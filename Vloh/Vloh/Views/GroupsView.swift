import SwiftUI

struct GroupsView: View {
    @Environment(AppStore.self) private var store
    @State private var create = false
    var body: some View {
        List {
            if store.archive.groups.isEmpty {
                ContentUnavailableView("Bring your people", systemImage: "person.2.fill", description: Text("Create a group or open a friend's invitation link. Each group has its own vlogs and chat."))
                Button("Create a group") { create = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("create-first-group")
            }
            ForEach(store.archive.groups) { group in
                NavigationLink {
                    FeedView().onAppear { store.selectedGroup = group.id }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Image(systemName: "person.2.fill").font(.title2).foregroundStyle(.orange); Text(group.name).font(.title2.bold()); Spacer() }
                        let vlogs = store.visibleVlogs(in: group.id)
                        Text("\(store.archive.members.filter { $0.group == group.id }.count) members · \(vlogs.count) vlogs").font(.subheadline).foregroundStyle(.secondary)
                        if let latest = vlogs.first { Text("\(latest.authorName) shared \(latest.createdAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                        else { Text("Share a little bit of your day").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 14)
                }.accessibilityIdentifier("group-" + group.id.zone)
            }
            if let message = store.syncMessage { Notice(text: message) { Task { await store.refresh() } } }
        }.navigationTitle("Your groups")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("New group", systemImage: "plus") { create = true } } }
        .sheet(isPresented: $create) { CreateGroupView() }
        .refreshable { await store.refresh() }
    }
}
struct RecordHubView: View {
    @Environment(AppStore.self) private var store
    @State private var draft: DraftPresentation?
    @State private var create = false
    @State private var opening = false
    var body: some View {
        NavigationStack {
            List {
                if let group = store.group {
                    Section {
                        Menu {
                            ForEach(store.archive.groups) { group in Button(group.name) { store.selectedGroup = group.id } }
                        } label: { Label("Recording for \(group.name)", systemImage: "person.2").font(.headline).frame(minHeight: 44) }.accessibilityIdentifier("record-group-picker")
                        Button { Task { await openCamera() } } label: { Label("Record your day", systemImage: "record.circle").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 60) }.buttonStyle(.borderedProminent).accessibilityIdentifier("record-day").disabled(opening)
                    }
                    Section("Your drafts in \(group.name)") {
                        ForEach(store.archive.drafts.filter { $0.group == group.id }.sorted { $0.createdAt > $1.createdAt }) { item in
                            if item.canEdit {
                                Button { draft = DraftPresentation(id: item.id, draft: item) } label: {
                                    HStack { Image(systemName: "film.stack"); VStack(alignment: .leading) { Text(item.caption.isEmpty ? "Your day" : item.caption).font(.headline); Text("\(item.clips.count) clips · \(Duration.seconds(item.totalDuration).formatted(.time(pattern: .minuteSecond)))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }
                                }
                            } else { UploadRow(draft: item) }
                        }
                    }
                } else {
                    ContentUnavailableView("Choose your people first", systemImage: "person.2", description: Text("Create a group, or join through an invitation. Then you're one tap from recording."))
                    Button("Create a group") { create = true }.buttonStyle(.borderedProminent)
                }
            }.navigationTitle("Record")
            .sheet(isPresented: $create) { CreateGroupView() }
            .sheet(item: $draft) { item in DraftView(initial: item.draft, startsRecording: opening).onDisappear { opening = false } }
            .task { await openCamera() }
        }
    }
    private func openCamera() async {
        guard store.group != nil, draft == nil else { return }
        opening = true
        if let id = await store.recordingDraft(), let value = store.archive.drafts.first(where: { $0.id == id }) { draft = DraftPresentation(id: id, draft: value) }
        else { opening = false }
    }
}
