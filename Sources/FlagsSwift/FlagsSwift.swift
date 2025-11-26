/// FlagsSwift - Swift Library for Flags.gg
///
/// This library provides a Swift client for interacting with the Flags.gg feature flag service.
///
/// ## Example Usage
///
/// ```swift
/// import FlagsSwift
///
/// // Initialize the client
/// let client = try Client.builder()
///     .withAuth(Auth(
///         projectId: "your-project-id",
///         agentId: "your-agent-id",
///         environmentId: "your-environment-id"
///     ))
///     .build()
///
/// // Check if a flag is enabled
/// let isEnabled = await client.is("my-feature").enabled()
///
/// // List all flags
/// let flags = try await client.list()
/// ```
public struct FlagsSwift {
    /// The version of the FlagsSwift library
    public static let version = "0.1.0"
}
