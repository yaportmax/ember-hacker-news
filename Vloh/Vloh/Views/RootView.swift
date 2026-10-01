import SwiftUI
import AuthenticationServices

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearance = "system"
    @State private var tab = 0
    @State private var onboarding = false
    var body: some View {
        @Bindable var store = store
        Group {
            if !store.ready { ProgressView("Opening Vloh") }
            else if store.name.isEmpty || store.signedOut { WelcomeView() }
            else {
                TabView(selection: $tab) {
                    NavigationStack { GroupsView() }.tabItem { Label("Groups", systemImage: "person.2.fill") }.tag(0)
                    RecordHubView().tabItem { Label("Record", systemImage: "record.circle") }.tag(1)
                    NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
                }
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .alert("Couldn't finish that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert("Your Vloh account was deleted", isPresented: Binding(get: { store.accountDeleted }, set: { store.accountDeleted = $0 })) {
            Button("Apple authorization instructions") { openURL(URL(string: "https://support.apple.com/102571")!) }
            Button("Done", role: .cancel) { }
        } message: { Text("Your Vloh data has been removed. To remove Apple's authorization too, open iOS Settings → your name → Sign in with Apple → Vloh and stop using Sign in with Apple.") }

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
                SignInWithAppleButton(.signUp, onRequest: { request in request.requestedScopes = [.fullName] }, onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                        let appleName = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
                        busy = true
                        Task { await store.connectApple(user: credential.user, displayName: name.isEmpty ? appleName : name); busy = false }
                    case .failure(let error): if (error as? ASAuthorizationError)?.code != .canceled { store.error = error.localizedDescription }
                    }
                }).frame(height: 50).disabled(busy).accessibilityIdentifier("welcome-continue")
                HStack { NavigationLink("Privacy policy") { PolicyView(kind: .privacy) }; Spacer(); NavigationLink("Community rules") { PolicyView(kind: .community) } }.font(.caption)
                Text("By creating your account, you agree to follow the community rules. Only share footage you have permission to share.").font(.caption).foregroundStyle(.secondary)
                Text("Sharing uses your iCloud account. No separate password.").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity).navigationTitle("Vloh").navigationBarTitleDisplayMode(.inline)
        }
    }
}
