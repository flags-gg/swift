import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Builder for creating a Client instance
public struct ClientBuilder: Sendable {
    private var baseURL: String = "https://api.flags.gg"
    private var maxRetries: UInt32 = 3
    private var auth: Auth?
    private var errorCallback: (@Sendable (FlagError) -> Void)?
    private var targetingKey: String?
    private var context: [String: [String]] = [:]
    private var urlSession: URLSession = .shared
    private var cache: (any Cache)?
    private var sqlitePath: String?

    internal init() {}

    private func with(_ change: (inout ClientBuilder) -> Void) -> ClientBuilder {
        var copy = self
        change(&copy)
        return copy
    }

    /// Set the base URL for the API
    public func withBaseURL(_ baseURL: String) -> ClientBuilder { with { $0.baseURL = baseURL } }

    /// Set the maximum number of retries
    public func withMaxRetries(_ maxRetries: UInt32) -> ClientBuilder { with { $0.maxRetries = maxRetries } }

    /// Set the authentication credentials
    public func withAuth(_ auth: Auth) -> ClientBuilder { with { $0.auth = auth } }

    /// Set a callback for error handling
    public func withErrorCallback(_ callback: @escaping @Sendable (FlagError) -> Void) -> ClientBuilder {
        with { $0.errorCallback = callback }
    }

    /// Who percentage rollouts are evaluated for, e.g. the signed-in user's id.
    /// Defaults to a stable per-install id (`Rollout.installId()`), so each phone keeps its answer.
    public func withTargetingKey(_ key: String?) -> ClientBuilder { with { $0.targetingKey = key } }

    /// Attributes for targeting rules, evaluated by the server, e.g. ["email": [email], "groups": ["beta"]].
    public func withContext(_ attributes: [String: [String]]) -> ClientBuilder { with { $0.context = attributes } }

    /// Single-valued attributes for targeting rules, e.g. ["email": email, "plan": "pro"].
    public func withContext(_ attributes: [String: String]) -> ClientBuilder { withContext(attributes.mapValues { [$0] }) }

    /// Use your own cache implementation.
    public func withCache(_ cache: any Cache) -> ClientBuilder { with { $0.cache = cache; $0.sqlitePath = nil } }

    /// Keep flags in memory only (the default).
    public func withMemoryCache() -> ClientBuilder { with { $0.cache = MemoryCache(); $0.sqlitePath = nil } }

    #if canImport(SQLite3)
    /// Keep flags in a SQLite file, so the last fetched values survive an app restart.
    public func withSQLiteCache(path: String = "flags_cache.db") -> ClientBuilder {
        with { $0.sqlitePath = path; $0.cache = nil }
    }
    #endif

    internal func withURLSession(_ session: URLSession) -> ClientBuilder { with { $0.urlSession = session } }

    /// Build the client
    /// - Returns: A configured FlagsClient instance
    /// - Throws: FlagError if validation fails
    public func build() throws -> FlagsClient {
        // Validate auth if provided
        if let auth = auth {
            if auth.projectId.trimmingCharacters(in: .whitespaces).isEmpty {
                throw FlagError.builderError("Project ID cannot be empty")
            }
            if auth.agentId.trimmingCharacters(in: .whitespaces).isEmpty {
                throw FlagError.builderError("Agent ID cannot be empty")
            }
            if auth.environmentId.trimmingCharacters(in: .whitespaces).isEmpty {
                throw FlagError.builderError("Environment ID cannot be empty")
            }
        }

        // Validate base URL
        if baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
            throw FlagError.builderError("Base URL cannot be empty")
        }

        // Validate max retries
        if maxRetries > 10 {
            throw FlagError.builderError("Max retries cannot exceed 10")
        }

        #if canImport(SQLite3)
        let finalCache: any Cache = try sqlitePath.map { try SQLiteCache(path: $0) } ?? cache ?? MemoryCache()
        #else
        let finalCache: any Cache = cache ?? MemoryCache()
        #endif

        return FlagsClient(
            baseURL: baseURL,
            maxRetries: maxRetries,
            auth: auth,
            cache: finalCache,
            errorCallback: errorCallback,
            urlSession: urlSession,
            targetingKey: targetingKey ?? Rollout.installId(),
            context: context
        )
    }
}
