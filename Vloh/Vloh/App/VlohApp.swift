import SwiftUI
import CloudKit
import AuthenticationServices

extension Notification.Name { static let acceptedShare = Notification.Name("Vloh.acceptedShare") }
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }
}
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { post(metadata) }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) { post(cloudKitShareMetadata) }
    private func post(_ metadata: CKShare.Metadata) {
        Task { @MainActor in ShareInbox.pending = metadata; NotificationCenter.default.post(name: .acceptedShare, object: nil) }
    }
}
@MainActor enum ShareInbox { static var pending: CKShare.Metadata? }
@main
struct VlohApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(.orange)
                .task { await store.boot(); await consumeShare() }
                .onReceive(NotificationCenter.default.publisher(for: .acceptedShare)) { _ in Task { await consumeShare() } }
                .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in store.signOut() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refresh(); store.startQueue() } }
                }
        }
    }
    private func consumeShare() async {
        guard store.ready, let metadata = ShareInbox.pending else { return }
        ShareInbox.pending = nil
        await store.accept(metadata)
    }
}
