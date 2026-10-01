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
                    FeedView(groupID: group.id).onAppear { store.selectedGroup = group.id }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { GroupPicture(group: group, size: 48); Text(group.name).font(.title2.bold()); Spacer() }
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
    @State private var deleting: Draft?
    @State private var opening = false
    @State private var vlogDay: Date?
    var body: some View {
        NavigationStack {
            List {
                if let group = store.group {
                    Section {
                        Menu {
                            ForEach(store.archive.groups) { group in Button(group.name) { store.selectedGroup = group.id } }
                        } label: { Label("Recording for \(group.name)", systemImage: "person.2").font(.headline).frame(minHeight: 44) }.accessibilityIdentifier("record-group-picker")
                        let days = VlogCalendar.availableDays(for: store.user, group: group, members: store.archive.members, now: .now)
                        if days.isEmpty { NavigationLink { ScheduleView(group: group) } label: { Label("See your next vlog day", systemImage: "calendar") } }
                        if days.count > 1 {
                            Menu { ForEach(days, id: \.self) { day in Button(VlogCalendar.label(day, in: group)) { vlogDay = day } } } label: { Label("Vlog day: " + VlogCalendar.label(vlogDay ?? days.first!, in: group), systemImage: "calendar") }
                        }
                        Button { Task { await openCamera() } } label: { Label("Record your day", systemImage: "record.circle").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 60) }.buttonStyle(.borderedProminent).accessibilityIdentifier("record-day").disabled(opening || days.isEmpty)
                    }
                    Section("Your drafts in \(group.name)") {
                        ForEach(store.archive.drafts.filter { $0.group == group.id }.sorted { $0.createdAt > $1.createdAt }) { item in
                            if item.canEdit {
                                Button { draft = DraftPresentation(id: item.id, draft: item) } label: {
                                    HStack { Image(systemName: "film.stack"); VStack(alignment: .leading) { Text(item.caption.isEmpty ? "Your day" : item.caption).font(.headline); Text("\(item.clips.count) clips · \(Duration.seconds(item.totalDuration).formatted(.time(pattern: .minuteSecond)))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }
                                }.swipeActions { Button("Delete draft", role: .destructive) { deleting = item } }
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
            .confirmationDialog("Delete this draft and its clips?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("Delete draft", role: .destructive) { if let deleting { Task { await store.removeDraft(deleting) } }; deleting = nil } }
            .task { if let group = store.group, !VlogCalendar.availableDays(for: store.user, group: group, members: store.archive.members, now: .now).isEmpty { await openCamera() } }
        }
    }
    private func openCamera() async {
        guard store.group != nil, draft == nil else { return }
        opening = true
        if let id = await store.recordingDraft(day: vlogDay), let value = store.archive.drafts.first(where: { $0.id == id }) { draft = DraftPresentation(id: id, draft: value) }
        else { opening = false }
    }
}
