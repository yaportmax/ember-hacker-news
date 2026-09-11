import SwiftUI
import UIKit

struct BrowserRoute: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor @Observable
final class AppContainer {
    let service: any HNService
    let reading: ReadingStore
    let cache: FeedCache
    var browser: BrowserRoute?
    var error: String?

    init() {
        let manager = FileManager.default
        let support = (manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory)
            .appendingPathComponent("Ember", isDirectory: true)
        let cachePath = (manager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory)
            .appendingPathComponent("Ember", isDirectory: true)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let testing = manager.temporaryDirectory.appendingPathComponent("EmberUITests", isDirectory: true)
            if !ProcessInfo.processInfo.arguments.contains("--preserve-state") { try? manager.removeItem(at: testing) }
            service = FixtureService()
            reading = ReadingStore(directory: testing)
            cache = FeedCache(directory: testing.appendingPathComponent("Cache"))
            return
        }
        #endif
        service = HNClient()
        reading = ReadingStore(directory: support)
        cache = FeedCache(directory: cachePath)
    }

    func open(_ url: URL, forceExternal: Bool = false) {
        guard let safeURL = WebURL.validated(url.absoluteString) else { error = AppError.invalidLink.localizedDescription; return }
        if forceExternal || UserDefaults.standard.bool(forKey: "externalBrowser") {
            UIApplication.shared.open(safeURL) { [weak self] success in
                if !success { Task { @MainActor in self?.error = "This link couldn’t be opened. Please try again." } }
            }
        } else { browser = BrowserRoute(url: safeURL) }
    }
}
