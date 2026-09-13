import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("compactRows") private var compact = false
    @Environment(AppContainer.self) private var app

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Toggle("Compact stories", isOn: $compact)
                NavigationLink("Text & spacing") { TypographySettingsView() }
            }
            Section("Reading") {
                NavigationLink("Reading preferences") { ReadingPreferencesView() }
                NavigationLink("Hidden content") { HiddenContentView() }
                NavigationLink("Storage") { StorageView() }
            }
            Section {
                Button("Sign in on Hacker News", systemImage: "arrow.up.right") { app.open(HNLinks.login) }
                Button("Submit a story", systemImage: "arrow.up.right") { app.open(HNLinks.submit) }
            } header: { Text("Hacker News") } footer: { Text("Opens the Hacker News website.") }
            Section {
                NavigationLink("Help & support") { SupportView() }
                NavigationLink("Privacy") { PrivacyView() }
                NavigationLink("Acknowledgments") { AcknowledgmentsView() }
                LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
            } header: { Text("About") } footer: { Text("An independent reader for Hacker News.") }
        }
        .readingWidth(grouped: true).navigationTitle("Settings")
    }
}

private struct TypographySettingsView: View {
    @AppStorage("storyTextSize") private var storySize = 17.0
    @AppStorage("storyFont") private var storyFont = ReadingFont.system
    @AppStorage("storyLineSpacing") private var storyLines = 2.0
    @AppStorage("storyRowSpacing") private var storyRows = 12.0
    @AppStorage("boldStoryTitles") private var bold = true
    @AppStorage("compactRows") private var compact = false
    @AppStorage("commentTextSize") private var commentSize = 17.0
    @AppStorage("commentFont") private var commentFont = ReadingFont.system
    @AppStorage("commentLineSpacing") private var commentLines = 5.0
    @AppStorage("commentRowSpacing") private var commentRows = 7.0
    @AppStorage("replyIndent") private var replyIndent = 12.0

    var body: some View {
        Form {
            Section("Preview") {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                        Text("The best part of the web is the people who make it")
                            .modifier(StoryTypography())
                        if !compact { Text("example.com").font(.caption).foregroundStyle(EmberStyle.secondaryText) }
                        Text("128 points · 42 comments · 2h").font(.caption).foregroundStyle(EmberStyle.secondaryText)
                    }.padding(.vertical, compact ? max(0, storyRows - 4) : storyRows)
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("alex · 1h").font(.subheadline).foregroundStyle(EmberStyle.secondaryText)
                        RichText("Small details make reading feel effortless. <b>Good typography</b> gives every idea room to breathe.")
                        RichText("And replies stay easy to follow.").padding(.leading, replyIndent)
                    }.padding(.vertical, commentRows)
                }
            }
            Section("Stories") {
                fontPicker("Font", selection: $storyFont)
                adjustment("Text size", value: $storySize, range: 13...28)
                Toggle("Bold titles", isOn: $bold)
                adjustment("Line spacing", value: $storyLines, range: 0...14)
                adjustment("Row spacing", value: $storyRows, range: 0...28)
                Toggle("Compact stories", isOn: $compact)
            }
            Section("Comments & post text") {
                fontPicker("Font", selection: $commentFont)
                adjustment("Text size", value: $commentSize, range: 13...28)
                adjustment("Line spacing", value: $commentLines, range: 0...16)
                adjustment("Row spacing", value: $commentRows, range: 0...24)
                adjustment("Reply indentation", value: $replyIndent, range: 0...20)
            }
            Section {
                Button("Reset text & spacing") {
                    storySize = 17; storyFont = .system; storyLines = 2; storyRows = 12
                    bold = true; compact = false
                    commentSize = 17; commentFont = .system; commentLines = 5; commentRows = 7; replyIndent = 12
                }
            } footer: {
                Text("Changes apply immediately and are saved on this device. Text also scales with your iOS text size. Website articles use the browser’s reading settings.")
            }
        }.readingWidth(grouped: true).navigationTitle("Text & spacing").navigationBarTitleDisplayMode(.inline)
    }

    private func fontPicker(_ title: String, selection: Binding<ReadingFont>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ReadingFont.allCases) { font in
                Text(font.title).font(.system(.body, design: font.design)).tag(font)
            }
        }
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) pt").foregroundStyle(EmberStyle.secondaryText).monospacedDigit() }
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue)) points")
        }
    }
}

