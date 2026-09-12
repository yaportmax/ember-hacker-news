import SwiftUI

struct SavedView: View {
    @Environment(ReadingStore.self) private var reading
    @State private var showHistory = false
    @State private var query = ""

    private var source: [SavedStory] { showHistory ? reading.history : reading.bookmarks }
    private var stories: [SavedStory] {
        return source.filter {
            !reading.isHidden($0.item) && (query.isEmpty || $0.item.displayTitle.localizedCaseInsensitiveContains(query) || ($0.item.domain ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List {
            Picker("Collection", selection: $showHistory) {
                Text("Bookmarks").tag(false)
                Text("History").tag(true)
            }.pickerStyle(.segmented).listRowSeparator(.hidden).padding(.vertical, 8)
            if stories.isEmpty {
                EmptyState(title: query.isEmpty ? (source.isEmpty ? (showHistory ? "No reading history" : "No saved stories") : "Stories are hidden") : "No matches",
                           symbol: showHistory ? "clock" : "bookmark",
                           detail: query.isEmpty ? (source.isEmpty ? (showHistory ? "Stories you open will appear here." : "Tap a story’s bookmark to keep it here.") : "Review Hidden content in Settings to show your stories.") : "Try a different title or website.")
                    .listRowSeparator(.hidden)
            }
            ForEach(stories) { saved in
                NavigationLink(value: saved.item) { StoryRow(item: saved.item) }.accessibilityIdentifier("story-\(saved.id)").storyActions(saved.item)
            }
        }
        .listStyle(.plain).readingWidth()
        .navigationTitle("Saved")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: showHistory ? "Search reading history" : "Search saved stories")
    }
}
