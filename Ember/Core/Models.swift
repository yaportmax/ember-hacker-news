import Foundation

enum Feed: String, CaseIterable, Codable, Identifiable, Sendable {
    case top, new, best, ask, show, jobs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .top: "Top"
        case .new: "New"
        case .best: "Best"
        case .ask: "Ask HN"
        case .show: "Show HN"
        case .jobs: "Jobs"
        }
    }
    var endpoint: String { self == .jobs ? "jobstories" : "\(rawValue)stories" }
}

enum FeedPeriod: String, CaseIterable, Identifiable {
    case live, day, week, month, year, all, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .live: "Live"
        case .day: "Today"
        case .week: "Past week"
        case .month: "Past month"
        case .year: "Past year"
        case .all: "All time"
        case .custom: "Custom dates"
        }
    }
    func window(now: Date = Date(), calendar: Calendar = .current, start: Date = Date(), end: Date = Date()) -> ArchiveWindow? {
        let after: Date
        switch self {
        case .live: return nil
        case .day: after = calendar.startOfDay(for: now)
        case .week: after = calendar.date(byAdding: .day, value: -7, to: now)!
        case .month: after = calendar.date(byAdding: .month, value: -1, to: now)!
        case .year: after = calendar.date(byAdding: .year, value: -1, to: now)!
        case .all: after = Date(timeIntervalSince1970: 0)
        case .custom:
            let lower = calendar.startOfDay(for: min(start, end))
            let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end)))!
            return ArchiveWindow(after: lower.timeIntervalSince1970, before: min(upper, now).timeIntervalSince1970)
        }
        return ArchiveWindow(after: after.timeIntervalSince1970, before: now.timeIntervalSince1970)
    }
}

struct ArchiveWindow: Hashable, Sendable {
    let after: TimeInterval
    let before: TimeInterval
}

struct HNItem: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var type: String?
    var by: String?
    var time: TimeInterval?
    var title: String?
    var url: String?
    var text: String?
    var score: Int?
    var descendants: Int?
    var kids: [Int]?
    var parent: Int?
    var parts: [Int]?
    var deleted: Bool?
    var dead: Bool?

    var isVisible: Bool { deleted != true && dead != true }
    var isStory: Bool { ["story", "job", "poll"].contains(type ?? "") }
    var displayTitle: String { HNHTML.plainText(title ?? "Untitled") }
    var articleURL: URL? { WebURL.validated(url) }
    var discussionURL: URL { HNLinks.item(id) }
    var date: Date { Date(timeIntervalSince1970: time ?? 0) }
    var commentCount: Int { max(0, descendants ?? 0) }
    var domain: String? {
        guard let host = articleURL?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

struct HNUser: Codable, Hashable, Sendable {
    let id: String
    let created: TimeInterval
    let karma: Int
    var about: String?
    var submitted: [Int]?
}

enum SearchOrder: String, CaseIterable, Identifiable, Sendable {
    case relevant, recent
    var id: String { rawValue }
    var title: String { self == .relevant ? "Relevance" : "Most recent" }
}

enum SearchPeriod: String, CaseIterable, Identifiable, Sendable {
    case all, day, week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All time"
        case .day: "Past day"
        case .week: "Past week"
        case .month: "Past month"
        case .year: "Past year"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .all: nil
        case .day: 86_400
        case .week: 604_800
        case .month: 2_592_000
        case .year: 31_536_000
        }
    }
}

struct SearchPage: Sendable {
    let items: [HNItem]
    let page: Int
    let totalPages: Int
    let totalHits: Int
}

struct SearchResponse: Decodable, Sendable {
    let hits: [Hit]
    let page: Int
    let nbPages: Int
    let nbHits: Int

