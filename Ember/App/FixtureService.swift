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
        if feed == .ask { return [1004] }
        if feed == .show { return [1003] }
        if feed == .jobs { return [1007] }
        return Self.stories.map(\.id)
    }
    func item(_ id: Int, fresh: Bool) async throws -> HNItem? {
        if ProcessInfo.processInfo.arguments.contains("--offline") { throw URLError(.notConnectedToInternet) }
        if id == 1007 { return HNItem(id: 1007, type: "job", by: "team", time: 1_789_118_000, title: "Example company is hiring a Swift engineer", url: "https://example.com/jobs") }
        return (Self.stories + Self.comments).first { $0.id == id }
    }
    func user(_ name: String) async throws -> HNUser { HNUser(id: name, created: 1_420_070_400, karma: 12_483, about: "Building small, useful things.<p>Curious about software, cities, and the web.") }
    func search(_ query: String, order: SearchOrder, period: SearchPeriod, page: Int) async throws -> SearchPage {
        let hits = Self.stories.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) }
        return SearchPage(items: hits, page: 0, totalPages: 1, totalHits: hits.count)
    }
}
#endif
