import Foundation

/// Protocol defining cache operations for feature flags
public protocol Cache: Sendable {
    /// Get a flag by name
    /// - Parameter name: The flag name
    /// - Returns: A tuple of (enabled: Bool, exists: Bool)
    func get(_ name: String) async throws -> (enabled: Bool, exists: Bool)

    /// Get all flags from the cache
    /// - Returns: Array of all feature flags
    func getAll() async throws -> [FeatureFlag]

    /// Refresh the cache with new flags
    /// - Parameters:
    ///   - flags: The flags to store
    ///   - intervalAllowed: The refresh interval in seconds
    func refresh(_ flags: [FeatureFlag], intervalAllowed: Int) async throws

    /// Check if the cache should be refreshed
    /// - Returns: True if refresh is needed
    func shouldRefreshCache() async -> Bool

    /// Initialize the cache
    func initialize() async throws
}

/// In-memory cache implementation
public actor MemoryCache: Cache {
    private var flags: [String: FeatureFlag] = [:]
    private var cacheTTL: Int = 60
    private var nextRefresh: Date

    public init() {
        // Initialize with a time in the past to force initial refresh
        self.nextRefresh = Date().addingTimeInterval(-90)
    }

    public func get(_ name: String) async throws -> (enabled: Bool, exists: Bool) {
        if let flag = flags[name] {
            return (flag.enabled, true)
        }
        return (false, false)
    }

    public func getAll() async throws -> [FeatureFlag] {
        return Array(flags.values)
    }

    public func refresh(_ flags: [FeatureFlag], intervalAllowed: Int) async throws {
        self.flags.removeAll()

        for flag in flags {
            self.flags[flag.details.name] = flag
        }

        self.cacheTTL = intervalAllowed
        self.nextRefresh = Date().addingTimeInterval(Double(cacheTTL))
    }

    public func shouldRefreshCache() async -> Bool {
        return Date() > nextRefresh
    }

    public func initialize() async throws {
        self.cacheTTL = 60
        self.nextRefresh = Date().addingTimeInterval(-90)
    }
}
