import SwiftUI

struct DiscussionView: View {
    @State private var model: DiscussionModel
    @State private var userToBlock: String?
    @State private var reportItem: HNItem?
    @Environment(AppContainer.self) private var app
    @Environment(ReadingStore.self) private var reading
    private let service: any HNService

    init(story: HNItem, service: any HNService) {
        _model = State(initialValue: DiscussionModel(story: story, service: service))
        self.service = service
    }

    var body: some View {
        List {
            storyHeader.listRowSeparator(.hidden)
            if let error = model.error { InlineNotice(message: error) { Task { await reload() } }.listRowSeparator(.hidden) }
            if !model.story.isVisible {
                InlineNotice(message: "This story has been removed from Hacker News.", symbol: "text.badge.xmark").listRowSeparator(.hidden)
            } else if let text = model.story.text, !text.isEmpty {
                RichText(text).padding(.vertical, 12).listRowSeparator(.hidden)
            }
            ForEach(model.polls.filter(\.isVisible)) { option in
                HStack(alignment: .top) {
                    Text(max(0, option.score ?? 0).formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(Color.accentColor).frame(minWidth: 32)
                    RichText(option.text ?? "")
                }.padding(.vertical, 5)
            }
            Section {
                if model.isLoading, model.comments.isEmpty {
                    HStack { Spacer(); ProgressView("Loading discussion…"); Spacer() }.padding(.vertical, 28).listRowSeparator(.hidden)
                }
                if (model.story.kids ?? []).isEmpty, !model.isLoading, model.error == nil {
                    EmptyState(title: "Quiet for now", symbol: "bubble.left.and.bubble.right", detail: "Be the first to join the discussion on Hacker News.")
                        .listRowSeparator(.hidden)
                }
                ForEach(model.rows(blocked: reading.archive.blockedUsers)) { row in
                    switch row.kind {
                    case .comment(let comment):
                        CommentView(item: comment, depth: row.depth, collapsed: model.collapsed.contains(comment.id),
                                    isOP: comment.by == model.story.by, service: service,
                                    toggle: { model.toggle(comment.id) }, block: { userToBlock = comment.by }, report: { reportItem = comment })
                            .listRowInsets(EdgeInsets(top: 7, leading: 20 + CGFloat(min(row.depth, 5)) * 12, bottom: 7, trailing: 20))
                    case .more(let parent, let remaining):
                        VStack(alignment: .leading, spacing: 3) {
                            if let error = model.branchErrors[parent] { Text(error).font(.caption).foregroundStyle(.secondary) }
                            PageButton(title: model.branchErrors[parent] == nil ? "\(parent == model.story.id ? "More comments" : "Show replies") (\(remaining))" : "Retry loading replies",
                                       loading: model.loadingParents.contains(parent)) { Task { await model.loadChildren(of: parent) } }
                                .accessibilityIdentifier("replies-\(parent)")
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 20 + CGFloat(min(row.depth, 5)) * 12, bottom: 4, trailing: 20))
                        .listRowSeparator(.hidden)
                    }
                }
            } header: {
                HStack { Text("Discussion"); Spacer(); Text(model.story.commentCount.formatted()).monospacedDigit() }
                    .font(.caption.weight(.semibold)).textCase(nil).padding(.vertical, 10)
            }
        }
        .listStyle(.plain).readingWidth()
        .navigationTitle("Discussion").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { reading.toggleBookmark(model.story) } label: {
                    Image(systemName: reading.isSaved(model.story.id) ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(reading.isSaved(model.story.id) ? "Remove bookmark" : "Save story")
                .accessibilityIdentifier("bookmark-story")
                Menu {
                    ShareLink(item: model.story.discussionURL) { Label("Share discussion", systemImage: "square.and.arrow.up") }
                    if let url = model.story.articleURL { ShareLink(item: url) { Label("Share article", systemImage: "link") } }
                    Button("Vote or reply on HN", systemImage: "arrow.up.right.square") { app.open(model.story.discussionURL) }
                    Divider()
                    Button("Collapse all threads", systemImage: "arrow.up.right.and.arrow.down.left") { model.collapseAll() }
                    Button("Expand loaded threads", systemImage: "arrow.down.left.and.arrow.up.right") { model.expandAll() }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                    Divider()
                    Button("Report story", systemImage: "flag") { reportItem = model.story }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Discussion actions")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.story.isVisible {
                Button {
                    reading.record(model.story)
                    app.open(model.story.articleURL ?? model.story.discussionURL)
                } label: {
                    HStack {
                        Image(systemName: model.story.articleURL == nil ? "bubble.left.and.bubble.right" : "safari")
                        Text(model.story.articleURL == nil ? "Join on Hacker News" : "Read article")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                    }.font(.subheadline.weight(.semibold)).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("read-article")
                .padding(.horizontal, 20).padding(.vertical, 10)
                .readingWidth().background(.bar)
            }
        }
        .refreshable { await reload() }
        .navigationDestination(item: $reportItem) { item in ReportView(item: item) }
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

    private var storyHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let domain = model.story.domain {
                Text(domain.uppercased()).font(.system(.caption2, design: .monospaced, weight: .medium)).tracking(1).foregroundStyle(Color.accentColor)
            }
            Text(model.story.displayTitle).font(.system(.title2, weight: .bold)).lineSpacing(3).textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { author; metadata }
                VStack(alignment: .leading, spacing: 10) { author; metadata }
            }
        }.padding(.top, 16).padding(.bottom, 18)
    }

    @ViewBuilder private var author: some View {
        if let by = model.story.by {
            NavigationLink { ProfileView(username: by, service: service) } label: { Text(by).font(.subheadline.weight(.medium)).frame(minHeight: 44) }.buttonStyle(.plain)
        }
    }
    private var metadata: some View {
        HStack(spacing: 12) {
            Label("\(max(0, model.story.score ?? 0)) points", systemImage: "arrow.up")
            RelativeTime(date: model.story.date)
        }.font(.caption).foregroundStyle(.secondary)
    }
    private func reload() async {
        await model.load()
        if !Task.isCancelled, model.error == nil { reading.record(model.story) }
    }
}

private struct CommentView: View {
    let item: HNItem
    let depth: Int
    let collapsed: Bool
    let isOP: Bool
    let service: any HNService
    let toggle: () -> Void
    let block: () -> Void
    let report: () -> Void
    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let by = item.by, item.isVisible {
                    NavigationLink { ProfileView(username: by, service: service) } label: {
                        Text(by).font(.subheadline.weight(.semibold)).foregroundStyle(isOP ? Color.accentColor : .primary).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                } else { Text("[deleted]").font(.subheadline).foregroundStyle(.secondary) }
                if isOP, item.isVisible { Text("OP").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                RelativeTime(date: item.date).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button(action: toggle) {
                    Image(systemName: collapsed ? "plus" : "minus").font(.caption.weight(.semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(collapsed ? "Expand comment by \(item.by ?? "deleted user")" : "Collapse comment by \(item.by ?? "deleted user")")
                    .accessibilityIdentifier("collapse-\(item.id)")
            }
            if collapsed {
                Text(item.isVisible ? HNHTML.plainText(item.text ?? "") : "Comment removed")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let kids = item.kids, !kids.isEmpty { Text("\(kids.count) replies hidden").font(.caption).foregroundStyle(.secondary) }
            } else if item.isVisible {
                RichText(item.text ?? "").padding(.bottom, 14).accessibilityIdentifier("comment-text-\(item.id)")
            } else {
                Text("Comment removed").font(.subheadline).italic().foregroundStyle(.secondary).padding(.bottom, 12)
            }
        }
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
