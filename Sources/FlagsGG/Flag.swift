import Foundation

/// Details about a feature flag
public struct Details: Codable, Sendable {
    public let name: String
    public let id: String

    public init(name: String, id: String) {
        self.name = name
        self.id = id
    }
}

/// A feature flag with its enabled state and details
public struct FeatureFlag: Codable, Sendable {
    public let enabled: Bool
    public let details: Details

    public init(enabled: Bool, details: Details) {
        self.enabled = enabled
        self.details = details
    }
}
