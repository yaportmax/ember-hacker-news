import SwiftUI
import PhotosUI

struct GroupSettingsView: View {
    let groupID: GroupID
    @Environment(AppStore.self) private var store
    @State private var photo: PhotosPickerItem?
    @State private var name = ""
    @State private var order: [Member] = []
    @State private var photoURL: URL?
    @State private var share: SharePresentation?
    @State private var busy = false
    @State private var error: String?
    @State private var leave = false
    private var group: VlohGroup? { store.archive.groups.first { $0.id == groupID } }
    var body: some View {
        Form {
            if let group {
                Section {
                    HStack {
                        ProfileImage(name: group.name, url: photoURL, size: 72).id(store.photoRevision)
                        if !group.id.shared { PhotosPicker(selection: $photo, matching: .images) { Text("Change group photo") }.disabled(busy) }
                        else { Text(group.name).font(.headline) }
                    }
                    if !group.id.shared {
                        TextField("Group name", text: $name)
                        Button("Save group name") { busy = true; Task { do { try await store.cloud.updateGroup(group, name: name, order: nil, photo: nil); await store.refresh() } catch { self.error = error.localizedDescription }; busy = false } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == group.name)
                    }
                }
                Section {
                    Button { busy = true; Task { do { share = SharePresentation(share: try await store.cloud.share(group), group: group) } catch { self.error = error.localizedDescription }; busy = false } } label: { Label("Invite with a link", systemImage: "link") }.disabled(busy || group.id.shared)
                    Text("Invitations are private. Choose Copy Link in Apple's invite sheet, then send it to your friends.").font(.caption).foregroundStyle(.secondary)
                    NavigationLink { ScheduleView(group: group) } label: { Label("Vlog schedule", systemImage: "calendar") }
                }
                Section("Vlogger order") {
                    ForEach(order) { member in
                        HStack { Text("\((order.firstIndex(where: { $0.id == member.id }) ?? 0) + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary); Avatar(name: member.name); Text(member.name); if member.id == store.user { Text("You").foregroundStyle(.secondary) } }
                    }.onMove { if !group.id.shared { order.move(fromOffsets: $0, toOffset: $1) } }
                    if !group.id.shared {
                        Button("Save vlogger order") { busy = true; Task { do { try await store.cloud.updateGroup(group, name: nil, order: order.map(\.id), photo: nil); await store.refresh() } catch { self.error = error.localizedDescription }; busy = false } }.disabled(busy)
                        Text("New order starts tomorrow. Today and yesterday keep their existing schedule.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Members") {
                    ForEach(store.archive.members.filter { $0.group == groupID }) { member in
                        GroupMemberRow(member: member)
                    }
                    if !group.id.shared { Button("Manage invitations and remove members") { busy = true; Task { do { share = SharePresentation(share: try await store.cloud.share(group), group: group) } catch { self.error = error.localizedDescription }; busy = false } }.disabled(busy) }
                }
                Section {
                    Button(group.id.shared ? "Leave group" : "Delete group", role: .destructive) { leave = true }.disabled(busy)
                }
                if let error { Section { Notice(text: error) } }
            }
        }.navigationTitle("Manage group").navigationBarTitleDisplayMode(.inline)
        .toolbar { if group?.id.shared == false { EditButton() } }
        .sheet(item: $share) { value in CloudShareView(share: value.share, title: value.group.name, onError: { error = $0 }, onClose: { Task { await store.refresh() } }) }
        .confirmationDialog(groupID.shared ? "Leave this group? Your posted vlogs remain." : "Delete this group and all its vlogs for everyone?", isPresented: $leave, titleVisibility: .visible) {
            Button(groupID.shared ? "Leave group" : "Delete group", role: .destructive) { Task { await store.leaveGroup(groupID) } }
        }
        .task {
            guard let group else { return }; name = group.name
            let members = store.archive.members.filter { $0.group == groupID }.sorted { $0.joinedAt < $1.joinedAt }
            let latest = group.orders?.max(by: { $0.effectiveDay < $1.effectiveDay })?.members ?? members.map(\.id)
            order = latest.compactMap { id in members.first { $0.id == id } } + members.filter { !latest.contains($0.id) }
            if !store.usesPreviewData { photoURL = try? await store.cloud.groupPhoto(groupID, destination: store.groupPhotoURL(groupID)) }
        }
        .onChange(of: photo) { _, item in
            guard let item, let group else { return }; busy = true
            Task { do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw VlohError.message("Couldn't open that photo.") }
                let url = store.groupPhotoURL(groupID); try await PhotoService.save(data, to: url)
                try await store.cloud.updateGroup(group, name: nil, order: nil, photo: url)
                photoURL = url; store.photoRevision = UUID()
            } catch { self.error = error.localizedDescription }; busy = false; photo = nil }
        }
    }
}
struct ProfileImage: View {
    let name: String
    var url: URL?
    var size: CGFloat = 64
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.orange).frame(maxWidth: .infinity, maxHeight: .infinity).background(.orange.opacity(0.13)) } }
            .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
            .task(id: url) { image = url.flatMap { UIImage(contentsOfFile: $0.path) } }
    }
}

struct GroupMemberRow: View {
    let member: Member
    @Environment(AppStore.self) private var store
    var body: some View {
        HStack {
            MemberPicture(member: member)
            NavigationLink { MemberVlogsView(member: member) } label: { Text(member.name) }
            if member.id != store.user { Button(store.isBlocked(member.id) ? "Unblock" : "Block") { store.toggleBlock(member.id) }.font(.caption).buttonStyle(.borderless) }
        }
    }
}
