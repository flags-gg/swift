/// FlagsGG - Swift Library for Flags.gg
///
/// This library provides a Swift client for interacting with the Flags.gg feature flag service.
///
/// ## Example Usage
///
/// ```swift
/// import FlagsGG
///
/// // Initialize the client
/// let client = try Flags.builder()
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
public struct FlagsGG {
    /// The version of the FlagsGG library
    public static let version = "0.1.0"
}
