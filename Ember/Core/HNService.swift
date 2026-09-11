import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol HNService: Sendable {
    func feedIDs(_ feed: Feed) async throws -> [Int]
    func item(_ id: Int, fresh: Bool) async throws -> HNItem?
    func user(_ name: String) async throws -> HNUser
    func search(_ query: String, order: SearchOrder, period: SearchPeriod, page: Int) async throws -> SearchPage
}

extension HNService {
    /// Bounded concurrency, original ranking, and all-or-nothing failure so pagination cannot skip a failed item.
    func items(_ ids: [Int], fresh: Bool = false) async throws -> [HNItem] {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (Int, HNItem?).self) { group in
            var next = 0
            var indexed: [(Int, HNItem)] = []
            func enqueue(_ index: Int) {
                group.addTask { try Task.checkCancellation(); return (index, try await self.item(ids[index], fresh: fresh)) }
            }
            for _ in 0..<min(8, ids.count) { enqueue(next); next += 1 }
            while let (index, item) = try await group.next() {
                if let item { indexed.append((index, item)) }
                if next < ids.count { enqueue(next); next += 1 }
            }
            try Task.checkCancellation()
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

actor HNClient: HNService {
    private let session: URLSession
    private var itemCache: [Int: (item: HNItem, fetched: Date)] = [:]
    private let base = URL(string: "https://hacker-news.firebaseio.com/v0")!

    init(session: URLSession? = nil) {
        if let session { self.session = session } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 40
            configuration.httpMaximumConnectionsPerHost = 8
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func feedIDs(_ feed: Feed) async throws -> [Int] {
        try await get(base.appendingPathComponent("\(feed.endpoint).json"))
    }

    func item(_ id: Int, fresh: Bool = false) async throws -> HNItem? {
        guard id > 0 else { throw AppError.missing }
        if !fresh, let cached = itemCache[id], Date().timeIntervalSince(cached.fetched) < 120 { return cached.item }
        let item: HNItem? = try await get(base.appendingPathComponent("item/\(id).json"))
        if let item {
            if itemCache.count >= 2_000 { itemCache.removeAll(keepingCapacity: true) }
            itemCache[id] = (item, Date())
        } else { itemCache.removeValue(forKey: id) }
        return item
    }

    func user(_ name: String) async throws -> HNUser {
        // HN names cannot contain a slash; avoid interpreting input as a URL path.
        guard !name.isEmpty, name.count <= 100,
              name.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0) }) else { throw AppError.missing }
        let value: HNUser? = try await get(base.appendingPathComponent("user/\(name).json"))
        guard let value else { throw AppError.missing }
        return value
    }

    func search(_ query: String, order: SearchOrder, period: SearchPeriod, page: Int) async throws -> SearchPage {
        let url = Self.searchURL(query, order: order, period: period, page: page)
        let response: SearchResponse = try await get(url)
        return response.result
    }

    nonisolated static func searchURL(_ query: String, order: SearchOrder, period: SearchPeriod, page: Int, now: Date = Date()) -> URL {
        var components = URLComponents(string: "https://hn.algolia.com/api/v1/\(order == .recent ? "search_by_date" : "search")")!
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "tags", value: "story"),
                                 URLQueryItem(name: "page", value: String(max(0, page))), URLQueryItem(name: "hitsPerPage", value: "30")]
        if let seconds = period.seconds {
            components.queryItems?.append(URLQueryItem(name: "numericFilters", value: "created_at_i>\(Int(now.timeIntervalSince1970 - seconds))"))
        }
        return components.url!
    }

    private func get<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for attempt in 0...1 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
                guard (200..<300).contains(http.statusCode) else { throw AppError.status(http.statusCode) }
                guard data.count < 8_000_000 else { throw AppError.invalidResponse }
                do { return try JSONDecoder().decode(T.self, from: data) }
                catch { throw AppError.invalidResponse }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                let retryable: Bool
                if let error = error as? AppError, case .status(let code) = error { retryable = (500...599).contains(code) }
                else if let error = error as? URLError { retryable = [.timedOut, .networkConnectionLost].contains(error.code) }
                else { retryable = false }
                guard attempt == 0, retryable else { throw error }
                try await Task.sleep(for: .milliseconds(450))
            }
        }
        throw AppError.invalidResponse
    }
}
