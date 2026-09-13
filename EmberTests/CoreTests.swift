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

final class ModelTests: XCTestCase {
    func testDeletedItemDecodesWithoutOptionalFields() throws {
        let item = try JSONDecoder().decode(HNItem.self, from: Data(#"{"id":42,"deleted":true}"#.utf8))
        XCTAssertFalse(item.isVisible)
        XCTAssertNil(item.articleURL)
        XCTAssertEqual(item.commentCount, 0)
    }
    func testUnknownFieldsAndHTMLTitles() throws {
        let data = Data(#"{"id":1,"type":"story","title":"A &amp; B &#x1F680;","unknown":9}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(HNItem.self, from: data).displayTitle, "A & B 🚀")
    }
    func testUnsafeURLsAreRejected() {
        for url in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,hello", "https://", "https://user:pass@example.com", "emberhn://item/1"] {
            XCTAssertNil(WebURL.validated(url), url)
        }
        XCTAssertEqual(WebURL.validated("https://example.com/a?q=one&two=2")?.host, "example.com")
        XCTAssertNotNil(WebURL.validated("http://example.com"))
    }
    func testDeepLinksValidateHostAndPositiveID() {
        XCTAssertEqual(HNLinks.itemID(from: HNLinks.item(42)), 42)
        XCTAssertEqual(HNLinks.itemID(from: URL(string: "emberhn://item/42")!), 42)
        XCTAssertNil(HNLinks.itemID(from: URL(string: "https://evil.com/item?id=42")!))
        XCTAssertNil(HNLinks.itemID(from: URL(string: "https://news.ycombinator.com/item?id=-1")!))
        XCTAssertNil(HNLinks.itemID(from: URL(string: "emberhn://item/0")!))
    }
    func testSearchEscapesQueryAndAppliesDateWindow() {
        let url = HNClient.searchURL("C++ & Swift? #tag", order: .recent, period: .week, page: 2, now: Date(timeIntervalSince1970: 1_000_000))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let values = Dictionary(components.queryItems!.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(components.path, "/api/v1/search_by_date")
        XCTAssertEqual(values["query"], "C++ & Swift? #tag")
        XCTAssertEqual(values["numericFilters"], "created_at_i>395200")
        XCTAssertEqual(values["page"], "2")
    }
    func testSearchHandlesNullsAndInvalidIDs() throws {
        let data = Data(#"{"hits":[{"objectID":"1","title":"First","url":null,"points":null},{"objectID":"invalid"}],"page":0,"nbPages":1,"nbHits":2}"#.utf8)
        let result = try JSONDecoder().decode(SearchResponse.self, from: data).result
        XCTAssertEqual(result.items.map(\.id), [1])
    }
    func testHTMLFormattingAndEntityDecoding() {
        let runs = HNHTML.runs("Hello &amp; goodbye<p><b>Bold</b> <i>italic</i> <a href=\"https://example.com?a=1&amp;b=2\">link</a><pre><code>let x = 1\n  x + 1</code></pre>")
        XCTAssertTrue(runs.contains { $0.bold && $0.text.contains("Bold") })
        XCTAssertTrue(runs.contains { $0.italic && $0.text.contains("italic") })
        XCTAssertEqual(runs.first { $0.link != nil }?.link?.absoluteString, "https://example.com?a=1&b=2")
        XCTAssertTrue(runs.contains { $0.code && $0.text.contains("\n  x + 1") })
        XCTAssertTrue(HNHTML.plainText("a<p>b").contains("a\n\nb"))
    }
    func testHTMLNeverExecutesOrLinksScripts() {
        let html = "<script>alert(1)</script>safe<a href='javascript:alert(2)'>click</a><img src='https://tracker.test/pixel'>"
        XCTAssertEqual(HNHTML.plainText(html), "safeclick")
        XCTAssertTrue(HNHTML.runs(html).allSatisfy { $0.link == nil })
        XCTAssertEqual(HNHTML.decodeEntities("&amp;lt; &#39; &#x1F642; &#999999999;"), "&lt; ' 🙂 &#999999999;")
    }
    func testRelativeHNLinksAreResolved() {
        XCTAssertEqual(HNHTML.runs("<a href='item?id=42'>thread</a>").first?.link, HNLinks.item(42))
    }
    func testHistoryIsBoundedAndMostRecentFirst() {
        var archive = ReadingArchive()
        for id in 1...550 { archive.record(HNItem(id: id)) }
        archive.record(HNItem(id: 540, title: "Updated"))
        XCTAssertEqual(archive.history.count, 500)
        XCTAssertEqual(archive.history.first?.id, 540)
        XCTAssertEqual(archive.history.filter { $0.id == 540 }.count, 1)
    }
    func testBookmarksPreserveOrderWhenRefreshed() {
        var archive = ReadingArchive()
        archive.toggleBookmark(HNItem(id: 1, title: "Old"))
        archive.toggleBookmark(HNItem(id: 2))
        archive.record(HNItem(id: 1, title: "New"))
        XCTAssertEqual(archive.bookmarks.map(\.id), [2, 1])
        XCTAssertEqual(archive.bookmarks.last?.item.title, "New")
        archive.toggleBookmark(HNItem(id: 1))
        XCTAssertEqual(archive.bookmarks.map(\.id), [2])
    }
}

actor MockService: HNService {
    var ids: [Int] = Array(1...65)
    var values: [Int: HNItem] = [:]
    var failingIDs: Set<Int> = []
    var feedFailure = false
    var active = 0
    var maximumActive = 0
    var delay: Duration = .milliseconds(1)
    var searchDelays: [String: Duration] = [:]

    func setFailure(_ ids: Set<Int>) { failingIDs = ids }
    func setFeedFailure(_ value: Bool) { feedFailure = value }
    func setItems(_ items: [HNItem], ids: [Int]? = nil) { values = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }); if let ids { self.ids = ids } }
    func setSearchDelays(_ delays: [String: Duration]) { searchDelays = delays }
    func feedIDs(_ feed: Feed) async throws -> [Int] { if feedFailure { throw URLError(.notConnectedToInternet) }; return ids }
    func item(_ id: Int, fresh: Bool) async throws -> HNItem? {
        active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: delay)
        if failingIDs.contains(id) { throw URLError(.timedOut) }
        return values[id] ?? HNItem(id: id, type: "story", by: "author", title: "Story \(id)")
    }
    func user(_ name: String) async throws -> HNUser { HNUser(id: name, created: 1, karma: 42) }
    func listing(_ url: URL) async throws -> HNListingPage { HNListingPage(items: [], next: nil) }
    func archive(_ feed: Feed, window: ArchiveWindow, page: Int) async throws -> SearchPage {
        SearchPage(items: [HNItem(id: 9000 + page, type: "story", title: "Archive page \(page)")], page: page, totalPages: 2, totalHits: 2)
    }
    func search(_ query: String, order: SearchOrder, period: SearchPeriod, page: Int) async throws -> SearchPage {
        if let delay = searchDelays[query] { try await Task.sleep(for: delay) }
        return SearchPage(items: [HNItem(id: query == "new" ? 2 : 1, type: "story", title: query)], page: page, totalPages: 1, totalHits: 1)
    }
}

@MainActor final class StateTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testBatchesPreserveOrderAndBoundConcurrency() async throws {
        let service = MockService()
        let ids = Array((1...24).reversed())
        let items = try await service.items(ids)
        let maximum = await service.maximumActive
        XCTAssertEqual(items.map(\.id), ids)
        XCTAssertLessThanOrEqual(maximum, 8)
    }
    func testPaginationFailureDoesNotLoseStories() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let service = MockService()
        let model = FeedModel(service: service, cache: FeedCache(directory: path))
        await model.load(.top)
        XCTAssertEqual(model.items.count, 30)
        await service.setFailure([35])
        await model.loadMore()
        XCTAssertEqual(model.items.count, 30)
        XCTAssertNotNil(model.error)
        await service.setFailure([])
        await model.loadMore()
        XCTAssertEqual(model.items.map(\.id), Array(1...60))
        await model.loadMore()
        XCTAssertEqual(model.items.count, 65)
        XCTAssertFalse(model.hasMore)
    }
    func testOfflineFeedRestoresLastSuccessfulSnapshot() async {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let service = MockService(), cache = FeedCache(directory: path)
        let first = FeedModel(service: service, cache: cache)
        await first.load(.top)
        await service.setFeedFailure(true)
        let second = FeedModel(service: service, cache: cache)
        await second.load(.top)
        XCTAssertEqual(second.items.count, 30)
        XCTAssertTrue(second.isCached)
        XCTAssertNotNil(second.error)
    }
    func testRefreshFailureKeepsExistingStories() async {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let service = MockService()
        let actual = FeedModel(service: service, cache: FeedCache(directory: path))
        await actual.load(.top)
        await service.setFeedFailure(true)
        await actual.refresh()
        XCTAssertEqual(actual.items.count, 30)
        XCTAssertFalse(actual.isLoading)
    }
    func testLateSearchCannotReplaceNewerResults() async throws {
        let service = MockService()
        await service.setSearchDelays(["old": .milliseconds(80), "new": .milliseconds(1)])
        let model = SearchModel(service: service)
        model.query = "old"
        let old = Task { await model.search(debounce: false) }
        try await Task.sleep(for: .milliseconds(10))
        model.query = "new"
        await model.search(debounce: false)
        await old.value
        XCTAssertEqual(model.items.first?.title, "new")
    }
    func testClearingSearchClearsResults() async {
        let model = SearchModel(service: MockService())
        model.query = "old"; await model.search(debounce: false)
        model.query = "   "; await model.search(debounce: false)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.hasSearched)
        XCTAssertFalse(model.isLoading)
    }
    func testThreadLoadingCollapseAndBlockedAuthors() async {
        let service = MockService()
        let story = HNItem(id: 1, type: "story", kids: [2, 3])
        await service.setItems([story, HNItem(id: 2, type: "comment", by: "alice", text: "Parent", kids: [4]), HNItem(id: 3, type: "comment", by: "bob", text: "Second"), HNItem(id: 4, type: "comment", by: "carol", text: "Child")])
        let model = DiscussionModel(story: story, service: service)
        await model.load()
        XCTAssertEqual(model.rows(blocked: []).map(\.id), ["comment-2", "comment-4", "comment-3"])
        model.toggle(2)
        XCTAssertEqual(model.rows(blocked: []).map(\.id), ["comment-2", "comment-3"])
        model.toggle(2)
        XCTAssertEqual(model.rows(blocked: ["alice"]).map(\.id), ["comment-3"])
    }
    func testDeletedCommentsKeepChildrenReachable() async {
        let service = MockService()
        let story = HNItem(id: 1, type: "story", kids: [2])
        await service.setItems([story, HNItem(id: 2, type: "comment", kids: [3], deleted: true), HNItem(id: 3, type: "comment", text: "Still here")])
        let model = DiscussionModel(story: story, service: service)
        await model.load()
        XCTAssertEqual(model.rows(blocked: []).map(\.id), ["comment-3"])
        XCTAssertEqual(model.rows(blocked: []).first?.depth, 0)
    }
    func testDelayedCommentsAreHiddenWithoutReorderingVisibleComments() async {
        let service = MockService()
        let story = HNItem(id: 1, type: "story", kids: [2, 3, 4])
        await service.setItems([story, HNItem(id: 2, type: "comment", text: "<p>[delayed]</p>"), HNItem(id: 3, type: "comment", text: "First visible"), HNItem(id: 4, type: "comment", text: "Second visible")])
        let model = DiscussionModel(story: story, service: service)
        await model.load()
        XCTAssertEqual(model.rows(blocked: []).map(\.id), ["comment-3", "comment-4"])
    }
    func testArchivePaginationAndReturnToLiveFeed() async {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let model = FeedModel(service: MockService(), cache: FeedCache(directory: path))
        await model.load(.top, window: ArchiveWindow(after: 0, before: 100))
        XCTAssertEqual(model.items.map(\.id), [9000])
        await model.loadMore()
        XCTAssertEqual(model.items.map(\.id), [9000, 9001])
        XCTAssertFalse(model.hasMore)
        await model.load(.top)
        XCTAssertEqual(model.items.first?.id, 1)
        XCTAssertFalse(model.items.contains { $0.id == 9000 })
    }

    func testWholeDiscussionLoadsBeyondFirstPageAndHandlesCycles() async {
        let service = MockService()
        let roots = Array(2...62)
        let story = HNItem(id: 1, type: "story", kids: roots)
        await service.setItems([story] + roots.map { HNItem(id: $0, type: "comment", text: "Root", kids: [$0 + 100]) } + roots.map { HNItem(id: $0 + 100, type: "comment", text: "Reply", kids: [1]) })
        let model = DiscussionModel(story: story, service: service)
        await model.load()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.comments.count, 122)
        XCTAssertEqual(model.rows(blocked: []).count, 122)
        XCTAssertEqual(model.rows(blocked: []).suffix(2).map(\.id), ["comment-62", "comment-162"])
    }
    func testAtomicPersistenceAndRapidMutations() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = ReadingStore(directory: path)
        for id in 1...30 { store.toggleBookmark(HNItem(id: id)) }
        store.record(HNItem(id: 20, title: "Fresh")); store.block("spammer")
        await store.flush()
        let restored = ReadingStore(directory: path)
        XCTAssertEqual(restored.bookmarks.count, 30)
        XCTAssertEqual(restored.history.first?.id, 20)
        XCTAssertTrue(restored.isBlocked("spammer"))
        XCTAssertNil(store.error)
    }
    func testCorruptStoreIsPreservedUntilExplicitRecovery() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let url = path.appendingPathComponent("reading-library.json")
        let original = Data("broken JSON".utf8)
        try original.write(to: url)
        let store = ReadingStore(directory: path)
        store.toggleBookmark(HNItem(id: 1)); await store.flush()
        XCTAssertTrue(store.needsRecovery)
        XCTAssertEqual(try Data(contentsOf: url), original)
        store.recover(); await store.flush()
        XCTAssertFalse(store.needsRecovery)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: path.path).count, 2)
    }
    func testWriterRejectsOutOfOrderRevisions() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let url = path.appendingPathComponent("state.json"), writer = ArchiveWriter(url: path.appendingPathComponent("state.json"))
        var latest = ReadingArchive(); latest.toggleBookmark(HNItem(id: 2))
        try await writer.write(latest, revision: 2)
        try await writer.write(ReadingArchive(), revision: 1)
        XCTAssertEqual(try ArchiveFile.read(at: url).bookmarks.first?.id, 2)
    }
}
