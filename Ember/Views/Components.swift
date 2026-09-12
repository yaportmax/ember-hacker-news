import SwiftUI
import SafariServices

enum EmberStyle {
    static let canvas = Color(uiColor: .systemBackground)
    static let subtle = Color(uiColor: .secondarySystemBackground)
    static let secondaryText = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.75 : 0.38, alpha: 1)
    })
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
            Label(message, systemImage: symbol).font(.subheadline).foregroundStyle(EmberStyle.secondaryText)
            if let retry { Button("Try again", action: retry).font(.subheadline.weight(.semibold)).frame(minHeight: 44).buttonStyle(.borderless) }
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
    var alignment: Alignment = .center
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if loading { ProgressView().controlSize(.small) }
                Text(loading ? "Loading…" : title)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: alignment)
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
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
    @Environment(ReadingStore.self) private var reading
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("compactRows") private var compact = false
    @AppStorage("dimReadStories") private var dimRead = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            Text(item.displayTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(dimRead && reading.isRead(item.id) ? EmberStyle.secondaryText : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            if !compact, let domain = item.domain {
                Text(domain).font(.caption).foregroundStyle(EmberStyle.secondaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { statistics; timeAndBookmark }
            } else {
                HStack(spacing: 8) { statistics; separator; timeAndBookmark }
            }
        }
        .font(.caption).foregroundStyle(EmberStyle.secondaryText)
        .padding(.vertical, compact ? 8 : 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens discussion")
    }

    @ViewBuilder private var statistics: some View {
        if item.type == "job" { Text("Job") }
        else {
            // Text can wrap at accessibility sizes; icons do not imply voting.
            Text("\(max(0, item.score ?? 0).formatted()) points · \(item.commentCount.formatted()) \(item.commentCount == 1 ? "comment" : "comments")")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var separator: some View { Text("·").accessibilityHidden(true) }
    private var timeAndBookmark: some View {
        HStack(spacing: 8) {
            RelativeTime(date: item.date).fixedSize()
            if reading.isSaved(item.id) {
                Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor).accessibilityLabel("Saved")
            }
        }
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
                if let url = item.articleURL { ShareLink(item: url) { Label("Share article", systemImage: "square.and.arrow.up") } }
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
