import SwiftUI

struct RootView: View {
    enum Tab: Hashable { case stories, search, saved, settings }
    @Environment(AppContainer.self) private var app
    @Environment(ReadingStore.self) private var reading
    @State private var selectedTab: Tab = .stories
    @State private var storyPath: [HNItem] = []
    @State private var searchPath: [HNItem] = []
    @State private var savedPath: [HNItem] = []
    @State private var deepLinkTask: Task<Void, Never>?
    @State private var openingLink = false
    @State private var pendingHNLink: URL?
    @State private var showingHNLinkOptions = false
    @AppStorage("readerMode") private var readerMode = true

    var body: some View {
        @Bindable var app = app
        TabView(selection: $selectedTab) {
            NavigationStack(path: $storyPath) {
                FeedView(service: app.service, cache: app.cache, openDiscussion: { navigate($0, tab: .stories) })
                    .navigationDestination(for: HNItem.self) { item in DiscussionView(story: item, service: app.service) }
            }.tabItem { Label("Stories", systemImage: "text.alignleft") }.tag(Tab.stories)
            NavigationStack(path: $searchPath) {
                SearchView(service: app.service, openDiscussion: { navigate($0, tab: .search) })
                    .navigationDestination(for: HNItem.self) { item in DiscussionView(story: item, service: app.service) }
            }.tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(Tab.search)
            NavigationStack(path: $savedPath) {
                SavedView(openDiscussion: { navigate($0, tab: .saved) })
                    .navigationDestination(for: HNItem.self) { item in DiscussionView(story: item, service: app.service) }
            }.tabItem { Label("Saved", systemImage: "bookmark") }.tag(Tab.saved)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(Tab.settings)
        }
        .sheet(item: $app.browser) { route in SafariView(url: route.url, reader: readerMode).ignoresSafeArea() }
        .environment(\.openURL, OpenURLAction { url in
            if HNLinks.itemID(from: url) != nil {
                pendingHNLink = url
                showingHNLinkOptions = true
            } else {
                app.open(url)
            }
            return .handled
        })
        .confirmationDialog("Open Hacker News discussion", isPresented: $showingHNLinkOptions, titleVisibility: .visible) {
            Button("Open in Ember") {
                guard let url = pendingHNLink else { return }
                pendingHNLink = nil
                openDeepLink(url, fromWithinApp: true)
            }
            Button("Open on Hacker News") {
                guard let url = pendingHNLink else { return }
                pendingHNLink = nil
                app.open(url)
            }
            Button("Cancel", role: .cancel) { pendingHNLink = nil }
        }
        .alert("Couldn’t open", isPresented: Binding(get: { app.error != nil }, set: { if !$0 { app.error = nil } })) {
            Button("OK", role: .cancel) { app.error = nil }
        } message: { Text(app.error ?? "") }
        .safeAreaInset(edge: .top, spacing: 0) {
            if openingLink {
                HStack { ProgressView(); Text("Opening discussion…").font(.subheadline); Spacer()
                    Button("Cancel") { deepLinkTask?.cancel(); openingLink = false }
                }.padding().background(.regularMaterial)
            }
            if let error = reading.error {
                HStack(alignment: .top) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.caption)
                        Button(reading.needsRecovery ? "Open Settings" : "Retry saving") {
                            if reading.needsRecovery { selectedTab = .settings } else { reading.retrySave() }
                        }.font(.caption.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                }.padding().background(EmberStyle.subtle)
            }
        }
        .onOpenURL { url in openDeepLink(url) }
    }

    private func navigate(_ item: HNItem, tab: Tab) {
        func push(_ item: HNItem) {
            switch tab {
            case .stories: storyPath.append(item)
            case .search: searchPath.append(item)
            case .saved: savedPath.append(item)
            case .settings: break
            }
        }
        guard item.type == "comment" else { push(item); return }
        deepLinkTask?.cancel(); openingLink = true
        deepLinkTask = Task {
            defer { if !Task.isCancelled { openingLink = false } }
            do {
                var root = item; var seen = Set<Int>()
                while root.type == "comment" {
                    guard seen.count < 100, seen.insert(root.id).inserted, let parent = root.parent,
                          let next = try await app.service.item(parent, fresh: false) else { throw AppError.missing }
                    root = next
                }
                try Task.checkCancellation()
                guard root.isStory else { throw AppError.missing }
                push(root)
            } catch { if !Task.isCancelled { app.error = friendlyError(error) } }
        }
    }

    private func openDeepLink(_ url: URL, fromWithinApp: Bool = false) {
        guard let id = HNLinks.itemID(from: url) else { app.error = "This isn’t a valid Hacker News item link."; return }
        deepLinkTask?.cancel()
        openingLink = true
        deepLinkTask = Task {
            defer { if !Task.isCancelled { openingLink = false } }
            do {
                guard var item = try await app.service.item(id, fresh: true) else { throw AppError.missing }
                var visited: Set<Int> = [id]
                // Comment links resolve to their enclosing discussion; cycles are rejected.
                while item.type == "comment", let parent = item.parent {
                    guard visited.count < 100, visited.insert(parent).inserted,
                          let next = try await app.service.item(parent, fresh: false) else { throw AppError.missing }
                    item = next
                }
                try Task.checkCancellation()
                guard item.isStory else { throw AppError.missing }
                if fromWithinApp, selectedTab != .settings {
                    navigate(item, tab: selectedTab)
                } else {
                    selectedTab = .stories
                    storyPath = [item]
                }
            } catch {
                if !Task.isCancelled { app.error = friendlyError(error) }
            }
        }
    }
}
