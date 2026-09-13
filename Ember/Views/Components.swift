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

enum ReadingFont: String, CaseIterable, Identifiable {
    case system, serif, rounded, monospaced
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
}

struct StoryTypography: ViewModifier {
    var heading = false
    @AppStorage("storyTextSize") private var size = 17.0
    @AppStorage("storyFont") private var font = ReadingFont.system
    @AppStorage("storyLineSpacing") private var spacing = 2.0
    @AppStorage("boldStoryTitles") private var bold = true
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    func body(content: Content) -> some View {
        content.font(.system(size: (size + (heading ? 5 : 0)) * scale,
                             weight: bold ? (heading ? .bold : .semibold) : .regular, design: font.design))
            .lineSpacing(spacing * scale)
    }
}

struct RichText: View {
    private let html: String
    private let preparedRuns: [HNHTML.Run]?
    @AppStorage("commentTextSize") private var size = 17.0
    @AppStorage("commentFont") private var font = ReadingFont.system
    @AppStorage("commentLineSpacing") private var spacing = 5.0
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    init(_ html: String, runs: [HNHTML.Run]? = nil) { self.html = html; self.preparedRuns = runs }
    private var value: AttributedString {
        var output = AttributedString()
        for run in preparedRuns ?? HNHTML.runs(html) {
            var text = AttributedString(run.text)
            var runFont = Font.system(size: size * scale, design: run.code ? .monospaced : font.design)
            if run.bold { runFont = runFont.bold() }
            if run.italic { runFont = runFont.italic() }
            text.font = runFont
            if let url = run.link { text.link = url }
            output.append(text)
        }
        return output
    }
    var body: some View {
        Text(value).lineSpacing(spacing * scale).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
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
            .contentShape(Rectangle())
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
    let openDiscussion: () -> Void
    @Environment(ReadingStore.self) private var reading
    @Environment(AppContainer.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("compactRows") private var compact = false
    @AppStorage("dimReadStories") private var dimRead = true
    @AppStorage("storyRowSpacing") private var rowSpacing = 12.0

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 3) {
            Button {
                if let url = item.articleURL { reading.record(item); app.open(url) }
                else { openDiscussion() }
            } label: {
                VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                    Text(item.displayTitle).modifier(StoryTypography())
                        .foregroundStyle(dimRead && reading.isRead(item.id) ? EmberStyle.secondaryText : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact, let domain = item.domain {
                        Text(domain).font(.caption).foregroundStyle(EmberStyle.secondaryText)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("article-\(item.id)")
            .accessibilityHint(item.articleURL == nil ? "Opens discussion" : "Opens article")
            Button(action: openDiscussion) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { statistics; MetadataSeparator(); timeAndBookmark }
                    VStack(alignment: .leading, spacing: 4) { statistics; timeAndBookmark }
                }
                .font(.caption).foregroundStyle(EmberStyle.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("story-\(item.id)")
            .accessibilityLabel("\(item.commentCount) comments on \(item.displayTitle)")
            .accessibilityHint("Opens discussion")
        }
        .padding(.vertical, compact ? max(0, rowSpacing - 4) : rowSpacing)
    }

    @ViewBuilder private var statistics: some View {
        if item.type == "job" { Text("Job details") }
        else {
            Text("\(max(0, item.score ?? 0).formatted()) points · \(item.commentCount.formatted()) \(item.commentCount == 1 ? "comment" : "comments")")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var timeAndBookmark: some View {
        HStack(spacing: 8) {
            RelativeTime(date: item.date).fixedSize()
            if reading.isSaved(item.id) {
                Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor).accessibilityLabel("Saved")
            }
        }
    }
}

struct MetadataSeparator: View {
    var body: some View {
        Circle().fill(.primary).frame(width: 2, height: 2).accessibilityHidden(true)
    }
}

struct StoryActions: ViewModifier {
    let item: HNItem
    @Environment(AppContainer.self) private var app
    @Environment(ReadingStore.self) private var reading

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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
    func readingWidth(grouped: Bool = false) -> some View { modifier(ReadingWidth(grouped: grouped)) }
}

private struct ReadingWidth: ViewModifier {
    let grouped: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        let layout = content.frame(maxWidth: EmberStyle.measure).frame(maxWidth: .infinity)
            .background(grouped ? Color(uiColor: .systemGroupedBackground) : EmberStyle.canvas)
        if sizeClass == .regular { layout.navigationBarTitleDisplayMode(.inline) }
        else { layout }
    }
}
