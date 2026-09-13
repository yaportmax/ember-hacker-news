import SwiftUI

struct FeedView: View {
    @State private var model: FeedModel
    @AppStorage("selectedFeed") private var selectedFeed = Feed.top.rawValue
    @AppStorage("feedPeriod") private var period = FeedPeriod.live
    @AppStorage("feedStartDate") private var startTimestamp = 0.0
    @AppStorage("feedEndDate") private var endTimestamp = 0.0
    @State private var customDates = false
    @State private var selectedList: HNList?
    private let service: any HNService
    @AppStorage("hideReadStories") private var hideRead = false
    @Environment(ReadingStore.self) private var reading

    let openDiscussion: (HNItem) -> Void
    init(service: any HNService, cache: FeedCache, openDiscussion: @escaping (HNItem) -> Void) {
        _model = State(initialValue: FeedModel(service: service, cache: cache))
        self.openDiscussion = openDiscussion
        self.service = service
    }
    private var feed: Feed { Feed(rawValue: selectedFeed) ?? .top }
    private var visible: [HNItem] { model.items.filter { !reading.isHidden($0) && !(hideRead && reading.isRead($0.id)) } }

    private var selectionKey: String { "\(selectedFeed)|\(period.rawValue)|\(startTimestamp)|\(endTimestamp)" }
    private var window: ArchiveWindow? {
        period.window(start: Date(timeIntervalSince1970: startTimestamp), end: Date(timeIntervalSince1970: endTimestamp))
    }
    private var periodTitle: String {
        if period == .custom {
            return "\(Date(timeIntervalSince1970: startTimestamp).formatted(.dateTime.month(.abbreviated).day()))–\(Date(timeIntervalSince1970: endTimestamp).formatted(.dateTime.month(.abbreviated).day()))"
        }
        return period.title
    }

    var body: some View {
        List {
            if let error = model.error { InlineNotice(message: error) { Task { await model.load(feed, window: window) } }.listRowSeparator(.hidden) }
            if model.isLoading, model.items.isEmpty {
                HStack { Spacer(); ProgressView("Loading stories…"); Spacer() }.padding(.vertical, 60).listRowSeparator(.hidden)
            } else if visible.isEmpty, model.error == nil {
                EmptyState(title: model.items.isEmpty ? "No stories yet" : "You’re caught up", symbol: "text.alignleft",
                           detail: model.items.isEmpty ? "Pull to refresh in a moment." : "Tap the feed name above to choose another feed or show read stories.")
                    .listRowSeparator(.hidden)
            }
            ForEach(visible) { item in
                StoryRow(item: item, openDiscussion: { openDiscussion(item) })
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
                ToolbarItem(placement: .topBarTrailing) { periodPicker }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { feedPicker }
                ToolbarItem(placement: .topBarTrailing) { periodPicker }
            }
        }
        .refreshable { await model.load(feed, window: window) }
        .task(id: selectionKey) { await model.load(feed, window: window) }
        .navigationDestination(item: $selectedList) { list in
            HNListingView(list: list, service: service, openDiscussion: openDiscussion)
        }
        .sheet(isPresented: $customDates) {
            CustomFeedDates(start: Date(timeIntervalSince1970: startTimestamp > 0 ? startTimestamp : Date().addingTimeInterval(-604800).timeIntervalSince1970),
                            end: Date(timeIntervalSince1970: endTimestamp > 0 ? endTimestamp : Date().timeIntervalSince1970)) { start, end in
                startTimestamp = start.timeIntervalSince1970; endTimestamp = end.timeIntervalSince1970; period = .custom
            }
        }
    }

