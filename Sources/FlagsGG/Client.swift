import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
    private var inflight: Task<Void, Error>?
    private let errorCallback: (@Sendable (FlagError) -> Void)?
    private let urlSession: URLSession
    private var targetingKey: String?
    private var context: [String: [String]]

    internal init(
        baseURL: String,
        maxRetries: UInt32,
        auth: Auth?,
        cache: any Cache,
        errorCallback: (@Sendable (FlagError) -> Void)?,
        urlSession: URLSession = .shared,
        targetingKey: String? = nil,
        context: [String: [String]] = [:]
    ) {
        self.targetingKey = targetingKey
        self.context = context
        self.baseURL = baseURL
        self.maxRetries = maxRetries
        self.auth = auth
        self.cache = cache
        self.circuitState = CircuitState()
        self.errorCallback = errorCallback
        self.urlSession = urlSession

        // Fetch now, then check every 30s whether the server's refresh interval has passed (like the Kotlin SDK).
        // The loop holds the client weakly and stops once it's released.
        Task { [weak self] in
            while self != nil {
                await self?.refreshIfStale()
                try? await Task.sleep(nanoseconds: FlagsClient.refreshCheckInterval)
            }
        }
    }

    static let refreshCheckInterval: UInt64 = 30_000_000_000

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

    /// Change who rollouts are evaluated for (e.g. after login) and re-fetch,
    /// so cached values match the new user.
    public func setTargetingKey(_ key: String?) async {
        targetingKey = key
        do {
            try await refetch()
        } catch {
            handleError(.httpError(error))
        }
    }

    /// Replace the attributes targeting rules see (e.g. email, plan, groups) and re-fetch.
    public func setContext(_ attributes: [String: [String]]) async {
        context = attributes
        do {
            try await refetch()
        } catch {
            handleError(.httpError(error))
        }
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

        await refreshIfStale()

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
        await refreshIfStale()

        return try await cache.getAll()
    }

    /// Get the enabled status of multiple flags at once
    /// - Parameter names: Array of flag names
    /// - Returns: Dictionary mapping flag names to their enabled status
    public func getMultiple(_ names: [String]) async -> [String: Bool] {
        await refreshIfStale()

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

    /// Fetch if the server's refresh interval has passed. Concurrent callers share one fetch, so a check made
    /// while the first fetch is running waits for it rather than reading an empty cache.
    private func refreshIfStale() async {
        guard await cache.shouldRefreshCache() else { return }
        if let inflight {
            _ = try? await inflight.value
            return
        }
        let task = Task { try await self.refetch() }
        inflight = task
        defer { inflight = nil }
        do {
            try await task.value
        } catch {
            handleError(.httpError(error))
        }
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
        request.setValue("rollout", forHTTPHeaderField: "X-Flags-Capabilities")
        request.setValue(Rollout.encodeContext(targetingKey, context), forHTTPHeaderField: "X-Flags-Context")
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

                // Resolve rollouts on the name as the API sends it (the bucket must match
                // every other SDK), then normalize flag names to lowercase
                let key = targetingKey
                let apiFlags = apiResp.flags.map { flag in
                    FeatureFlag(
                        enabled: flag.enabled && Rollout.inRollout(flag.details.name, key, flag.rollout),
                        details: Details(
                            name: flag.details.name.lowercased(),
                            id: flag.details.id
                        )
                    )
                }

                try await cache.refresh(withLocal(apiFlags), intervalAllowed: apiResp.intervalAllowed)
                return
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    handleError(.httpError(error))
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000) * UInt64(attempt))
                    continue
                }

                // After exhausting attempts, update circuit state
                circuitState.failureCount += 1
                circuitState.lastFailure = Date()

                handleError(.httpError(error))

                // Keep the last fetched values (like the Kotlin SDK) rather than turning every remote flag off;
                // retry in 60s
                let lastKnown = (try? await cache.getAll()) ?? []
                try await cache.refresh(withLocal(lastKnown), intervalAllowed: 60)

                throw error
            }
        }

        if let error = lastError {
            throw error
        }
    }

    /// Env (FLAGS_*) flags override flags of the same name; env-only flags are added.
    private func withLocal(_ flags: [FeatureFlag]) -> [FeatureFlag] {
        var local = Dictionary(buildLocal().map { ($0.details.name, $0) }, uniquingKeysWith: { a, _ in a })
        var combined = flags.map { local.removeValue(forKey: $0.details.name) ?? $0 }
        combined.append(contentsOf: local.values)
        return combined
    }

    private func buildLocal() -> [FeatureFlag] {
        var result: [FeatureFlag] = []
        let env = ProcessInfo.processInfo.environment

        for (key, value) in env {
            guard key.hasPrefix("FLAGS_") else { continue }

            let enabled = ["true", "1", "on", "yes", "enabled"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
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
