import SwiftUI
import SafariServices

enum EmberStyle {
    static let canvas = Color(uiColor: .systemBackground)
    static let subtle = Color(uiColor: .secondarySystemBackground)
    static let measure: CGFloat = 760
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let reader: Bool
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = reader
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(named: "AccentColor") ?? .systemOrange
        controller.dismissButtonStyle = .done
        return controller
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct RichText: View {
    private let value: AttributedString
    init(_ html: String) {
        var output = AttributedString()
        for run in HNHTML.runs(html) {
            var text = AttributedString(run.text)
            var font = run.code ? Font.system(.body, design: .monospaced) : Font.body
            if run.bold { font = font.bold() }
            if run.italic { font = font.italic() }
            text.font = font
            if let url = run.link { text.link = url }
            output.append(text)
        }
        value = output
    }
    var body: some View {
        Text(value).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineNotice: View {
    let message: String
    var symbol = "wifi.exclamationmark"
    var retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            if let retry { Button("Try again", action: retry).font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

struct EmptyState: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        }
        .padding(.vertical, 32)
    }
}

struct PageButton: View {
    var title = "Load more"
    let loading: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if loading { ProgressView().controlSize(.small) }
                Text(loading ? "Loading…" : title)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(loading)
        .accessibilityIdentifier("load-more")
    }
}

struct RelativeTime: View {
    let date: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(Self.short(date, now: context.date))
                .accessibilityLabel(date.formatted(date: .abbreviated, time: .shortened))
        }
    }
    static func short(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct StoryRow: View {
    let item: HNItem
    var rank: Int?
    @Environment(ReadingStore.self) private var reading
    @AppStorage("compactRows") private var compact = false
    @AppStorage("dimReadStories") private var dimRead = true

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            if let rank {
                Text(rank.formatted())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 21, alignment: .trailing)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: compact ? 5 : 9) {
                Text(item.displayTitle)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(dimRead && reading.isRead(item.id) ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                if !compact, let domain = item.domain {
                    Text(domain).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ViewThatFits(in: .horizontal) {
                    metadata(includeAuthor: true)
                    metadata(includeAuthor: false)
                }
            }
        }
        .padding(.vertical, compact ? 9 : 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the discussion and article actions")
    }

    private func metadata(includeAuthor: Bool) -> some View {
        HStack(spacing: 10) {
            if item.type == "job" { Text("JOB").fontWeight(.medium) }
            else {
                Label(max(0, item.score ?? 0).formatted(), systemImage: "arrow.up")
                    .accessibilityLabel("\(max(0, item.score ?? 0)) points")
                Label(item.commentCount.formatted(), systemImage: "bubble.right")
                    .accessibilityLabel("\(item.commentCount) comments")
            }
            if includeAuthor, let by = item.by { Text(by).lineLimit(1) }
            RelativeTime(date: item.date)
            if reading.isSaved(item.id) { Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor).accessibilityLabel("Saved") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct StoryActions: ViewModifier {
    let item: HNItem
    @Environment(AppContainer.self) private var app
    @Environment(ReadingStore.self) private var reading

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let url = item.articleURL { Button("Read article", systemImage: "safari") { reading.record(item); app.open(url) } }
                Button(reading.isSaved(item.id) ? "Remove bookmark" : "Save story", systemImage: reading.isSaved(item.id) ? "bookmark.slash" : "bookmark") { reading.toggleBookmark(item) }
                ShareLink(item: item.articleURL ?? item.discussionURL) { Label("Share article", systemImage: "square.and.arrow.up") }
                ShareLink(item: item.discussionURL) { Label("Share discussion", systemImage: "bubble.right") }
                Button("Open on Hacker News", systemImage: "arrow.up.right.square") { app.open(item.discussionURL) }
                Divider()
                Button("Hide story", systemImage: "eye.slash", role: .destructive) { reading.hide(item.id) }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button { reading.toggleBookmark(item) } label: {
                    Label(reading.isSaved(item.id) ? "Unsave" : "Save", systemImage: reading.isSaved(item.id) ? "bookmark.slash" : "bookmark")
                }.tint(Color.accentColor)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if let url = item.articleURL {
                    Button { reading.record(item); app.open(url) } label: { Label("Read", systemImage: "safari") }.tint(.blue)
                }
            }
    }
}

extension View {
    func storyActions(_ item: HNItem) -> some View { modifier(StoryActions(item: item)) }
    func readingWidth() -> some View { frame(maxWidth: EmberStyle.measure).frame(maxWidth: .infinity) }
}
