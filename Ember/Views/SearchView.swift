import SwiftUI

struct SearchView: View {
    @State private var model: SearchModel
    @Environment(ReadingStore.self) private var reading
    init(service: any HNService) { _model = State(initialValue: SearchModel(service: service)) }

    var body: some View {
        @Bindable var model = model
        List {
            if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyState(title: "Find something worth reading", symbol: "magnifyingglass", detail: "Search stories across the Hacker News archive.")
                    .listRowSeparator(.hidden)
            } else if model.isLoading {
                HStack { Spacer(); ProgressView("Searching…"); Spacer() }.padding(.vertical, 50).listRowSeparator(.hidden)
            } else {
                if let error = model.error { InlineNotice(message: error) { Task { await model.search(debounce: false) } }.listRowSeparator(.hidden) }
                if model.hasSearched, model.items.isEmpty, model.error == nil {
                    EmptyState(title: "No results", symbol: "magnifyingglass", detail: "Try another phrase or a wider date range.").listRowSeparator(.hidden)
                }
                if !model.items.isEmpty {
                    Text("\(model.totalHits.formatted()) results · \(model.period.title)").font(.caption).foregroundStyle(.secondary).listRowSeparator(.hidden)
                }
                ForEach(model.items.filter { !reading.isHidden($0) }) { item in
                    NavigationLink(value: item) { StoryRow(item: item) }.accessibilityIdentifier("story-\(item.id)").storyActions(item)
                }
                if model.hasMore { PageButton(loading: model.isLoadingMore) { Task { await model.loadMore() } }.listRowSeparator(.hidden) }
            }
            if model.hasSearched { Text("Search by Algolia").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).listRowSeparator(.hidden) }
        }
        .listStyle(.plain)
        .readingWidth()
        .navigationTitle("Search")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Stories, ideas, people")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $model.order) { ForEach(SearchOrder.allCases) { Text($0.title).tag($0) } }
                    Picker("Posted", selection: $model.period) { ForEach(SearchPeriod.allCases) { Text($0.title).tag($0) } }
                } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("Search filters")
            }
        }
        .task(id: model.key) { await model.search() }
    }
}
