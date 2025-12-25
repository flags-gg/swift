import Foundation

/// API response structure
private struct ApiResponse: Codable {
    let intervalAllowed: Int
    let flags: [FeatureFlag]
}

/// Circuit breaker state
private struct CircuitState {
    var isOpen: Bool = false
    var failureCount: UInt32 = 0
    var lastFailure: Date?
}

/// A flag wrapper for fluent API
public struct Flag {
    let name: String
    let client: FlagsClient

    /// Check if the flag is enabled
    /// - Returns: True if the flag is enabled
    public func enabled() async -> Bool {
        await client.isEnabled(name)
    }
}

/// Preferred type alias for FlagsClient
public typealias Flags = FlagsClient

/// Main client for interacting with Flags.gg
public actor FlagsClient {
    private let baseURL: String
    private let maxRetries: UInt32
    private let auth: Auth?
    private let cache: any Cache
    private var circuitState: CircuitState
    private var refreshInProgress: Bool = false
    private let errorCallback: (@Sendable (FlagError) -> Void)?
    private let urlSession: URLSession

    internal init(
        baseURL: String,
        maxRetries: UInt32,
        auth: Auth?,
        cache: any Cache,
        errorCallback: (@Sendable (FlagError) -> Void)?,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.maxRetries = maxRetries
        self.auth = auth
        self.cache = cache
        self.circuitState = CircuitState()
        self.errorCallback = errorCallback
        self.urlSession = urlSession
    }

    /// Create a client builder
    /// - Returns: A new ClientBuilder instance
    public static func builder() -> ClientBuilder {
        return ClientBuilder()
    }

    /// Get debug information about the client
    /// - Returns: A string with debug information
    public func debugInfo() -> String {
        return "Client { baseURL: \(baseURL), maxRetries: \(maxRetries), auth: \(String(describing: auth)) }"
    }

    /// Create a flag wrapper for fluent API
    /// - Parameter name: The flag name
    /// - Returns: A Flag instance
    public nonisolated func `is`(_ name: String) -> Flag {
        return Flag(name: name, client: self)
    }

    /// Check if a flag is enabled
    /// - Parameter name: The flag name
    /// - Returns: True if the flag is enabled
    public func isEnabled(_ name: String) async -> Bool {
        let normalizedName = name.lowercased()

        // Check if cache needs refresh
        if await cache.shouldRefreshCache() {
            if !refreshInProgress {
                refreshInProgress = true
                do {
                    try await refetch()
                } catch {
                    handleError(.httpError(error))
                }
                refreshInProgress = false
            }
        }

        // Check cache
        do {
            let (enabled, exists) = try await cache.get(normalizedName)
            return exists && enabled
        } catch {
            return false
        }
    }

    /// List all flags
    /// - Returns: Array of all feature flags
    public func list() async throws -> [FeatureFlag] {
        // Check if cache needs refresh
        if await cache.shouldRefreshCache() {
            if !refreshInProgress {
                refreshInProgress = true
                do {
                    try await refetch()
                } catch {
                    handleError(.httpError(error))
                }
                refreshInProgress = false
            }
        }

        return try await cache.getAll()
    }

    /// Get the enabled status of multiple flags at once
    /// - Parameter names: Array of flag names
    /// - Returns: Dictionary mapping flag names to their enabled status
    public func getMultiple(_ names: [String]) async -> [String: Bool] {
        // Check if cache needs refresh
        if await cache.shouldRefreshCache() {
            if !refreshInProgress {
                refreshInProgress = true
                do {
                    try await refetch()
                } catch {
                    handleError(.httpError(error))
                }
                refreshInProgress = false
            }
        }

        var results: [String: Bool] = [:]

        for name in names {
            let normalizedName = name.lowercased()
            do {
                let (enabled, exists) = try await cache.get(normalizedName)
                results[name] = exists && enabled
            } catch {
                results[name] = false
            }
        }

        return results
    }

    /// Check if all specified flags are enabled
    /// - Parameter names: Array of flag names
    /// - Returns: True if all flags are enabled
    public func allEnabled(_ names: [String]) async -> Bool {
        guard !names.isEmpty else { return true }

        let flags = await getMultiple(names)
        return names.allSatisfy { flags[$0] == true }
    }

    /// Check if any of the specified flags are enabled
    /// - Parameter names: Array of flag names
    /// - Returns: True if at least one flag is enabled
    public func anyEnabled(_ names: [String]) async -> Bool {
        guard !names.isEmpty else { return false }

        let flags = await getMultiple(names)
        return names.contains { flags[$0] == true }
    }

    private func handleError(_ error: FlagError) {
        errorCallback?(error)
    }

    private func fetchFlags() async throws -> ApiResponse {
        guard let auth = auth else {
            throw FlagError.authError("Authentication is required")
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/flags")!)
        request.httpMethod = "GET"
        request.setValue("Flags-Swift", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(auth.projectId, forHTTPHeaderField: "X-Project-ID")
        request.setValue(auth.agentId, forHTTPHeaderField: "X-Agent-ID")
        request.setValue(auth.environmentId, forHTTPHeaderField: "X-Environment-ID")
        request.timeoutInterval = 10

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FlagError.apiError("Invalid response type")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw FlagError.apiError("Unexpected status code: \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ApiResponse.self, from: data)
    }

    private func refetch() async throws {
        // If no auth is configured, only use local/env flags
        if auth == nil {
            let localFlags = buildLocal()
            try await cache.refresh(localFlags, intervalAllowed: 60)
            return
        }

        // Check circuit breaker
        if circuitState.isOpen {
            if let lastFailure = circuitState.lastFailure {
                let timeSinceFailure = Date().timeIntervalSince(lastFailure)
                if timeSinceFailure < 10 {
                    return
                }
            }
            // Attempt to close circuit
            circuitState.isOpen = false
            circuitState.failureCount = 0
        }

        // Implement retry logic
        var lastError: Error?
        let maxAttempts = max(maxRetries, 1)

        for attempt in 1...maxAttempts {
            do {
                let apiResp = try await fetchFlags()

                // Reset failure count on success
                circuitState.failureCount = 0

                // Normalize flag names to lowercase
                let apiFlags = apiResp.flags.map { flag in
                    FeatureFlag(
                        enabled: flag.enabled,
                        details: Details(
                            name: flag.details.name.lowercased(),
                            id: flag.details.id
                        )
                    )
                }

                let localFlags = buildLocal()

                // Combine API flags and local flags, with local overriding API
                var combinedFlags: [FeatureFlag] = []
                var localFlagsMap = Dictionary(uniqueKeysWithValues: localFlags.map { ($0.details.name, $0) })

                for apiFlag in apiFlags {
                    if let localFlag = localFlagsMap.removeValue(forKey: apiFlag.details.name) {
                        combinedFlags.append(localFlag)
                    } else {
                        combinedFlags.append(apiFlag)
                    }
                }

                // Add remaining local flags
                combinedFlags.append(contentsOf: localFlagsMap.values)

                try await cache.refresh(combinedFlags, intervalAllowed: apiResp.intervalAllowed)
                return
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    handleError(.httpError(error))
                    try await Task.sleep(nanoseconds: UInt64(100_000_000 * attempt))
                    continue
                }

                // After exhausting attempts, update circuit state
                circuitState.failureCount += 1
                circuitState.lastFailure = Date()

                handleError(.httpError(error))

                // Refresh with local flags
                let localFlags = buildLocal()
                try await cache.refresh(localFlags, intervalAllowed: 60)

                throw error
            }
        }

        if let error = lastError {
            throw error
        }
    }

    private func buildLocal() -> [FeatureFlag] {
        var result: [FeatureFlag] = []
        let env = ProcessInfo.processInfo.environment

        for (key, value) in env {
            guard key.hasPrefix("FLAGS_") else { continue }

            let enabled = value == "true"
            let flagNameEnv = String(key.dropFirst("FLAGS_".count))
            let flagNameLower = flagNameEnv.lowercased()

            // Create flag for lowercase version
            result.append(FeatureFlag(
                enabled: enabled,
                details: Details(
                    name: flagNameLower,
                    id: "local_\(flagNameLower)"
                )
            ))

            // Create variations with hyphens and spaces
            if flagNameLower.contains("_") {
                let flagNameHyphenated = flagNameLower.replacingOccurrences(of: "_", with: "-")
                result.append(FeatureFlag(
                    enabled: enabled,
                    details: Details(
                        name: flagNameHyphenated,
                        id: "local_\(flagNameHyphenated)"
                    )
                ))
            }

            if flagNameLower.contains("_") || flagNameLower.contains("-") {
                let flagNameSpaced = flagNameLower
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                result.append(FeatureFlag(
                    enabled: enabled,
                    details: Details(
                        name: flagNameSpaced,
                        id: "local_\(flagNameSpaced)"
                    )
                ))
            }
        }

        return result
    }
}
