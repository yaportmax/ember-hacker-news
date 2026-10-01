import SwiftUI

struct MemberVlogsView: View {
    let member: Member
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            HStack { MemberPicture(member: member, size: 64); VStack(alignment: .leading) { Text(member.name).font(.title2.bold()); Text("Past vlogs in this group").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical)
            let vlogs = store.visibleVlogs(in: member.group).filter { $0.authorID == member.id }
            if vlogs.isEmpty { ContentUnavailableView("No vlogs yet", systemImage: "video") }
            ForEach(vlogs) { vlog in NavigationLink { VlogView(vlog: vlog) } label: { VStack(alignment: .leading, spacing: 12) { Poster(vlog: vlog); Text(vlog.vlogDay ?? vlog.createdAt, style: .date).font(.headline); if !vlog.caption.isEmpty { Text(vlog.caption) } }.padding(.vertical, 8) } }
        }.navigationTitle(member.name).navigationBarTitleDisplayMode(.inline)
    }
}
struct GroupPicture: View {
    let group: VlohGroup
    var size: CGFloat = 48
    @Environment(AppStore.self) private var store
    @State private var url: URL?
    var body: some View { ProfileImage(name: group.name, url: url, size: size).id(store.photoRevision).task(id: group.id) { let cached = store.groupPhotoURL(group.id); if FileManager.default.fileExists(atPath: cached.path) { url = cached }; if let fresh = try? await store.cloud.groupPhoto(group.id, destination: cached) { url = nil; url = fresh } } }
}
struct MemberPicture: View {
    let member: Member
    var size: CGFloat = 40
    @Environment(AppStore.self) private var store
    @State private var url: URL?
    var body: some View {
        ProfileImage(name: member.name, url: member.id == store.user ? store.profilePhotoURL : url, size: size).id(member.id == store.user ? store.photoRevision.uuidString : member.id)
            .task(id: member.id) {
                guard member.id != store.user else { return }
                let key = Data((member.group.key + "/" + member.id).utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
                let file = store.root.appendingPathComponent("MemberPhotos/" + key + ".jpg")
                if FileManager.default.fileExists(atPath: file.path) { url = file }
                if let fresh = try? await store.cloud.memberPhoto(member.id, group: member.group, destination: file) { url = nil; url = fresh }
            }
    }
}
