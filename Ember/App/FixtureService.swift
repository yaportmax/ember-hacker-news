// Deterministic, explicitly opt-in fixtures for previews and UI tests.
// This entire file is excluded by conditional compilation from Release builds.
#if DEBUG
import Foundation

struct FixtureService: HNService {
    static let stories: [HNItem] = [
        HNItem(id: 1001, type: "story", by: "julia", time: 1_789_118_000, title: "A small web is a beautiful web", url: "https://example.com/small-web", score: 284, descendants: 4, kids: [2001, 2002, 2003]),
        HNItem(id: 1002, type: "story", by: "marcel", time: 1_789_114_400, title: "Building a search engine from scratch", url: "https://example.com/search", score: 196, descendants: 42),
        HNItem(id: 1003, type: "story", by: "sara", time: 1_789_110_800, title: "Show HN: I made a tiny music synthesizer", url: "https://example.com/synth", score: 172, descendants: 31),
        HNItem(id: 1004, type: "story", by: "tomas", time: 1_789_107_200, title: "Ask HN: What are you working on this month?", text: "What have you been making lately?<p>Small projects are welcome, too.", score: 139, descendants: 0),
        HNItem(id: 1005, type: "story", by: "maya", time: 1_789_103_600, title: "The quiet craft of software maintenance", url: "https://example.com/maintenance", score: 121, descendants: 27),
        HNItem(id: 1006, type: "story", by: "eli", time: 1_789_100_000, title: "Why old maps still matter", url: "https://example.com/maps", score: 97, descendants: 19)
    ]
    static let comments: [HNItem] = [
        HNItem(id: 2001, type: "comment", by: "alex", time: 1_789_118_900, text: "The best part of a personal website is that it feels like a place someone lives.<p>More gardens, fewer billboards.", kids: [3001], parent: 1001),
        HNItem(id: 2002, type: "comment", by: "julia", time: 1_789_119_200, text: "This is what I miss about the early web. You could spend an afternoon following links and end up somewhere completely unexpected.", parent: 1001),
        HNItem(id: 2003, type: "comment", by: "noah", time: 1_789_119_800, text: "A good reminder to <i>make things for people</i>, even if the audience is small.<p>I started with a single HTML file. It was enough.", parent: 1001),
        HNItem(id: 3001, type: "comment", by: "riley", time: 1_789_119_000, text: "Exactly. Small and useful is a perfectly good ambition.", parent: 2001)
    ]
    func feedIDs(_ feed: Feed) async throws -> [Int] {
        if ProcessInfo.processInfo.arguments.contains("--offline") { throw URLError(.notConnectedToInternet) }
        if ProcessInfo.processInfo.arguments.contains("--large-discussion") { return [9501] }
        if ProcessInfo.processInfo.arguments.contains("--reading-controls") { return [9101] }
        if feed == .ask { return [1004] }
        if feed == .show { return [1003] }
        if feed == .jobs { return [1007] }
        if feed == .new { return [1008] + Self.stories.map(\.id) }
        return Self.stories.map(\.id)
    }
    func item(_ id: Int, fresh: Bool) async throws -> HNItem? {
        if ProcessInfo.processInfo.arguments.contains("--offline") { throw URLError(.notConnectedToInternet) }
        if id == 1001, ProcessInfo.processInfo.arguments.contains("--settings-review") {
            var story = Self.stories[0]
            story.title = "A quieter place to read the stories and ideas<br>that make the web worth exploring"
            return story
        }
        if id == 9501 { return HNItem(id: 9501, type: "story", by: "julia", title: "A discussion with 1,200 comments", url: "https://example.com", descendants: 1200, kids: Array(10000...10119)) }
        if (10000...10119).contains(id) || (20000...21079).contains(id) {
            try await Task.sleep(for: .milliseconds(25))
            let root = id < 20000
            let paragraph = "Reading stays responsive while the rest of this discussion loads. <b>Emphasis</b>, <i>italics</i>, and <a href='https://example.com'>a link</a> remain readable."
            return HNItem(id: id, type: "comment", by: "reader\(id)", text: "Comment \(id)<p>" + Array(repeating: paragraph, count: root ? 5 : 2).joined(separator: "<p>"),
                          kids: root ? Array((20000 + (id - 10000) * 9)..<(20000 + (id - 10000) * 9 + 9)) : nil,
                          parent: root ? 9501 : 10000 + (id - 20000) / 9)
        }
        if id == 9101 { return HNItem(id: 9101, type: "story", by: "julia", title: "Reading controls review", url: "https://example.com", descendants: 5, kids: [9200, 9201, 9202, 9203]) }
        if id == 9200 { return HNItem(id: 9200, type: "comment", by: "waiting", text: "[delayed]") }
        if id == 9201 { return HNItem(id: 9201, type: "comment", by: "alex", text: "<a href=\"https://example.com\">Example link</a><p>" + Array(repeating: "Reading should be calm and predictable. A long comment gives us room to check scrolling, navigation, and the small controls that keep a discussion easy to follow.", count: 18).joined(separator: "<p>"), kids: [9301]) }
        if id == 9301 { return HNItem(id: 9301, type: "comment", by: "riley", text: "The next reply is now visible.", parent: 9201) }
        if id == 9202 { return HNItem(id: 9202, type: "comment", kids: [9302], deleted: true) }
        if id == 9302 { return HNItem(id: 9302, type: "comment", by: "noah", text: "A visible reply survives its removed parent.", parent: 9202) }
        if id == 9203 { return HNItem(id: 9203, type: "comment", by: "julia", text: "A final top-level comment.") }
        if id == 1007 { return HNItem(id: 1007, type: "job", by: "team", time: 1_789_118_000, title: "Example company is hiring a Swift engineer", url: "https://example.com/jobs") }
        if id == 1008 { return HNItem(id: 1008, type: "poll", by: "julia", time: 1_789_118_000, title: "Poll: When do you read Hacker News?", text: "Choose the time that fits your routine.", score: 42, descendants: 0, parts: [1009, 1010]) }
        if id == 1009 { return HNItem(id: 1009, type: "pollopt", text: "Over morning coffee", score: 28) }
        if id == 1010 { return HNItem(id: 1010, type: "pollopt", text: "At the end of the day", score: 14) }
        return (Self.stories + Self.comments).first { $0.id == id }
    }
    func user(_ name: String) async throws -> HNUser { HNUser(id: name, created: 1_420_070_400, karma: 12_483, about: "Building small, useful things.<p>Curious about software, cities, and the web.") }
    func listing(_ url: URL) async throws -> HNListingPage {
        HNListingPage(items: url.path.contains("comments") || url.path.contains("highlights") ? Self.comments : Self.stories, next: nil)
    }
    func archive(_ feed: Feed, window: ArchiveWindow, page: Int) async throws -> SearchPage {
        let item = HNItem(id: 9401, type: "story", by: "archive", time: window.after + 1,
                          title: "A favorite from the archive", url: "https://example.com", score: 2048, descendants: 128)
        return SearchPage(items: [item], page: 0, totalPages: 1, totalHits: 1)
    }
    func search(_ query: String, order: SearchOrder, period: SearchPeriod, page: Int) async throws -> SearchPage {
        let hits = Self.stories.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) }
        return SearchPage(items: hits, page: 0, totalPages: 1, totalHits: hits.count)
    }
}
#endif
