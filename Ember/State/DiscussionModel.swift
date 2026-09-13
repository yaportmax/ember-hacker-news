import Foundation
import Observation

struct CommentRow: Identifiable, Equatable, Sendable {
    let id: String
    let depth: Int
    let item: HNItem
    let runs: [HNHTML.Run]
}

struct PreparedComment: Sendable {
    let item: HNItem
    let depth: Int
    let runs: [HNHTML.Run]
    let visible: Bool
}

struct DiscussionSnapshot: Sendable {
    let story: HNItem
    let comments: [PreparedComment]
    let polls: [HNItem]
    let complete: Bool
}

/// Session-only reuse, bounded by both thread count and comment count.
actor DiscussionCache {
    private var entries: [Int: (snapshot: DiscussionSnapshot, date: Date)] = [:]
    private var order: [Int] = []

    func snapshot(_ id: Int) -> DiscussionSnapshot? {
        guard let entry = entries[id], Date().timeIntervalSince(entry.date) < 120 else { return nil }
        return entry.snapshot
    }

    func store(_ snapshot: DiscussionSnapshot) {
        let id = snapshot.story.id
        entries[id] = (snapshot, Date())
        order.removeAll { $0 == id }; order.append(id)
        while entries.count > 4 || entries.values.reduce(0, { $0 + $1.snapshot.comments.count }) > 8_000 {
            entries.removeValue(forKey: order.removeFirst())
        }
    }
}

/// Network scheduling and HTML preparation stay off the main actor. Children
/// take priority over later roots; only a contiguous prefix is published, so a
/// late reply cannot insert itself above comments already being read.
enum DiscussionLoader {
    static func load(story: HNItem, service: any HNService, fresh: Bool,
                     receive: @MainActor @Sendable (DiscussionSnapshot) async -> Void) async throws {
        guard let story = try await service.item(story.id, fresh: fresh) else { throw AppError.missing }
        let polls = try await service.items(story.parts ?? [], fresh: fresh)
        try await withThrowingTaskGroup(of: HNItemResult.self) { group in
            var pending = Array((story.kids ?? []).reversed())
            var scheduled: Set<Int> = [story.id]
            var resolved: Set<Int> = [story.id]
            var prepared: [Int: PreparedComment] = [:]
            var active = 0, published = 0
            let clock = ContinuousClock()
            var lastPublication = clock.now

            func enqueue() {
                while active < 8, let id = pending.popLast() {
                    guard scheduled.insert(id).inserted else { continue }
                    active += 1
                    group.addTask {
                        try Task.checkCancellation()
                        return HNItemResult(id: id, item: try await service.item(id, fresh: fresh))
                    }
                }
            }
            func snapshot(complete: Bool) -> DiscussionSnapshot {
                var output: [PreparedComment] = []
                var stack = (story.kids ?? []).reversed().map { ($0, 0) }
                var visited: Set<Int> = [story.id]
                while let (id, depth) = stack.popLast() {
                    guard depth < 100, visited.insert(id).inserted else { continue }
                    guard resolved.contains(id) else { break }
                    guard let value = prepared[id] else { continue }
                    output.append(PreparedComment(item: value.item, depth: depth, runs: value.runs, visible: value.visible))
                    stack.append(contentsOf: (value.item.kids ?? []).reversed().map { ($0, depth + 1) })
                }
                return DiscussionSnapshot(story: story, comments: output, polls: polls, complete: complete)
            }
            enqueue()
            while let result = try await group.next() {
                try Task.checkCancellation()
                active -= 1; resolved.insert(result.id)
                if let item = result.item {
                    let runs = HNHTML.runs(item.text ?? "")
                    let plain = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                    prepared[result.id] = PreparedComment(item: item, depth: 0, runs: runs,
                                                         visible: item.isVisible && !plain.isEmpty && plain != "[delayed]")
                    pending.append(contentsOf: (item.kids ?? []).reversed())
                }
                enqueue()
                // First readable content is immediate; subsequent UI updates are
                // coalesced. All remaining work continues without scroll triggers.
                if published == 0 || lastPublication.duration(to: clock.now) >= .milliseconds(500) {
                    let value = snapshot(complete: false)
                    if value.comments.count > published, value.comments.contains(where: \.visible) {
                        await receive(value)
                        published = value.comments.count; lastPublication = clock.now
                    }
                }
            }
            try Task.checkCancellation()
            await receive(snapshot(complete: true))
        }
    }

