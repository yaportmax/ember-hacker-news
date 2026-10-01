import SwiftUI

struct FeedView: View {
    let groupID: GroupID
    @Environment(AppStore.self) private var store
    @State private var create = false
    @State private var draft: DraftPresentation?
    @State private var inviting = false
    @State private var share: SharePresentation?
    @State private var search = ""
    @State private var filter = "All"
    private var group: VlohGroup? { store.archive.groups.first { $0.id == groupID } }
    var filtered: [Vlog] {
        store.visibleVlogs(in: groupID).filter { vlog in
            (filter != "Unwatched" || !store.archive.seen.contains(vlog.group.key + "/" + vlog.id)) &&
            (search.isEmpty || vlog.caption.localizedCaseInsensitiveContains(search) || vlog.authorName.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        List {
            if let group {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.name).font(.title2.bold())
                        if let member = Rotation.member(for: group, members: store.archive.members, date: .now) {
                            Label(member.id == store.user ? "Your day to vlog" : "\(member.name)'s day to vlog", systemImage: "sun.max")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else { Text("A little bit of everyone's day.").foregroundStyle(.secondary) }
                        Button {
                            Task { if let id = await store.recordingDraft(groupID: groupID), let value = store.archive.drafts.first(where: { $0.id == id }) { draft = DraftPresentation(id: id, draft: value) } }
                        } label: { Label("Record your day", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("record-day")
                        NavigationLink { ScheduleView(group: group) } label: { Label("See the vlog schedule", systemImage: "calendar") }.accessibilityIdentifier("group-schedule")
                    }.padding(.vertical, 8)
                }
                if let message = store.syncMessage { Section { Notice(text: message) { Task { await store.refresh() } } } }
                if !store.online { Section { Label("Offline. Your drafts are saved on this iPhone.", systemImage: "wifi.slash").font(.subheadline).foregroundStyle(.secondary) } }
                let pending = store.archive.drafts.filter { $0.group == group.id && $0.phase != .draft }
                if !pending.isEmpty {
                    Section("Uploads") {
                        ForEach(pending) { item in UploadRow(draft: item) }
                    }
                }
                Section {
                    Picker("Show", selection: $filter) { Text("All").tag("All"); Text("Unwatched").tag("Unwatched") }.pickerStyle(.segmented)
                    if filtered.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "The good stuff starts here" : "No matching vlogs", systemImage: "video", description: Text(search.isEmpty ? "Share your first vlog or invite your friends." : "Try another name or caption."))
                    }
                    ForEach(filtered) { vlog in
                        NavigationLink { VlogView(vlog: vlog) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Avatar(name: vlog.authorName)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(vlog.authorName).font(.headline)
                                        Text(vlog.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !store.archive.seen.contains(vlog.group.key + "/" + vlog.id) { Circle().fill(.orange).frame(width: 8, height: 8).accessibilityLabel("Unwatched") }
                                    Text(Duration.seconds(vlog.duration).formatted(.time(pattern: .minuteSecond))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Poster(vlog: vlog)
                                if !vlog.caption.isEmpty { Text(vlog.caption).font(.body).lineLimit(3) }
                            }.padding(.vertical, 12)
                        }.buttonStyle(.plain).accessibilityIdentifier("vlog-" + vlog.id)
                    }
                } header: { Text("The latest") }
            } else {
                Section {
                    ContentUnavailableView("Bring your people", systemImage: "person.2", description: Text("Create a private group, then send your buddies an invite. Have an invite? Open the link in Messages."))
                    Button("Create a group") { create = true }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent).accessibilityIdentifier("create-first-group")
                }
                if let message = store.syncMessage { Section { Notice(text: message) { Task { await store.refresh() } } } }
            }
        }
        .listStyle(.plain).frame(maxWidth: 700).frame(maxWidth: .infinity)
        .navigationTitle(group?.name ?? "Vloh").searchable(text: $search, prompt: "Find a friend or a memory")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { NavigationLink { ChatView(groupID: groupID) } label: { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.accessibilityIdentifier("group-chat") }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let group { NavigationLink("Manage group") { GroupSettingsView(groupID: group.id) }.accessibilityIdentifier("manage-group"); NavigationLink("Vlog schedule") { ScheduleView(group: group) } }
                    Button("Create group", systemImage: "plus") { create = true }
                    if let group, !group.id.shared {
                        Button("Invite friends", systemImage: "person.badge.plus") { invite(group) }.disabled(inviting)
                    }
                } label: { Image(systemName: inviting ? "hourglass" : "person.2").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Groups and invitations").accessibilityIdentifier("group-menu")
            }
        }
        .task(id: groupID) { await store.preloadRecentVideos(groupID: groupID) }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $create) { CreateGroupView() }
        .sheet(item: $draft) { DraftView(initial: $0.draft, startsRecording: true) }
        .sheet(item: $share) { value in CloudShareView(share: value.share, title: value.group.name, onError: { store.error = $0 }, onClose: { Task { await store.refresh() } }) }
    }
    private func invite(_ group: VlohGroup) {
        inviting = true
        Task {
            defer { inviting = false }
            do { share = SharePresentation(share: try await store.cloud.share(group), group: group) }
            catch { store.error = error.localizedDescription }
        }
    }
}
struct CreateGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rotation = true
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Your group") { TextField("Group name", text: $name).accessibilityIdentifier("group-name") }
                Section {
                    Label("One daily vlog, taking turns", systemImage: "calendar")
                } footer: { Text("Each day has one scheduled person. Post that day or the next day.") }
                Section { Button {
                    busy = true
                    Task { await store.createGroup(name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)), rotation: rotation); busy = false; if store.error == nil { dismiss() } }
                } label: { HStack { Text(busy ? "Creating…" : "Create group"); Spacer(); if busy { ProgressView() } } }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy).accessibilityIdentifier("create-group") }
            }.navigationTitle("New group").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
        }
    }
}
struct UploadRow: View {
    let draft: Draft
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if draft.phase == .preparing || draft.phase == .uploading { ProgressView() }
                Label(draft.phase.title, systemImage: draft.phase == .failed ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.up.circle")
                Spacer()
                if draft.phase == .failed { Button("Retry") { Task { await store.publish(draft.id) } }.frame(minHeight: 44) }
            }
            if let error = draft.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if draft.phase == .queued { Text("You can keep using Vloh. We'll upload when connected.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
