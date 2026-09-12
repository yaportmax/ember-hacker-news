import SwiftUI

struct FeedView: View {
    @State private var model: FeedModel
    @AppStorage("selectedFeed") private var selectedFeed = Feed.top.rawValue
    @AppStorage("hideReadStories") private var hideRead = false
    @Environment(ReadingStore.self) private var reading

    init(service: any HNService, cache: FeedCache) { _model = State(initialValue: FeedModel(service: service, cache: cache)) }
    private var feed: Feed { Feed(rawValue: selectedFeed) ?? .top }
    private var visible: [HNItem] { model.items.filter { !reading.isHidden($0) && !(hideRead && reading.isRead($0.id)) } }

    var body: some View {
        List {
            if model.isCached, let updated = model.updatedAt {
                Label("Saved feed · \(updated.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(EmberStyle.secondaryText).listRowSeparator(.hidden)
            }
            if let error = model.error { InlineNotice(message: error) { Task { await model.refresh() } }.listRowSeparator(.hidden) }
            if model.isLoading, model.items.isEmpty {
                HStack { Spacer(); ProgressView("Loading stories…"); Spacer() }.padding(.vertical, 60).listRowSeparator(.hidden)
            } else if visible.isEmpty, model.error == nil {
                EmptyState(title: model.items.isEmpty ? "No stories yet" : "You’re caught up", symbol: "text.alignleft",
                           detail: model.items.isEmpty ? "Pull to refresh in a moment." : "Tap the feed name above to choose another feed or show read stories.")
                    .listRowSeparator(.hidden)
            }
            ForEach(visible) { item in
                NavigationLink(value: item) {
                    StoryRow(item: item)
                }
                .accessibilityIdentifier("story-\(item.id)")
                .storyActions(item)
            }
            if model.hasMore {
                PageButton(loading: model.isLoadingMore) { Task { await model.loadMore() } }.listRowSeparator(.hidden)
            }
            if !model.items.isEmpty, !model.hasMore, !model.isLoading, model.error == nil {
                Text("You’ve reached the end.").font(.caption).foregroundStyle(EmberStyle.secondaryText)
                    .frame(maxWidth: .infinity).padding(.vertical, 16).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .readingWidth()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { feedPicker }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { feedPicker }
            }
        }
        .refreshable { await model.refresh() }
        .task(id: selectedFeed) { await model.load(feed) }
    }

    private var feedPicker: some View {
        Menu {
            Picker("Feed", selection: $selectedFeed) {
                ForEach(Feed.allCases) { feed in Text(feed.title).tag(feed.rawValue) }
            }
            Divider()
            Toggle("Hide read stories", isOn: $hideRead)
        } label: {
            HStack(spacing: 6) {
                Text(feed.title).font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EmberStyle.secondaryText)
            }
            .foregroundStyle(.primary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose feed, \(feed.title) selected")
        .accessibilityIdentifier("feed-menu")
    }
}
