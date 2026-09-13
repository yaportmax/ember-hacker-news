import Foundation
import Observation

struct CommentRow: Identifiable, Equatable {
    let id: String
    let depth: Int
    let item: HNItem
}

@MainActor @Observable
final class DiscussionModel {
    private(set) var story: HNItem
    private(set) var comments: [Int: HNItem] = [:]
    private(set) var polls: [HNItem] = []
    private(set) var collapsed: Set<Int> = []
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private let service: any HNService
    @ObservationIgnored private var generation = UUID()

    init(story: HNItem, service: any HNService) { self.story = story; self.service = service }

    func load() async {
        generation = UUID()
        let request = generation
        isLoading = true; error = nil
        defer { if generation == request { isLoading = false } }
        do {
            guard let fresh = try await service.item(story.id, fresh: true) else { throw AppError.missing }
            // Load the complete tree before showing it. The service limits requests
            // to eight at a time; scrolling never triggers more network work.
            var fetched: [Int: HNItem] = [:]
            var visited: Set<Int> = [fresh.id]
            var pending = fresh.kids ?? []
            while !pending.isEmpty {
                try Task.checkCancellation()
                guard generation == request else { return }
                let batch = pending.filter { visited.insert($0).inserted }
                let items = try await service.items(batch, fresh: true)
                for item in items { fetched[item.id] = item }
                pending = items.flatMap { $0.kids ?? [] }
            }
            let options = try await service.items(fresh.parts ?? [], fresh: true)
            try Task.checkCancellation()
            guard generation == request else { return }
            story = fresh; comments = fetched; polls = options
            collapsed.formIntersection(fetched.keys)

        } catch {
            guard generation == request, !Task.isCancelled else { return }
            self.error = friendlyError(error)
        }
    }

    func toggle(_ id: Int) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    func expandAll() { collapsed = [] }
    func collapseAll() { collapsed = Set(comments.keys) }

    /// Flatten the visible tree for a single lazy List. Capped visual indentation
    /// keeps deep discussions readable without truncating the actual hierarchy.
    func rows(blocked: Set<String>) -> [CommentRow] {
        var rows: [CommentRow] = []
        var visited = Set<Int>()
        func appendChildren(_ parent: Int, kids: [Int], depth: Int) {
            guard depth < 100 else { return }
            for id in kids {
                guard visited.insert(id).inserted, let item = comments[id] else { continue }
                if let by = item.by, blocked.contains(by) { continue }
                let text = HNHTML.plainText(item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let visible = item.isVisible && !text.isEmpty && text != "[delayed]"
                if visible { rows.append(CommentRow(id: "comment-\(id)", depth: depth, item: item)) }
                if !visible || !collapsed.contains(id) {
                    appendChildren(id, kids: item.kids ?? [], depth: depth + (visible ? 1 : 0))
                }
            }

        }
        appendChildren(story.id, kids: story.kids ?? [], depth: 0)
        return rows
    }
}
