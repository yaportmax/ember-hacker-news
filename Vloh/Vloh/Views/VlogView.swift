import SwiftUI
import AVKit

struct VlogView: View {
    let vlog: Vlog
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var error: String?
    @State private var loading = false
    @State private var text = ""
    @State private var sending = false
    @State private var deleting = false
    var replies: [Reply] { store.archive.replies.filter { $0.group == vlog.group && $0.vlogID == vlog.id }.sorted { $0.createdAt < $1.createdAt } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let url { FilePlayer(url: url).aspectRatio(9 / 16, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16)) }
                else if let error { Notice(text: error) { Task { await load() } } }
                else { ProgressView("Loading video…").frame(maxWidth: .infinity, minHeight: 300) }
                HStack { Avatar(name: vlog.authorName); VStack(alignment: .leading) { Text(vlog.authorName).font(.headline); Text(vlog.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } }
                if !vlog.caption.isEmpty { Text(vlog.caption).textSelection(.enabled) }
                HStack(spacing: 10) {
                    ForEach(["❤️", "😂", "🔥", "👏"], id: \.self) { emoji in
                        Button {
                            Task { await store.react(vlog, emoji: emoji) }
                        } label: {
                            let count = store.archive.reactions.filter { $0.group == vlog.group && $0.vlogID == vlog.id && $0.emoji == emoji }.count
                            Text(count > 0 ? "\(emoji) \(count)" : emoji).frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.bordered).accessibilityLabel("React \(emoji)")
                    }
                }
                Divider()
                Text("Replies").font(.headline)
                if replies.isEmpty { Text("Be the first to say something.").foregroundStyle(.secondary) }
                ForEach(replies) { reply in ReplyRow(reply: reply) }
            }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .navigationTitle("\(vlog.authorName)'s day").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Say something", text: $text, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button { sending = true; Task { if await store.send(text: text, vlog: vlog) { text = "" }; sending = false } } label: { Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44) }
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000).accessibilityLabel("Send reply")
            }.padding().background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let url { ShareLink(item: url) { Label("Export video", systemImage: "square.and.arrow.up") } }
                    if vlog.authorID == store.user { Button("Delete vlog", systemImage: "trash", role: .destructive) { deleting = true } }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Video actions")
            }
        }
        .confirmationDialog("Delete this vlog for everyone?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete vlog", role: .destructive) { Task { await store.delete(vlog); if store.error == nil { dismiss() } } }
        }
        .task { await load() }
        .refreshable { await store.refresh() }
    }
    private func load() async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do { url = try await store.file(for: vlog); store.archive.seen.insert(vlog.id); store.save() }
        catch { self.error = error.localizedDescription }
    }
}
struct ReplyRow: View {
    let reply: Reply
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: reply.authorName)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(reply.authorName).font(.subheadline.bold()); Text(reply.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary) }
                Text(reply.text).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6)
    }
}
struct ChatView: View {
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var sending = false
    private var replies: [Reply] { store.archive.replies.filter { $0.group == store.group?.id && $0.vlogID == nil }.sorted { $0.createdAt < $1.createdAt } }
    var body: some View {
        Group {
            if store.group == nil { ContentUnavailableView("Your group goes here", systemImage: "bubble.left.and.bubble.right", description: Text("Create or join a group from Today.")) }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if replies.isEmpty { ContentUnavailableView("Keep the conversation going", systemImage: "bubble.left", description: Text("Plans, inside jokes, whatever's on your mind.")) }
                            ForEach(replies) { ReplyRow(reply: $0).id($0.id) }
                        }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: replies.count) { _, _ in if let last = replies.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    .refreshable { await store.refresh() }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        TextField("Message your group", text: $text, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder).accessibilityIdentifier("chat-message")
                        Button { sending = true; Task { if await store.send(text: text) { text = "" }; sending = false } } label: { Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44) }
                            .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000).accessibilityLabel("Send message").accessibilityIdentifier("send-message")
                    }.padding().background(.bar)
                }
            }
        }.navigationTitle(store.group?.name ?? "Chat").navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)); await store.refresh() } catch { return }
            }
        }
    }
}