private struct ReadingPreferencesView: View {
    @AppStorage("dimReadStories") private var dimRead = true
    @AppStorage("hideReadStories") private var hideRead = false
    @AppStorage("readerMode") private var readerMode = true
    @AppStorage("externalBrowser") private var externalBrowser = false

    var body: some View {
        Form {
            Section {
                Toggle("Dim read stories", isOn: $dimRead)
                Toggle("Hide read stories", isOn: $hideRead)
            } header: { Text("Stories") } footer: { Text("Customize fonts, sizes, and spacing in Text & spacing.") }
            Section {
                Toggle("Open in default browser", isOn: $externalBrowser)
                if !externalBrowser { Toggle("Use Reader when available", isOn: $readerMode) }
            } header: { Text("Articles") } footer: { Text(externalBrowser ? "Articles open in the browser you chose in iOS Settings." : "Reader simplifies supported articles in the in-app browser.") }
        }.readingWidth(grouped: true).navigationTitle("Reading preferences").navigationBarTitleDisplayMode(.inline)
    }
}

private struct HiddenContentView: View {
    @Environment(ReadingStore.self) private var reading
    var body: some View {
        List {
            Section {
                NavigationLink("Blocked users (\(reading.blockedUsers.count))") { BlockedUsersView() }
                Button("Restore hidden stories (\(reading.archive.hiddenStories.count))") { reading.restoreHidden() }
                    .disabled(reading.archive.hiddenStories.isEmpty)
            } footer: { Text("Hide a story from its menu, or block an author from their profile. These choices apply only on this device.") }
        }.readingWidth(grouped: true).navigationTitle("Hidden content").navigationBarTitleDisplayMode(.inline)
    }
}

private struct StorageView: View {
    @Environment(AppContainer.self) private var app
    @Environment(ReadingStore.self) private var reading
    @State private var confirmation: ClearAction?
    @State private var cacheMessage: String?
    enum ClearAction: String, Identifiable {
        case history = "Clear reading history", bookmarks = "Remove all bookmarks", recover = "Recover saved data"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section {
                Button("Clear reading history", role: .destructive) { confirmation = .history }.disabled(reading.history.isEmpty)
                Button("Remove all bookmarks", role: .destructive) { confirmation = .bookmarks }.disabled(reading.bookmarks.isEmpty)
            } footer: { Text("Bookmarks and history stay on this device and may be included in your device backup.") }
            Section {
                Button("Clear offline feed cache") {
                    Task {
                        do { try await app.cache.clear(); cacheMessage = "Offline feed cache cleared." }
                        catch { cacheMessage = friendlyError(error) }
                    }
                }
                if let cacheMessage { Text(cacheMessage).font(.subheadline).foregroundStyle(EmberStyle.secondaryText) }
            } footer: { Text("Clearing cached feeds keeps your bookmarks and history.") }
            if reading.needsRecovery {
                Section { Button("Recover saved data") { confirmation = .recover } }
            }
        }.readingWidth(grouped: true).navigationTitle("Storage").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(confirmation?.rawValue ?? "", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            Button(confirmation?.rawValue ?? "Confirm", role: .destructive) {
                switch confirmation {
                case .history: reading.clearHistory()
                case .bookmarks: reading.clearBookmarks()
                case .recover: reading.recover()
                case nil: break
                }
                confirmation = nil
            }
            .accessibilityIdentifier("confirm-clear-data")
        } message: {
            Text(confirmation == .recover ? "Ember will keep a copy of the unreadable file and start a new local collection." : "This removes the selected data from this device and can’t be undone.")
        }
    }
}

