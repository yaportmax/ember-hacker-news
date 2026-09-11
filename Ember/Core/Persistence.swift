import Foundation

struct SavedStory: Codable, Identifiable, Equatable, Sendable {
    var item: HNItem
    var savedAt: Date
    var id: Int { item.id }
}

struct ReadingArchive: Codable, Equatable, Sendable {
    var version = 1
    var bookmarks: [SavedStory] = []
    var history: [SavedStory] = []
    var blockedUsers: Set<String> = []
    var hiddenStories: Set<Int> = []

    mutating func record(_ item: HNItem, now: Date = Date()) {
        history.removeAll { $0.id == item.id }
        history.insert(SavedStory(item: item, savedAt: now), at: 0)
        history = Array(history.prefix(500))
        if let index = bookmarks.firstIndex(where: { $0.id == item.id }) { bookmarks[index].item = item }
    }

    mutating func toggleBookmark(_ item: HNItem, now: Date = Date()) {
        if bookmarks.contains(where: { $0.id == item.id }) { bookmarks.removeAll { $0.id == item.id } }
        else { bookmarks.insert(SavedStory(item: item, savedAt: now), at: 0) }
    }
}

enum ArchiveFile {
    static func read(at url: URL) throws -> ReadingArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return ReadingArchive() }
        let data = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(ReadingArchive.self, from: data)
        guard archive.version == 1 else { throw AppError.invalidStorage }
        return archive
    }
}

actor ArchiveWriter {
    private let url: URL
    private var revision = -1
    init(url: URL) { self.url = url }

    func write(_ archive: ReadingArchive, revision: Int) throws {
        guard revision > self.revision else { return }
        let data = try JSONEncoder().encode(archive)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        self.revision = revision
    }
}

struct CachedFeed: Codable, Sendable {
    let items: [HNItem]
    let fetchedAt: Date
}

actor FeedCache {
    private let directory: URL
    init(directory: URL) { self.directory = directory }

    func read(_ feed: Feed) -> CachedFeed? {
        guard let data = try? Data(contentsOf: path(feed)) else { return nil }
        return try? JSONDecoder().decode(CachedFeed.self, from: data)
    }

    func write(_ items: [HNItem], feed: Feed, fetchedAt: Date) {
        // Cache is replaceable; a cache write failure must not prevent reading live stories.
        guard let data = try? JSONEncoder().encode(CachedFeed(items: Array(items.prefix(150)), fetchedAt: fetchedAt)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: path(feed), options: .atomic)
    }

    func clear() throws {
        for feed in Feed.allCases where FileManager.default.fileExists(atPath: path(feed).path) {
            try FileManager.default.removeItem(at: path(feed))
        }
    }

    private func path(_ feed: Feed) -> URL { directory.appendingPathComponent("\(feed.rawValue).json") }
}
