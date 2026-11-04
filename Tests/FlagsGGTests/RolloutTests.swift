import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FlagsGG

/// Serves one canned /flags response and records the last request's capabilities header.
final class MockFlagsProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var capabilities: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.capabilities = request.value(forHTTPHeaderField: "X-Flags-Capabilities")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
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

        await client.setTargetingKey("user-2") // bucket 82: out
        let afterSwitch = await client.isEnabled("new-checkout")
        XCTAssertFalse(afterSwitch)
    }
}
