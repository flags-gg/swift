import Foundation
import FlagsSwift

/// Basic example demonstrating how to use the FlagsSwift library
///
/// To run this example:
/// 1. Set up environment variables (optional):
///    export FLAGS_MY_FEATURE=true
/// 2. Run the example:
///    swift run Basic
@main
struct Basic {
    static func main() async throws {
        // Initialize the client
        let client = try Client.builder()
            .withAuth(Auth(
                projectId: "your-project-id",
                agentId: "your-agent-id",
                environmentId: "your-environment-id"
            ))
            .withErrorCallback { error in
                print("Error occurred: \(error)")
            }
            .build()

        // Check if a flag is enabled using the fluent API
        let isFeatureEnabled = await client.is("my-feature").enabled()
        print("Feature 'my-feature' is enabled: \(isFeatureEnabled)")

        // Check multiple flags at once
        let flags = await client.getMultiple(["feature-1", "feature-2", "feature-3"])
        print("\nMultiple flags:")
        for (name, enabled) in flags {
            print("  \(name): \(enabled)")
        }

        // Check if all flags are enabled
        let allEnabled = await client.allEnabled(["feature-1", "feature-2"])
        print("\nAll features enabled: \(allEnabled)")

        // Check if any flags are enabled
        let anyEnabled = await client.anyEnabled(["premium-feature", "beta-feature"])
        print("Any premium/beta features enabled: \(anyEnabled)")

        // List all flags
        do {
            let allFlags = try await client.list()
            print("\nAll flags:")
            for flag in allFlags {
                print("  \(flag.details.name) (\(flag.details.id)): \(flag.enabled)")
            }
        } catch {
            print("Failed to list flags: \(error)")
        }
    }
}
