import XCTest
@testable import FlagsGG

final class FlagsGGTests: XCTestCase {
    func testAuthCreation() {
        let auth = Auth(
            projectId: "test-project",
            agentId: "test-agent",
            environmentId: "development"
        )

        XCTAssertEqual(auth.projectId, "test-project")
        XCTAssertEqual(auth.agentId, "test-agent")
        XCTAssertEqual(auth.environmentId, "development")
    }

    func testFlagCreation() {
        let details = Details(name: "test-flag", id: "flag-123")
        let flag = FeatureFlag(enabled: true, details: details)

        XCTAssertTrue(flag.enabled)
        XCTAssertEqual(flag.details.name, "test-flag")
        XCTAssertEqual(flag.details.id, "flag-123")
    }

    func testClientBuilderValidation() async throws {
        // Empty project ID should fail
        let authWithEmptyProject = Auth(
            projectId: "",
            agentId: "test-agent",
            environmentId: "dev"
        )

        XCTAssertThrowsError(try Client.builder().withAuth(authWithEmptyProject).build()) { error in
            if case let FlagError.builderError(message) = error {
                XCTAssertTrue(message.contains("Project ID"))
            } else {
                XCTFail("Expected builderError")
            }
        }

        // Empty agent ID should fail
        let authWithEmptyAgent = Auth(
            projectId: "test-project",
            agentId: "",
            environmentId: "dev"
        )

        XCTAssertThrowsError(try Client.builder().withAuth(authWithEmptyAgent).build()) { error in
            if case let FlagError.builderError(message) = error {
                XCTAssertTrue(message.contains("Agent ID"))
            } else {
                XCTFail("Expected builderError")
            }
        }

        // Too many retries should fail
        let auth = Auth(
            projectId: "test-project",
            agentId: "test-agent",
            environmentId: "dev"
        )

        XCTAssertThrowsError(try Client.builder().withAuth(auth).withMaxRetries(15).build()) { error in
            if case let FlagError.builderError(message) = error {
                XCTAssertTrue(message.contains("Max retries"))
            } else {
                XCTFail("Expected builderError")
            }
        }
    }

    func testClientBuilderSuccess() async throws {
        let auth = Auth(
            projectId: "test-project",
            agentId: "test-agent",
            environmentId: "development"
        )

        let client = try Client.builder()
            .withAuth(auth)
            .withMaxRetries(5)
            .build()

        let debugInfo = await client.debugInfo()
        XCTAssertTrue(debugInfo.contains("test-project"))
    }

    func testClientWithoutAuth() async throws {
        // Should succeed without auth (will only use local flags)
        let client = try Client.builder().build()

        let debugInfo = await client.debugInfo()
        XCTAssertTrue(debugInfo.contains("https://api.flags.gg"))
    }

    func testMemoryCache() async throws {
        let cache = MemoryCache()

        // Initially should need refresh
        let shouldRefresh = await cache.shouldRefreshCache()
        XCTAssertTrue(shouldRefresh)

        // Add some flags
        let flags = [
            FeatureFlag(
                enabled: true,
                details: Details(name: "test-flag", id: "flag-1")
            ),
            FeatureFlag(
                enabled: false,
                details: Details(name: "disabled-flag", id: "flag-2")
            )
        ]

        try await cache.refresh(flags, intervalAllowed: 60)

        // Should not need refresh immediately after refreshing
        let shouldRefreshAfter = await cache.shouldRefreshCache()
        XCTAssertFalse(shouldRefreshAfter)

        // Get a flag
        let (enabled, exists) = try await cache.get("test-flag")
        XCTAssertTrue(exists)
        XCTAssertTrue(enabled)

        // Get a disabled flag
        let (disabledEnabled, disabledExists) = try await cache.get("disabled-flag")
        XCTAssertTrue(disabledExists)
        XCTAssertFalse(disabledEnabled)

        // Get non-existent flag
        let (nonExistEnabled, nonExistExists) = try await cache.get("non-existent")
        XCTAssertFalse(nonExistExists)
        XCTAssertFalse(nonExistEnabled)

        // Get all flags
        let allFlags = try await cache.getAll()
        XCTAssertEqual(allFlags.count, 2)
    }

    func testFlagErrorDescriptions() {
        let httpError = FlagError.httpError(NSError(domain: "test", code: 500))
        XCTAssertTrue(httpError.description.contains("HTTP error"))

        let cacheError = FlagError.cacheError("Cache failed")
        XCTAssertTrue(cacheError.description.contains("Cache error"))

        let authError = FlagError.authError("No credentials")
        XCTAssertTrue(authError.description.contains("authentication"))

        let apiError = FlagError.apiError("500 error")
        XCTAssertTrue(apiError.description.contains("API error"))

        let builderError = FlagError.builderError("Invalid config")
        XCTAssertTrue(builderError.description.contains("Builder error"))
    }
}
