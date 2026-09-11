import SwiftUI

struct SavedView: View {
    @Environment(ReadingStore.self) private var reading
    @State private var showHistory = false
    @State private var query = ""

    private var stories: [SavedStory] {
        let source = showHistory ? reading.history : reading.bookmarks
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
                EmptyState(title: query.isEmpty ? (showHistory ? "Your reading history" : "Keep the good ones") : "No matches",
                           symbol: showHistory ? "clock" : "bookmark",
                           detail: query.isEmpty ? (showHistory ? "Stories you open will appear here." : "Swipe left on a story or tap its bookmark to save it here.") : "Try a different title or website.")
                    .listRowSeparator(.hidden)
            }
            ForEach(stories) { saved in
                NavigationLink(value: saved.item) { StoryRow(item: saved.item) }.accessibilityIdentifier("story-\(saved.id)").storyActions(saved.item)
            }
        }
        .listStyle(.plain).readingWidth()
        .navigationTitle("Saved")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter saved stories")
    }
}
