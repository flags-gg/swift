import Foundation
import FlagsSwift

/// Example demonstrating local flag overrides using environment variables
///
/// Environment variables prefixed with FLAGS_ will override remote flags.
/// You can use underscores, hyphens, or spaces in flag names - they're all normalized.
///
/// To run this example:
/// FLAGS_MY_FEATURE=true FLAGS_BETA_MODE=true swift run LocalOverrides
@main
struct LocalOverrides {
    static func main() async throws {
        print("Local Flag Overrides Example")
        print("=============================\n")

        // Print current environment flags
        print("Environment flags:")
        for (key, value) in ProcessInfo.processInfo.environment where key.hasPrefix("FLAGS_") {
            print("  \(key) = \(value)")
        }
        print()

        // Initialize the client without auth - will only use local flags
        let client = try Client.builder()
            .withErrorCallback { error in
                print("Error: \(error)")
            }
            .build()

        // Check flags that may be set via environment
        let features = ["my-feature", "my_feature", "my-feature", "beta-mode", "beta_mode"]

        print("Checking flags (all variations are normalized):")
        for feature in features {
            let enabled = await client.is(feature).enabled()
            print("  \(feature): \(enabled)")
        }

        // List all available flags
        print("\nAll available flags:")
        let allFlags = try await client.list()
        for flag in allFlags {
            print("  \(flag.details.name): \(flag.enabled)")
        }
    }
}
