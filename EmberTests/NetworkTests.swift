import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if SWIFT_PACKAGE
@testable import EmberCore
#else
@testable import Ember
#endif

private final class HTTPFixtures: @unchecked Sendable {
    struct Reply: Sendable { let status: Int; let body: String }
    private let lock = NSLock()
    private var replies: [String: [Reply]] = [:]
    private var counts: [String: Int] = [:]
    func install(_ replies: [Reply], path: String) { lock.lock(); defer { lock.unlock() }; self.replies[path] = replies; counts[path] = 0 }
    func next(_ path: String) -> Reply {
        lock.lock(); defer { lock.unlock() }
        counts[path, default: 0] += 1
        guard var choices = replies[path], let first = choices.first else { return Reply(status: 404, body: "null") }
        if choices.count > 1 { choices.removeFirst(); replies[path] = choices }
        return first
    }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[path, default: 0] }
}

private final class MockURLProtocol: URLProtocol {
    static let fixtures = HTTPFixtures()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let reply = Self.fixtures.next(url.path)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NetworkTests: XCTestCase, @unchecked Sendable {
    private func client() -> HNClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return HNClient(session: URLSession(configuration: config))
    }
    func testHTTPServerErrorRetriesOnce() async throws {
        let path = "/v0/topstories.json"
        MockURLProtocol.fixtures.install([.init(status: 503, body: "unavailable"), .init(status: 200, body: "[1,2]")], path: path)
        let ids = try await client().feedIDs(.top)
        XCTAssertEqual(ids, [1, 2])
        XCTAssertEqual(MockURLProtocol.fixtures.count(path), 2)
    }
    func testHTTPClientErrorDoesNotRetry() async {
        let path = "/v0/newstories.json"
        MockURLProtocol.fixtures.install([.init(status: 403, body: "forbidden")], path: path)
        do { _ = try await client().feedIDs(.new); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? AppError, .status(403)) }
        XCTAssertEqual(MockURLProtocol.fixtures.count(path), 1)
    }
    func testMalformedJSONFailsClearly() async {
        MockURLProtocol.fixtures.install([.init(status: 200, body: "<html>error</html>")], path: "/v0/beststories.json")
        do { _ = try await client().feedIDs(.best); XCTFail("Expected invalid response") }
        catch { XCTAssertEqual(error as? AppError, .invalidResponse) }
    }
    func testNullItemIsNotAnError() async throws {
        MockURLProtocol.fixtures.install([.init(status: 200, body: "null")], path: "/v0/item/991.json")
        let value = try await client().item(991, fresh: true)
        XCTAssertNil(value)
    }
    func testItemCacheAndExplicitRefresh() async throws {
        let path = "/v0/item/992.json"
        MockURLProtocol.fixtures.install([.init(status: 200, body: #"{"id":992,"score":1}"#), .init(status: 200, body: #"{"id":992,"score":2}"#)], path: path)
        let client = client()
        let first = try await client.item(992, fresh: false)
        let cached = try await client.item(992, fresh: false)
        let fresh = try await client.item(992, fresh: true)
        XCTAssertEqual(first?.score, 1); XCTAssertEqual(cached?.score, 1); XCTAssertEqual(fresh?.score, 2)
        XCTAssertEqual(MockURLProtocol.fixtures.count(path), 2)
    }
    func testCancelledRequestDoesNotStart() async {
        let service = client()
        let task = Task { try Task.checkCancellation(); return try await service.feedIDs(.ask) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
    }
    func testInvalidUsernameCannotChangeAPIPath() async {
        do { _ = try await client().user("../topstories"); XCTFail("Expected invalid user") }
        catch { XCTAssertEqual(error as? AppError, .missing) }
    }
}

final class LiveAPITests: XCTestCase, @unchecked Sendable {
    func testLiveFeedStoryCommentsUserAndSearch() async throws {
        guard ProcessInfo.processInfo.environment["EMBER_LIVE_TESTS"] == "1" else { throw XCTSkip("Set EMBER_LIVE_TESTS=1 to check the public APIs.") }
        let service = HNClient()
        for feed in Feed.allCases {
            let ids = try await service.feedIDs(feed)
            XCTAssertFalse(ids.isEmpty, feed.rawValue)
        }
        let ids = try await service.feedIDs(.top)
        let story = try await service.item(try XCTUnwrap(ids.first), fresh: true)
        let value = try XCTUnwrap(story)
        XCTAssertTrue(value.isStory)
        if let commentID = value.kids?.first {
            let comment = try await service.item(commentID, fresh: true)
            XCTAssertEqual(comment?.type, "comment")
        }
        let user = try await service.user("pg")
        XCTAssertEqual(user.id, "pg")
        let results = try await service.search("Swift", order: .relevant, period: .all, page: 0)
        XCTAssertFalse(results.items.isEmpty)
    }
}
