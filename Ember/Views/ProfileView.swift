import SwiftUI

struct ProfileView: View {
    let username: String
    let service: any HNService
    @State private var user: HNUser?
    @State private var error: String?
    @State private var loading = false
    @State private var confirmBlock = false
    @Environment(AppContainer.self) private var app
    @Environment(ReadingStore.self) private var reading

    var body: some View {
        List {
            if loading { HStack { Spacer(); ProgressView(); Spacer() }.padding(30).listRowSeparator(.hidden) }
            if let error { InlineNotice(message: error) { Task { await load() } }.listRowSeparator(.hidden) }
            if let user {
                Section {
                    LabeledContent("Karma", value: user.karma.formatted())
                    LabeledContent("Joined", value: Date(timeIntervalSince1970: user.created).formatted(date: .abbreviated, time: .omitted))
                }
                if let about = user.about, !about.isEmpty { Section("About") { RichText(about).padding(.vertical, 8) } }
                Section {
                    Button("Profile on Hacker News", systemImage: "arrow.up.right.square") { app.open(HNLinks.user(username)) }
                }
                Section {
                    if reading.isBlocked(username) {
                        Button("Unblock user", systemImage: "person.crop.circle.badge.checkmark") { reading.unblock(username) }
                    } else {
                        Button("Block user", systemImage: "person.slash", role: .destructive) { confirmBlock = true }
                    }
                }
            }
        }
        .readingWidth().navigationTitle(username).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Block \(username)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block user", role: .destructive) { reading.block(username) }
        } message: { Text("Their stories and comments will be hidden on this device. You can undo this in Settings.") }
    }

    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do { let fetched = try await service.user(username); try Task.checkCancellation(); user = fetched }
        catch { if !Task.isCancelled { self.error = friendlyError(error) } }
    }
}
