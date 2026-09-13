import SwiftUI

struct DiscussionView: View {
    @AppStorage("commentRowSpacing") private var rowSpacing = 7.0
    @AppStorage("replyIndent") private var replyIndent = 12.0
    @State private var model: DiscussionModel
    @State private var userToBlock: String?
    @State private var reportItem: HNItem?
    @State private var selectedUsername: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppContainer.self) private var app
    @Environment(ReadingStore.self) private var reading
    private let service: any HNService

    init(story: HNItem, service: any HNService) {
        _model = State(initialValue: DiscussionModel(story: story, service: service))
        self.service = service
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                storyHeader.padding(.top, 8).padding(.bottom, 4)
                if let error = model.error { InlineNotice(message: error) { Task { await reload() } } }
                if !model.story.isVisible {
                    InlineNotice(message: "This story has been removed from Hacker News.", symbol: "text.badge.xmark")
                } else if let text = model.story.text, !text.isEmpty {
                    RichText(text).padding(.vertical, 12)
                }
                ForEach(model.polls.filter(\.isVisible)) { option in
                    HStack(alignment: .top) {
                        Text(max(0, option.score ?? 0).formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(Color.accentColor).frame(minWidth: 32)
                        RichText(option.text ?? "")
                    }.padding(.vertical, 5)
                }
                if model.story.isVisible, model.story.articleURL == nil { articleAction }
                if model.story.type != "job" {
                    Text(model.story.commentCount == 1 ? "1 comment" : "\(model.story.commentCount.formatted()) comments")
                        .font(.subheadline.weight(.medium)).foregroundStyle(EmberStyle.secondaryText)
                        .padding(.top, 20).padding(.bottom, 12).accessibilityAddTraits(.isHeader)
                    if model.isLoading, model.comments.isEmpty {
                        HStack { Spacer(); ProgressView("Loading discussion…"); Spacer() }.padding(.vertical, 28)
                    }
                    if (model.story.kids ?? []).isEmpty, !model.isLoading, model.error == nil {
                        EmptyState(title: "Quiet for now", symbol: "bubble.left.and.bubble.right", detail: "Be the first to join the discussion on Hacker News.")
                    }
                    if !(model.story.kids ?? []).isEmpty, !model.isLoading, model.error == nil,
                       model.rows(blocked: reading.archive.blockedUsers).isEmpty {
                        EmptyState(title: "Comments are hidden", symbol: "eye.slash", detail: "There are no visible comments right now. Removed comments and blocked users are hidden.")
                    }
                    ForEach(model.rows(blocked: reading.archive.blockedUsers)) { row in
                        let comment = row.item
                        VStack(spacing: 0) {
                            CommentView(item: comment, depth: row.depth, collapsed: model.collapsed.contains(comment.id),
                                        isOP: comment.by == model.story.by,
                                        profile: { selectedUsername = comment.by },
                                        toggle: { model.toggle(comment.id) }, block: { userToBlock = comment.by }, report: { reportItem = comment })
                                .padding(.top, rowSpacing)
                                .padding(.bottom, model.collapsed.contains(comment.id) ? 0 : rowSpacing)
                            Divider()
                        }
                        .padding(.leading, indent(row.depth))
                        .id(row.id)
                        .anchorPreference(key: CommentAnchorsKey.self, value: .bounds) { [comment.id: $0] }
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 72)
        }
        .readingWidth()
        .overlayPreferenceValue(CommentAnchorsKey.self) { anchors in
            GeometryReader { geometry in
                if let target = nextCommentTarget(anchors: anchors, geometry: geometry) {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                proxy.scrollTo(target, anchor: .top)
                            } label: {
                                Image(systemName: "arrow.down").font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                                    .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Next comment or reply")
                            .accessibilityIdentifier("next-comment")
                        }
                    }.padding(16)
                }
            }
        }
        .navigationTitle(model.story.type == "job" ? "Job" : "Discussion").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { reading.toggleBookmark(model.story) } label: {
                    Image(systemName: reading.isSaved(model.story.id) ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(reading.isSaved(model.story.id) ? "Remove bookmark" : "Save story")
                .accessibilityIdentifier("bookmark-story")
                Menu {
                    if model.story.articleURL != nil, model.story.isVisible {
                        Button(articleActionTitle, systemImage: "arrow.up.right", action: openArticle)
                    }
                    ShareLink(item: model.story.discussionURL) { Label("Share discussion", systemImage: "square.and.arrow.up") }
                    if let url = model.story.articleURL { ShareLink(item: url) { Label("Share article", systemImage: "link") } }
                    Button(model.story.type == "job" ? "Open on Hacker News" : "Vote or reply on HN", systemImage: "arrow.up.right.square") { app.open(model.story.discussionURL) }
                    Divider()
                    if !(model.story.kids ?? []).isEmpty {
                    Button("Collapse all threads", systemImage: "arrow.up.right.and.arrow.down.left") { model.collapseAll() }
                    Button("Expand all threads", systemImage: "arrow.down.left.and.arrow.up.right") { model.expandAll() }
                    }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                    Divider()
                    Button("Report story", systemImage: "flag") { reportItem = model.story }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Discussion actions")
            }
        }
        .refreshable { await reload() }
        .navigationDestination(item: $reportItem) { item in ReportView(item: item) }
        .navigationDestination(item: $selectedUsername) { name in ProfileView(username: name, service: service) }
        .task {
            reading.record(model.story)
            await reload()
        }
        .confirmationDialog("Block \(userToBlock ?? "this user")?", isPresented: Binding(get: { userToBlock != nil }, set: { if !$0 { userToBlock = nil } }), titleVisibility: .visible) {
            Button("Block user", role: .destructive) {
                if let userToBlock { reading.block(userToBlock) }
                userToBlock = nil
            }
        } message: { Text("Their stories and comments will be hidden on this device. You can unblock them in Settings.") }
    }

    }

    private func nextCommentTarget(anchors: [Int: Anchor<CGRect>], geometry: GeometryProxy) -> String? {
        let rows = model.rows(blocked: reading.archive.blockedUsers)
        guard !rows.isEmpty else { return nil }
        if let last = rows.last, let anchor = anchors[last.item.id],
           geometry[anchor].maxY <= geometry.size.height { return nil }
        for (index, row) in rows.enumerated() {
            guard let anchor = anchors[row.item.id] else { continue }
            let frame = geometry[anchor]
            if frame.maxY > 16 && frame.minY < geometry.size.height {
                return index + 1 < rows.count ? rows[index + 1].id : nil
            }
        }
        return rows.first?.id
    }

    private var storyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let domain = model.story.domain {
                Text(domain).font(.subheadline).foregroundStyle(EmberStyle.secondaryText)
                    .accessibilityLabel("Source: \(domain)")
            }
            if model.story.articleURL != nil, model.story.isVisible {
                Button(action: openArticle) { storyTitle.frame(minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens article")
                    .accessibilityIdentifier("article-title")
            } else { storyTitle }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { author; metadata }
            } else {
                HStack(spacing: 12) { author; metadata; Spacer(minLength: 0) }
            }
            if model.story.isVisible, model.story.articleURL != nil { articleAction }

        }.padding(.top, 8).padding(.bottom, 4)
    }

    private var articleActionTitle: String {
        model.story.type == "job" ? "View job" : (model.story.articleURL == nil ? "Join on Hacker News" : "Read article")
    }

    private var articleAction: some View {
        Button(action: openArticle) {
            HStack(spacing: 6) {
                Text(articleActionTitle)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
        .accessibilityLabel(articleActionTitle).accessibilityIdentifier("read-article")
    }

    private var storyTitle: some View {
        Text(model.story.displayTitle).modifier(StoryTypography(heading: true))
            .foregroundStyle(.primary).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var author: some View {
        if let by = model.story.by {
            Button { selectedUsername = by } label: {
                Text(by).font(.subheadline.weight(.medium)).frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Profile: \(by)")
            .accessibilityIdentifier("story-author")
        }
    }
    private var metadata: some View {
        HStack(spacing: 8) {
            if model.story.type != "job" {
                Text("\(max(0, model.story.score ?? 0).formatted()) points")
                MetadataSeparator()
            }
            RelativeTime(date: model.story.date)
        }.font(.caption).foregroundStyle(EmberStyle.secondaryText)
    }
    private func openArticle() {
        reading.record(model.story)
        app.open(model.story.articleURL ?? model.story.discussionURL)
    }
    private func indent(_ depth: Int) -> CGFloat {
        CGFloat(min(depth, typeSize.isAccessibilitySize ? 2 : 5)) * (typeSize.isAccessibilitySize ? min(replyIndent, 6) : replyIndent)
    }
    private func reload() async {
        await model.load()
        if !Task.isCancelled, model.error == nil { reading.record(model.story) }
    }
}

struct CommentView: View {
    let item: HNItem
    let depth: Int
    let collapsed: Bool
    let isOP: Bool
    let profile: () -> Void
    let toggle: () -> Void
    let block: () -> Void
    let report: () -> Void
    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let by = item.by, item.isVisible {
                    Button(action: profile) {
                        Text(by).font(.subheadline.weight(.semibold)).foregroundStyle(isOP ? Color.accentColor : .primary)
                            .fixedSize(horizontal: false, vertical: true).frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Profile: \(by)")
                } else { Text("[deleted]").font(.subheadline).foregroundStyle(EmberStyle.secondaryText) }
                if isOP, item.isVisible { Text("OP").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor).accessibilityLabel("Original poster") }
                RelativeTime(date: item.date).font(.caption).foregroundStyle(EmberStyle.secondaryText)
                Spacer(minLength: 4)
                Button(action: toggle) {
                    Image(systemName: collapsed ? "plus" : "minus").font(.caption.weight(.semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(EmberStyle.secondaryText)
                    .accessibilityLabel(collapsed ? "Expand comment by \(item.by ?? "deleted user")" : "Collapse comment by \(item.by ?? "deleted user")")
                    .accessibilityIdentifier("collapse-\(item.id)")
            }
            if !collapsed {
                RichText(item.text ?? "").padding(.bottom, 6).accessibilityIdentifier("comment-text-\(item.id)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .accessibilityAction(named: collapsed ? "Expand thread" : "Collapse thread", toggle)
        .padding(.leading, depth > 0 ? 10 : 0)
        .overlay(alignment: .leading) {
            if depth > 0 { Rectangle().fill(Color.accentColor.opacity(0.25)).frame(width: 1).padding(.vertical, 10).accessibilityHidden(true) }
        }
        .contextMenu {
            Button(collapsed ? "Expand thread" : "Collapse thread", systemImage: collapsed ? "plus" : "minus", action: toggle)
            Button("Reply on Hacker News", systemImage: "arrowshape.turn.up.left") { app.open(item.discussionURL) }
            ShareLink(item: item.discussionURL) { Label("Share comment", systemImage: "square.and.arrow.up") }
            Button("Report comment", systemImage: "flag", action: report)
            if item.by != nil { Button("Block user", systemImage: "person.slash", role: .destructive, action: block) }
        }
    }
}

private struct CommentAnchorsKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
