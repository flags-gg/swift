import Foundation

/// Authentication credentials for the Flags.gg API
public struct Auth: Sendable {
    public let projectId: String
    public let agentId: String
    public let environmentId: String

    public init(projectId: String, agentId: String, environmentId: String) {
        self.projectId = projectId
        self.agentId = agentId
        self.environmentId = environmentId
    }
}
