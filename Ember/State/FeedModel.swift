import Foundation
import Observation

@MainActor @Observable
final class FeedModel {
    private(set) var items: [HNItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isCached = false
    private(set) var updatedAt: Date?
    private(set) var hasMore = false
    private(set) var error: String?
    @ObservationIgnored private let service: any HNService
    @ObservationIgnored private let cache: FeedCache
    @ObservationIgnored private var ids: [Int] = []
    @ObservationIgnored private var cursor = 0
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var feed: Feed = .top

    init(service: any HNService, cache: FeedCache) { self.service = service; self.cache = cache }

    func load(_ feed: Feed) async {
        generation = UUID()
        let request = generation
        self.feed = feed
        items = []; ids = []; cursor = 0; hasMore = false; error = nil; isCached = false; updatedAt = nil
        isLoading = true; isLoadingMore = false
        if let cached = await cache.read(feed), generation == request, !Task.isCancelled {
            items = cached.items; updatedAt = cached.fetchedAt; isCached = true
        }
        guard generation == request, !Task.isCancelled else { return }
        await refresh()
    }

    func refresh() async {
        generation = UUID()
        let request = generation
        let currentFeed = feed
        isLoading = true; isLoadingMore = false; error = nil
        defer { if generation == request { isLoading = false } }
        do {
            let newIDs = try await service.feedIDs(currentFeed)
            let first = Array(newIDs.prefix(30))
            let fetched = try await service.items(first, fresh: true)
            try Task.checkCancellation()
            guard generation == request else { return }
            ids = newIDs; cursor = first.count
            items = fetched.filter { $0.isVisible && $0.isStory }.uniqued()
            hasMore = cursor < ids.count; isCached = false; updatedAt = Date()
            await cache.write(items, feed: currentFeed, fetchedAt: updatedAt ?? Date())
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            self.error = friendlyError(error)
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        isLoadingMore = true; error = nil
        let request = generation
        let start = cursor
        let batch = Array(ids.dropFirst(start).prefix(30))
        defer { if generation == request { isLoadingMore = false } }
        do {
            let fetched = try await service.items(batch)
            try Task.checkCancellation()
            guard generation == request else { return }
            items = (items + fetched.filter { $0.isVisible && $0.isStory }).uniqued()
            cursor = start + batch.count; hasMore = cursor < ids.count
            await cache.write(items, feed: feed, fetchedAt: updatedAt ?? Date())
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            self.error = friendlyError(error)
        }
    }
}