    struct Hit: Decodable, Sendable {
        let objectID: String
        let title: String?
        let url: String?
        let author: String?
        let points: Int?
        let num_comments: Int?
        let created_at_i: TimeInterval?
        let story_text: String?
        var item: HNItem? {
            guard let id = Int(objectID), id > 0 else { return nil }
            return HNItem(id: id, type: "story", by: author, time: created_at_i,
                          title: title, url: url, text: story_text, score: points,
                          descendants: num_comments)
        }
    }
    var result: SearchPage {
        SearchPage(items: hits.compactMap(\.item), page: page, totalPages: nbPages, totalHits: nbHits)
    }
}

enum WebURL {
    /// Only HTTP(S) links with a hostname can reach the browser. Never execute HN HTML.
    static func validated(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

enum HNLinks {
    static let home = URL(string: "https://news.ycombinator.com")!
    static let login = URL(string: "https://news.ycombinator.com/login")!
    static let submit = URL(string: "https://news.ycombinator.com/submit")!
    static func item(_ id: Int) -> URL { home.appendingPathComponent("item").appending(queryItems: [URLQueryItem(name: "id", value: String(id))]) }
    static func user(_ name: String) -> URL { home.appendingPathComponent("user").appending(queryItems: [URLQueryItem(name: "id", value: name)]) }
    static func itemID(from url: URL) -> Int? {
        let host = url.host?.lowercased()
        if url.scheme?.lowercased() == "emberhn", host == "item" {
            return positiveID(url.pathComponents.last)
        }
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              host == "news.ycombinator.com", url.path == "/item" else { return nil }
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
        return positiveID(value)
    }
    private static func positiveID(_ value: String?) -> Int? {
        guard let value, let id = Int(value), id > 0 else { return nil }
        return id
    }
}

enum AppError: LocalizedError, Sendable, Equatable {
    case invalidResponse, status(Int), missing, invalidLink, invalidStorage
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned something Ember couldn’t read. Please try again."
        case .status(let code): "The server is unavailable (\(code)). Please try again shortly."
        case .missing: "This item is no longer available."
        case .invalidLink: "This link can’t be opened."
        case .invalidStorage: "Your saved data couldn’t be read. The original file has been kept."
        }
    }
}

func friendlyError(_ error: Error) -> String {
    if let error = error as? URLError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "You’re offline. Check your connection and try again."
        case .timedOut: return "The request took too long. Please try again."
        default: break
        }
    }
    return error.localizedDescription
}

extension Array where Element: Identifiable, Element.ID: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
enum HNList: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bestcomments, newcomments, highlights, active, asknew, shownew, whoishiring, launches, classic, pool, invited, noobstories, noobcomments
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bestcomments: "Best Comments"
        case .newcomments: "New Comments"
        case .highlights: "Comment Highlights"
        case .active: "Active Discussions"
        case .asknew: "Newest Ask HN"
        case .shownew: "Newest Show HN"
        case .whoishiring: "Who Is Hiring"
        case .launches: "Launch HN"
        case .classic: "Classic"
        case .pool: "Second Chance"
        case .invited: "Invited to Repost"
        case .noobstories: "Newcomer Stories"
        case .noobcomments: "Newcomer Comments"
        }
    }
    var detail: String {
        switch self {
        case .bestcomments: "Most-upvoted comments from the last 48 hours."
        case .newcomments: "The newest comments across Hacker News."
        case .highlights: "Notable comments selected from across the years."
        case .active: "The most active current discussions."
        case .asknew: "Ask HN posts, newest first."
        case .shownew: "Show HN posts, newest first."
        case .whoishiring: "Monthly hiring discussions."
        case .launches: "YC startup launches."
        case .classic: "The front page as voted by longstanding accounts."
        case .pool: "Stories selected for another chance at the front page."
        case .invited: "Overlooked submissions invited to repost."
        case .noobstories: "Stories from new accounts."
        case .noobcomments: "Comments from new accounts."
        }
    }
    var url: URL {
        if self == .whoishiring { return URL(string: "https://news.ycombinator.com/submitted?id=whoishiring")! }
        return HNLinks.home.appendingPathComponent(rawValue)
    }
}

struct HNListingPage: Sendable {
    let items: [HNItem]
    let next: URL?
}