    private var periodPicker: some View {
        Menu {
            ForEach(FeedPeriod.allCases) { option in
                Button {
                    if option == .custom { customDates = true } else { period = option }
                } label: {
                    if option == period { Label(option.title, systemImage: "checkmark") }
                    else { Text(option.title) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(periodTitle).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.font(.subheadline).foregroundStyle(EmberStyle.secondaryText).frame(minHeight: 44)
        }
        .accessibilityLabel("Time period, \(period.title) selected")
        .accessibilityHint(period == .live ? "Current Hacker News feed" : "Archive sorted by \(feed == .new || feed == .jobs ? "newest first" : "most points")")
        .accessibilityIdentifier("period-menu")
    }

    private var feedPicker: some View {
        Menu {
            Picker("Feed", selection: $selectedFeed) {
                ForEach(Feed.allCases) { feed in Text(feed.title).tag(feed.rawValue) }
            }
            Menu("More feeds") {
                ForEach(HNList.allCases) { list in Button(list.title) { selectedList = list } }
                Divider()
                Link("All lists on Hacker News", destination: HNLinks.home.appendingPathComponent("lists"))
            }
            Divider()
            Toggle("Hide read stories", isOn: $hideRead)
        } label: {
            HStack(spacing: 8) {
                Text(feed.title).font(.largeTitle.bold())
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(EmberStyle.secondaryText)
            }
            .foregroundStyle(.primary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(Color(uiColor: .label))
        .accessibilityLabel("Choose feed, \(feed.title) selected")
        .accessibilityIdentifier("feed-menu")
    }
}

private struct CustomFeedDates: View {
    @State var start: Date
    @State var end: Date
    let apply: (Date, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, in: ...min(end, Date()), displayedComponents: .date)
                DatePicker("Through", selection: $end, in: min(start, Date())...Date(), displayedComponents: .date)
                Section {
                    Text("Includes both dates. Archived Top, Best, Ask HN, and Show HN are sorted by points; New and Jobs are sorted by date.")
                        .font(.footnote).foregroundStyle(EmberStyle.secondaryText)
                }
            }
            .navigationTitle("Custom dates").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply(start, end); dismiss() }.accessibilityIdentifier("apply-dates") }
            }
        }.presentationDetents([.medium, .large])
    }
}

private struct HNListingView: View {
    let list: HNList
    let service: any HNService
    let openDiscussion: (HNItem) -> Void
    @State private var model: HNListingModel
    @State private var profile: String?
    @State private var commentHours = 48
    @State private var reportItem: HNItem?
    @Environment(ReadingStore.self) private var reading
    init(list: HNList, service: any HNService, openDiscussion: @escaping (HNItem) -> Void) {
        self.list = list; self.service = service; self.openDiscussion = openDiscussion
        _model = State(initialValue: HNListingModel(service: service))
    }
    private var sourceURL: URL {
        guard list == .bestcomments else { return list.url }
        var parts = URLComponents(url: list.url, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "h", value: String(commentHours))]
        return parts.url!
    }
    var body: some View {
        List {
            Text(list == .bestcomments ? "Most-upvoted comments of the past \(commentHours) hours." : list.detail).font(.subheadline).foregroundStyle(EmberStyle.secondaryText).listRowSeparator(.hidden)
            if let error = model.error {
                InlineNotice(message: error) { Task { await model.load(sourceURL) } }
                Link("Open on Hacker News", destination: sourceURL)
            }
            if model.loading && model.items.isEmpty { ProgressView("Loading…").listRowSeparator(.hidden) }
            ForEach(model.items.filter { !reading.isHidden($0) }) { item in
                if item.type == "comment" {
                    ListedComment(item: item, openDiscussion: { openDiscussion(item) }, profile: { profile = item.by }, report: { reportItem = item })
                } else {
                    StoryRow(item: item, openDiscussion: { openDiscussion(item) }).storyActions(item)
                }
            }
            if let next = model.next {
                PageButton(loading: model.loading) { Task { await model.load(next, more: true) } }.listRowSeparator(.hidden)
            }
            if model.items.isEmpty, !model.loading, model.error == nil {
                Text("No entries right now.").foregroundStyle(EmberStyle.secondaryText)
            }
        }
        .listStyle(.plain).readingWidth().navigationTitle(list.title).navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load(sourceURL) }
        .task(id: sourceURL) { await model.load(sourceURL) }
        .toolbar {
            if list == .bestcomments {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Time period", selection: $commentHours) {
                            Text("Past 24 hours").tag(24)
                            Text("Past 48 hours").tag(48)
                            Text("Past week").tag(168)
                        }
                    } label: { Text(commentHours == 168 ? "Week" : "\(commentHours)h").font(.subheadline) }
                    .accessibilityLabel("Best Comments time period").accessibilityIdentifier("best-comments-period")
                }
            }
        }
        .navigationDestination(item: $profile) { name in ProfileView(username: name, service: service) }
        .navigationDestination(item: $reportItem) { item in ReportView(item: item) }
    }
}

private struct ListedComment: View {
    let item: HNItem
    let openDiscussion: () -> Void
    let profile: () -> Void
    let report: () -> Void
    @State private var collapsed = false
    @Environment(ReadingStore.self) private var reading
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommentView(item: item, depth: 0, collapsed: collapsed, isOP: false, profile: profile,
                        toggle: { collapsed.toggle() }, block: { reading.block(item.by ?? "") }, report: report)
            if !collapsed {
                Button("View discussion", action: openDiscussion).font(.caption).frame(minHeight: 44)
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityIdentifier("thread-\(item.id)")
            }
        }
    }
}
