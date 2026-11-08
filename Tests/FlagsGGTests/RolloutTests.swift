import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FlagsGG

/// Serves one canned /flags response and records the last request's capabilities header.
final class MockFlagsProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var capabilities: String?
    nonisolated(unsafe) static var context: String?
    nonisolated(unsafe) static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.capabilities = request.value(forHTTPHeaderField: "X-Flags-Capabilities")
        Self.context = request.value(forHTTPHeaderField: "X-Flags-Context")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RolloutTests: XCTestCase {
    // Shared with the API (orchestrator internal/flags/rollout_test.go) and every SDK; must never drift.
    func testBucketMatchesSharedVectors() {
        let vectors: [(String, String, Int)] = [
            ("new-checkout", "user-1", 63),
            ("new-checkout", "user-2", 82),
            ("teams", "visitor-abc", 12),
            ("", "", 53),
            ("émoji ✓", "ключ", 95),
        ]
        for (flag, key, want) in vectors {
            XCTAssertEqual(Rollout.bucket(flag, key), want, "\(flag):\(key)")
        }
    }

    func testPercentageAndFailClosed() {
        XCTAssertFalse(Rollout.inRollout("new-checkout", "user-1", 63)) // bucket 63
        XCTAssertTrue(Rollout.inRollout("new-checkout", "user-1", 64))
        XCTAssertFalse(Rollout.inRollout("new-checkout", nil, 50))
        XCTAssertTrue(Rollout.inRollout("new-checkout", nil, nil))
        XCTAssertFalse(Rollout.inRollout("new-checkout", "user-1", 0))
    }

    func testEncodesUserForTargetingRules() throws {
        let encoded = Rollout.encodeContext("u-1", ["email": ["ana@acme.com"], "groups": ["beta", "ünï"]])
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(decoded["key"] as? String, "u-1")
        XCTAssertEqual(decoded["groups"] as? [String], ["beta", "ünï"])
    }

    func testInstallIdIsStable() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "flagsgg-tests-\(UUID().uuidString)"))
        let first = Rollout.installId(defaults)
        XCTAssertEqual(Rollout.installId(defaults), first)
    }

    func testClientResolvesRolloutForTargetingKey() async throws {
        // lookups stay case-insensitive; the bucket uses the name as the API sends it
        MockFlagsProtocol.body = Data(#"{"intervalAllowed":60,"flags":[{"enabled":true,"rollout":64,"details":{"name":"new-checkout","id":"1"}}]}"#.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockFlagsProtocol.self]

        let client = try FlagsClient.builder()
            .withAuth(Auth(projectId: "p", agentId: "a", environmentId: "e"))
            .withURLSession(URLSession(configuration: config))
            .withTargetingKey("user-1") // bucket 63 < 64: in
            .build()

        let inRollout = await client.isEnabled("New-Checkout")
        XCTAssertTrue(inRollout)
        XCTAssertEqual(MockFlagsProtocol.capabilities, "rollout")
        XCTAssertNotNil(MockFlagsProtocol.context)

        await client.setTargetingKey("user-2") // bucket 82: out
        let afterSwitch = await client.isEnabled("new-checkout")
        XCTAssertFalse(afterSwitch)
    }

    func testKeepsLastValuesWhenAPIIsDown() async throws {
        MockFlagsProtocol.status = 200
        MockFlagsProtocol.body = Data(#"{"intervalAllowed":60,"flags":[{"enabled":true,"details":{"name":"dark-mode","id":"1"}}]}"#.utf8)
        defer { MockFlagsProtocol.status = 200 }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockFlagsProtocol.self]

        let client = try FlagsClient.builder()
            .withAuth(Auth(projectId: "p", agentId: "a", environmentId: "e"))
            .withURLSession(URLSession(configuration: config))
            .withMaxRetries(1)
            .build()

        let before = await client.isEnabled("dark-mode")
        XCTAssertTrue(before)

        MockFlagsProtocol.status = 500
        await client.setContext(["plan": ["pro"]]) // re-fetch fails
        let during = await client.isEnabled("dark-mode")
        XCTAssertTrue(during)
    }

    func testEnvOverridesAcceptTruthyValues() async throws {
        setenv("FLAGS_YES_FLAG", "Yes", 1)
        setenv("FLAGS_ONE_FLAG", "1", 1)
        setenv("FLAGS_OFF_FLAG", "off", 1)
        defer { for name in ["FLAGS_YES_FLAG", "FLAGS_ONE_FLAG", "FLAGS_OFF_FLAG"] { unsetenv(name) } }

        let client = try FlagsClient.builder().build() // no auth: env flags only
        let yes = await client.isEnabled("yes-flag")
        let one = await client.isEnabled("One Flag")
        let off = await client.isEnabled("off_flag")
        XCTAssertTrue(yes)
        XCTAssertTrue(one)
        XCTAssertFalse(off)
    }

    #if canImport(SQLite3)
    func testSQLiteCacheSurvivesRestart() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("flags-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = try SQLiteCache(path: path)
        try await first.refresh([FeatureFlag(enabled: true, details: Details(name: "dark-mode", id: "1"))], intervalAllowed: 60)
        let fresh = await first.shouldRefreshCache()
        XCTAssertFalse(fresh)

        let reopened = try SQLiteCache(path: path)
        let flag = try await reopened.get("dark-mode")
        XCTAssertTrue(flag.enabled && flag.exists)
        let missing = try await reopened.get("nope")
        XCTAssertFalse(missing.exists)
        let all = try await reopened.getAll()
        XCTAssertEqual(all.map(\.details.id), ["1"])
    }
    #endif
}
