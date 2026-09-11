import SwiftUI

struct FeedView: View {
    @State private var model: FeedModel
    @AppStorage("selectedFeed") private var selectedFeed = Feed.top.rawValue
    @AppStorage("hideReadStories") private var hideRead = false
    @Environment(ReadingStore.self) private var reading
    @Environment(AppContainer.self) private var app

    init(service: any HNService, cache: FeedCache) { _model = State(initialValue: FeedModel(service: service, cache: cache)) }
    private var feed: Feed { Feed(rawValue: selectedFeed) ?? .top }
    private var visible: [HNItem] { model.items.filter { !reading.isHidden($0) && !(hideRead && reading.isRead($0.id)) } }

    var body: some View {
        List {
            if model.isCached, let updated = model.updatedAt {
                Label("Saved feed · \(updated.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(.secondary).listRowSeparator(.hidden)
            }
            if let error = model.error { InlineNotice(message: error) { Task { await model.refresh() } }.listRowSeparator(.hidden) }
            if model.isLoading, model.items.isEmpty {
                HStack { Spacer(); ProgressView("Loading stories…"); Spacer() }.padding(.vertical, 60).listRowSeparator(.hidden)
            } else if visible.isEmpty, model.error == nil {
                EmptyState(title: model.items.isEmpty ? "No stories yet" : "You’re caught up", symbol: "text.alignleft",
                           detail: model.items.isEmpty ? "Pull to refresh in a moment." : "Try another feed or turn off filters in Settings.")
                    .listRowSeparator(.hidden)
            }
            ForEach(visible) { item in
                NavigationLink(value: item) {
                    StoryRow(item: item, rank: model.items.firstIndex(where: { $0.id == item.id }).map { $0 + 1 })
                }
                .accessibilityIdentifier("story-\(item.id)")
                .storyActions(item)
            }
            if model.hasMore {
                PageButton(loading: model.isLoadingMore) { Task { await model.loadMore() } }.listRowSeparator(.hidden)
            }
            if !model.items.isEmpty, !model.hasMore, !model.isLoading, model.error == nil {
                Text("You’ve reached the end.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .readingWidth()
        .navigationTitle(feed.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("EMBER").font(.system(.caption2, design: .monospaced, weight: .bold)).tracking(3).foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Ember, Hacker News")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Feed", selection: $selectedFeed) {
                        ForEach(Feed.allCases) { feed in Text(feed.title).tag(feed.rawValue) }
                    }
                    Divider()
                    Toggle("Hide read stories", isOn: $hideRead)
                    Button("Submit to Hacker News", systemImage: "square.and.pencil") { app.open(HNLinks.submit) }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                .accessibilityLabel("Choose feed").accessibilityIdentifier("feed-menu")
            }
        }
        .refreshable { await model.refresh() }
        .task(id: selectedFeed) { await model.load(feed) }
    }
}
