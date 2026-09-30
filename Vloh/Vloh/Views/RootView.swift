import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = 0
    @State private var onboarding = false
    var body: some View {
        @Bindable var store = store
        Group {
            if !store.ready { ProgressView("Opening Vloh") }
            else {
                TabView(selection: $tab) {
                    NavigationStack { FeedView() }.tabItem { Label("Today", systemImage: "play.rectangle") }.tag(0)
                    NavigationStack { DraftsView() }.tabItem { Label("Drafts", systemImage: "square.and.pencil") }.tag(1)
                    NavigationStack { ChatView() }.tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(2)
                    NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
                }
            }
        }
        .alert("Couldn't finish that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sheet(isPresented: $onboarding) { WelcomeView().interactiveDismissDisabled() }
        .onChange(of: store.ready) { _, ready in if ready && store.name.isEmpty { onboarding = true } }
    }
}
struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image(systemName: "video.fill").font(.system(size: 56)).foregroundStyle(.orange).accessibilityHidden(true)
                Text("Your people.\nYour everyday.").font(.largeTitle.bold())
                Text("Record a few clips, share your day, and keep up with your friends. Just your private group.").foregroundStyle(.secondary)
                TextField("Your first name", text: $name).textContentType(.givenName).textFieldStyle(.roundedBorder).accessibilityIdentifier("welcome-name")
                Button {
                    busy = true
                    Task { await store.saveName(name); busy = false; if store.error == nil { dismiss() } }
                } label: { Text(busy ? "Saving…" : "Let's go").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                .accessibilityIdentifier("welcome-continue")
                Text("Sharing uses your iCloud account. No separate password.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity).navigationTitle("Vloh").navigationBarTitleDisplayMode(.inline)
        }
    }
}
