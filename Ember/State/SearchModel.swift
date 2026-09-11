import Foundation
import Observation

@MainActor @Observable
final class SearchModel {
    var query = ""
    var order: SearchOrder = .relevant
    var period: SearchPeriod = .all
    private(set) var items: [HNItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?
    private(set) var totalHits = 0
    private(set) var hasMore = false
    private(set) var hasSearched = false
    @ObservationIgnored private var nextPage = 0
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let service: any HNService

    init(service: any HNService) { self.service = service }
    var key: String { "\(order.rawValue)|\(period.rawValue)|\(query)" }

    func search(debounce: Bool = true) async {
        generation = UUID()
        let request = generation
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentOrder = order, currentPeriod = period
        items = []; error = nil; hasMore = false; hasSearched = false; totalHits = 0
        nextPage = 0; isLoadingMore = false
        isLoading = !text.isEmpty
        defer { if generation == request { isLoading = false } }
        guard !text.isEmpty else { return }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(350)) }
            let result = try await service.search(text, order: currentOrder, period: currentPeriod, page: 0)
            try Task.checkCancellation()
            guard request == generation else { return }
            items = result.items.uniqued(); totalHits = result.totalHits
            nextPage = result.page + 1; hasMore = nextPage < result.totalPages; hasSearched = true
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = friendlyError(error); hasSearched = true
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let request = generation
        isLoadingMore = true; error = nil
        defer { if generation == request { isLoadingMore = false } }
        do {
            let result = try await service.search(query.trimmingCharacters(in: .whitespacesAndNewlines), order: order, period: period, page: nextPage)
            try Task.checkCancellation()
            guard request == generation else { return }
            items = (items + result.items).uniqued()
            nextPage = result.page + 1; hasMore = nextPage < result.totalPages
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = friendlyError(error)
        }
    }
}