    private struct HNItemResult: Sendable { let id: Int; let item: HNItem? }
}

@MainActor @Observable
final class DiscussionModel {
    private(set) var story: HNItem
    private(set) var comments: [Int: HNItem] = [:]
    private(set) var polls: [HNItem] = []
    private(set) var collapsed: Set<Int> = []
    private(set) var rows: [CommentRow] = []
    private(set) var rowPositions: [Int: Int] = [:]
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private let service: any HNService
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var prepared: [PreparedComment] = []
    @ObservationIgnored private var blocked: Set<String> = []
    @ObservationIgnored private var complete = false
    @ObservationIgnored private var collapseIncoming = false

    init(story: HNItem, service: any HNService) { self.story = story; self.service = service }

    func load(refresh: Bool = false, cache: DiscussionCache? = nil) async {
        if complete, !refresh { return }
        generation = UUID()
        let request = generation
        isLoading = true; error = nil
        defer { if generation == request { isLoading = false } }
        if !refresh, let cached = await cache?.snapshot(story.id) {
            guard generation == request, !Task.isCancelled else { return }
            apply(cached)
            if cached.complete { return }
        }
        // Keep an existing thread intact while an explicit refresh is in flight.
        let retainedCount = prepared.count
        do {
            try await DiscussionLoader.load(story: story, service: service, fresh: refresh) { [weak self] snapshot in
                guard let self, self.generation == request, !Task.isCancelled else { return }
                if snapshot.complete || snapshot.comments.count >= retainedCount {
                    self.apply(snapshot)
                    await cache?.store(snapshot)
                }
            }
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            self.error = friendlyError(error)
        }
    }

    private func apply(_ snapshot: DiscussionSnapshot) {
        story = snapshot.story; polls = snapshot.polls; prepared = snapshot.comments
        if collapseIncoming { collapsed.formUnion(Set(prepared.map { $0.item.id }).subtracting(comments.keys)) }
        comments = Dictionary(uniqueKeysWithValues: prepared.map { ($0.item.id, $0.item) })
        complete = snapshot.complete
        if complete { collapsed.formIntersection(comments.keys) }
        rebuildRows()
    }

    func setBlockedUsers(_ users: Set<String>) {
        guard blocked != users else { return }
        blocked = users; rebuildRows()
    }

    func toggle(_ id: Int) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        rebuildRows()
    }

    func expandAll() { collapseIncoming = false; collapsed = []; rebuildRows() }
    func collapseAll() { collapseIncoming = true; collapsed = Set(comments.keys); rebuildRows() }

    /// Rebuilt only when data or collapse/block state changes, never on scroll.
    private func rebuildRows() {
        var output: [CommentRow] = [], visibleAncestors: [Int] = []
        var hiddenDepth: Int?
        for value in prepared {
            if let hiddenDepth, value.depth > hiddenDepth { continue }
            hiddenDepth = nil
            while let depth = visibleAncestors.last, depth >= value.depth { visibleAncestors.removeLast() }
            if let by = value.item.by, blocked.contains(by) { hiddenDepth = value.depth; continue }
            guard value.visible else { continue }
            output.append(CommentRow(id: "comment-\(value.item.id)", depth: visibleAncestors.count,
                                     item: value.item, runs: value.runs))
            if collapsed.contains(value.item.id) { hiddenDepth = value.depth }
            else { visibleAncestors.append(value.depth) }
        }
        rows = output
        rowPositions = Dictionary(uniqueKeysWithValues: output.enumerated().map { ($0.element.item.id, $0.offset) })
    }
}
