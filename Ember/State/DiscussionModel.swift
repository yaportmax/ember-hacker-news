import Foundation
import Observation

struct CommentRow: Identifiable, Equatable {
    enum Kind: Equatable { case comment(HNItem), more(parent: Int, remaining: Int) }
    let id: String
    let depth: Int
    let kind: Kind
}

@MainActor @Observable
final class DiscussionModel {
    private(set) var story: HNItem
    private(set) var comments: [Int: HNItem] = [:]
    private(set) var polls: [HNItem] = []
    private(set) var collapsed: Set<Int> = []
    private(set) var loadingParents: Set<Int> = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var branchErrors: [Int: String] = [:]
    @ObservationIgnored private var cursors: [Int: Int] = [:]
    @ObservationIgnored private let service: any HNService
    @ObservationIgnored private var generation = UUID()

    init(story: HNItem, service: any HNService) { self.story = story; self.service = service }

    func load() async {
        generation = UUID()
        let request = generation
        isLoading = true; error = nil; loadingParents = []; branchErrors = [:]
        defer { if generation == request { isLoading = false } }
        do {
            guard let fresh = try await service.item(story.id, fresh: true) else { throw AppError.missing }
            let roots = try await service.items(Array((fresh.kids ?? []).prefix(20)), fresh: true)
            let options = try await service.items(fresh.parts ?? [], fresh: true)
            try Task.checkCancellation()
            guard generation == request else { return }
            story = fresh
            comments = Dictionary(roots.uniqued().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            cursors = [fresh.id: min(20, fresh.kids?.count ?? 0)]
            collapsed = []; loadingParents = []; branchErrors = [:]; polls = options
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

    func loadChildren(of parent: Int) async {
        guard !loadingParents.contains(parent), !isLoading else { return }
        let kids = parent == story.id ? (story.kids ?? []) : (comments[parent]?.kids ?? [])
        let cursor = cursors[parent, default: 0]
        let batch = Array(kids.dropFirst(cursor).prefix(20))
        guard !batch.isEmpty else { return }
        let request = generation
        loadingParents.insert(parent); branchErrors.removeValue(forKey: parent)
        defer { if generation == request { loadingParents.remove(parent) } }
        do {
            let fetched = try await service.items(batch, fresh: true)
            try Task.checkCancellation()
            guard generation == request else { return }
            for item in fetched { comments[item.id] = item }
            cursors[parent] = cursor + batch.count
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            branchErrors[parent] = friendlyError(error)
        }
    }

    /// Flatten the visible tree for a single lazy List. Capped visual indentation
    /// keeps deep discussions readable without truncating the actual hierarchy.
    func rows(blocked: Set<String>) -> [CommentRow] {
        var rows: [CommentRow] = []
        var visited = Set<Int>()
        func appendChildren(_ parent: Int, kids: [Int], depth: Int) {
            guard depth < 100 else { return }
            let loadedCount = cursors[parent, default: 0]
            for id in kids.prefix(loadedCount) {
                guard visited.insert(id).inserted, let item = comments[id] else { continue }
                if let by = item.by, blocked.contains(by) { continue }
                let text = HNHTML.plainText(item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let visible = item.isVisible && !text.isEmpty && text != "[delayed]"
                if visible { rows.append(CommentRow(id: "comment-\(id)", depth: depth, kind: .comment(item))) }
                if !visible || !collapsed.contains(id) {
                    appendChildren(id, kids: item.kids ?? [], depth: depth + (visible ? 1 : 0))
                }
            }
            if loadedCount < kids.count {
                rows.append(CommentRow(id: "more-\(parent)", depth: depth,
                                       kind: .more(parent: parent, remaining: kids.count - loadedCount)))
            }
        }
        appendChildren(story.id, kids: story.kids ?? [], depth: 0)
        return rows
    }
}