private struct BlockedUsersView: View {
    @Environment(ReadingStore.self) private var reading
    var body: some View {
        List {
            if reading.blockedUsers.isEmpty { EmptyState(title: "No blocked users", symbol: "person.crop.circle.badge.checkmark", detail: "Block someone from their profile or a comment’s menu.") }
            ForEach(reading.blockedUsers, id: \.self) { name in
                HStack { Text(name); Spacer(); Button("Unblock") { reading.unblock(name) }.buttonStyle(.borderless) }
            }
        }.readingWidth(grouped: true).navigationTitle("Blocked users").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Your data") {
                Text("Ember has no advertising SDKs, analytics, tracking, or developer-operated server. The app does not ask for your contacts, location, photos, or Hacker News password.")
            }
            Section("Stored on this device") {
                Text("Bookmarks, reading history, blocked users, hidden stories, and preferences are stored locally. Recent feeds are cached for offline reading. Your device’s backup settings may include local app data. You can remove bookmarks, history, and cached feeds in Settings.")
            }
            Section("Network requests") {
                Text("Stories, comments, and profiles are requested from the public Hacker News API hosted by Firebase. Searches send your search text to Algolia’s Hacker News search service. These services receive ordinary connection information, including your IP address, under their own privacy policies.")
            }
            Section("Articles and accounts") {
                Text("Opening an article contacts that website through Apple’s browser. Websites may use cookies and collect information under their own policies. Sign-in, votes, replies, and submissions happen on Hacker News. Ember does not read your password or browser cookies.")
            }
            Section("Policies") {
                Link("Y Combinator privacy policy", destination: URL(string: "https://www.ycombinator.com/legal#privacy")!)
                Link("Google privacy policy", destination: URL(string: "https://policies.google.com/privacy")!)
                Link("Algolia privacy policy", destination: URL(string: "https://www.algolia.com/policies/privacy/")!)
            }
        }.readingWidth(grouped: true).navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportView: View {
    var body: some View {
        List {
            Section("Reading") { Text("Tap a story title to open the article. Tap the comment count beneath it to open the discussion. Swipe right on a story to read it directly.") }
            Section("Saving") { Text("Swipe left on a story, or tap the bookmark in a discussion. Saved stories appear in the Saved tab. Bookmarks preserve the story details and any loaded post text; external articles are not downloaded for offline use.") }
            Section("Comments") { Text("Tap a comment to collapse or expand its thread. Use the floating down arrow on long comments to jump to the next comment or reply. Replies load automatically as you scroll, in Hacker News order. Long-press a comment to reply on HN, share, report, or block its author.") }
            Section("Accounts") { Text("Sign in from Settings to vote, reply, or submit on the Hacker News website. Ember bookmarks are separate from your HN favorites.") }
            Section("Troubleshooting") { Text("Pull down to refresh. If you’re offline, previously loaded feeds and saved story details remain available. Check your connection if new comments or search results cannot load.") }
            if let support = Bundle.main.object(forInfoDictionaryKey: "EmberSupportURL") as? String,
               let url = WebURL.validated(support), !support.contains("$(") {
                Section("Contact") { Link("Contact Ember support", destination: url) }
            }
        }.readingWidth(grouped: true).navigationTitle("Help & support").navigationBarTitleDisplayMode(.inline)
    }
}

struct ReportView: View {
    let item: HNItem
    @Environment(AppContainer.self) private var app
    @Environment(ReadingStore.self) private var reading
    @State private var didBlock = false
    var body: some View {
        List {
            Section {
                Text("Hacker News moderates the stories and comments shown in Ember. Open the original item and use HN’s flag action when available, or its contact link to report abuse. Your HN account may be required.")
                Button("Open item on Hacker News", systemImage: "flag") { app.open(item.discussionURL) }
                Button("Hacker News guidelines") { app.open(URL(string: "https://news.ycombinator.com/newsguidelines.html")!) }
            }
            if let by = item.by {
                Section {
                    Button(didBlock || reading.isBlocked(by) ? "User blocked" : "Block \(by) on this device", systemImage: "person.slash") {
                        reading.block(by); didBlock = true
                    }.disabled(didBlock || reading.isBlocked(by))
                } footer: { Text("Blocking hides their stories and comments in Ember. You can undo it in Settings.") }
            }
            if let support = Bundle.main.object(forInfoDictionaryKey: "EmberSupportURL") as? String,
               let url = WebURL.validated(support), !support.contains("$(") {
                Section { Link("Report to Ember support", destination: url) }
            }
        }.readingWidth(grouped: true).navigationTitle("Report content").navigationBarTitleDisplayMode(.inline)
    }
}

struct AcknowledgmentsView: View {
    var body: some View {
        List {
            Section("Hacker News") {
                Text("Stories, discussions, and user profiles are provided by the Hacker News community through the public API.")
                Link("Hacker News API", destination: URL(string: "https://github.com/HackerNews/API")!)
            }
            Section("Algolia") {
                Text("Full-text search is provided by Algolia’s Hacker News search service.")
                Link("HN Search", destination: URL(string: "https://hn.algolia.com")!)
            }
            Section("Built with Swift") { Text("Ember uses Apple’s native frameworks and has no third-party runtime dependencies.") }
        }.readingWidth(grouped: true).navigationTitle("Acknowledgments").navigationBarTitleDisplayMode(.inline)
    }
}
