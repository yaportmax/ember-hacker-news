import SwiftUI

struct SearchView: View {
    @State private var model: SearchModel
    @Environment(ReadingStore.self) private var reading
    init(service: any HNService) { _model = State(initialValue: SearchModel(service: service)) }

    private var visible: [HNItem] { model.items.filter { !reading.isHidden($0) } }

    var body: some View {
        @Bindable var model = model
        List {
            HStack(alignment: .firstTextBaseline) {
                Text(model.hasSearched ? "\(model.totalHits.formatted()) \(model.totalHits == 1 ? "result" : "results")" : model.period.title)
                    .font(.caption).foregroundStyle(EmberStyle.secondaryText)
                Spacer(minLength: 12)
                Menu {
                    Picker("Sort by", selection: $model.order) { ForEach(SearchOrder.allCases) { Text($0.title).tag($0) } }
                    Picker("Posted", selection: $model.period) { ForEach(SearchPeriod.allCases) { Text($0.title).tag($0) } }
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.borderless).accessibilityLabel("Search filters")
                .accessibilityValue("\(model.order.title), \(model.period.title)")
            }.listRowSeparator(.hidden)
            if model.order != .relevant || model.period != .all {
                Text("\(model.order.title) · \(model.period.title)")
                    .font(.caption).foregroundStyle(EmberStyle.secondaryText).listRowSeparator(.hidden)
            }
            if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyState(title: "Search Hacker News", symbol: "magnifyingglass", detail: "Find stories from the entire archive.")
                    .listRowSeparator(.hidden)
            } else if model.isLoading {
                HStack { Spacer(); ProgressView("Searching…"); Spacer() }.padding(.vertical, 50).listRowSeparator(.hidden)
            } else {
                if let error = model.error { InlineNotice(message: error) { Task { await model.search(debounce: false) } }.listRowSeparator(.hidden) }
                if model.hasSearched, model.items.isEmpty, model.error == nil {
                    EmptyState(title: "No results", symbol: "magnifyingglass", detail: "Try another phrase or a wider date range.").listRowSeparator(.hidden)
                }
                if !model.items.isEmpty, visible.isEmpty {
                    EmptyState(title: "Results are hidden", symbol: "eye.slash", detail: "Review Hidden content in Settings to show matching stories.").listRowSeparator(.hidden)
                }
                ForEach(visible) { item in
                    NavigationLink(value: item) { StoryRow(item: item) }.accessibilityIdentifier("story-\(item.id)").storyActions(item)
                }
                if model.hasMore { PageButton(loading: model.isLoadingMore) { Task { await model.loadMore() } }.listRowSeparator(.hidden) }
            }
            if model.hasSearched { Text("Search by Algolia").font(.caption2).foregroundStyle(EmberStyle.secondaryText).frame(maxWidth: .infinity).listRowSeparator(.hidden) }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .readingWidth()
        .navigationTitle("Search")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search stories")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task(id: model.key) { await model.search() }
    }
}
