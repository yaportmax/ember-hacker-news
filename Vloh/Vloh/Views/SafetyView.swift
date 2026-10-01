import SwiftUI
import MessageUI

enum PolicyKind { case privacy, community }
struct PolicyView: View {
    let kind: PolicyKind
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if kind == .privacy {
                    Text("Vloh privacy policy").font(.title.bold())
                    Text("Updated October 1, 2026. Vloh is provided by Max Yaport.")
                    Text("Your display name, optional profile photo, group membership, videos, captions, reactions, and messages are stored in Apple's CloudKit. Your Apple sign-in identifier is stored in your private profile. We do not collect your Apple password or store your email address from Sign in with Apple. Draft clips and editing information stay on your device until you post.")
                    Text("Your private group's invited members can view and export shared content. Camera and microphone access is requested only for recording. Photo import uses Apple's picker and only accesses items you select. We do not request contacts, location, advertising identifiers, or full photo-library access.")
                    Text("There are no advertising or analytics SDKs, tracking, or sale of data. Apple provides iCloud storage and may process service data under its own privacy policy. Data remains until you delete it or the owning group is deleted. Apple controls its backup retention.")
                    Text("Delete a vlog from its actions menu. Delete drafts from the draft list. Settings → Your account → Delete Vloh account and data removes your private profile, drafts, your contributions to joined groups, and all groups you own. Other people's exported copies cannot be recalled. Camera and microphone consent can be withdrawn in iOS Settings. Your Apple account is not deleted.")
                    Text("Content reports are sent only when you submit them using your mail app. Review the message and any attached evidence before sending. Reports may include the content identifier, explanation, and optional video you choose to attach. We use that information for support and safety and retain it only as needed to resolve the report.")
                    Link("Apple privacy policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                } else {
                    Text("Keep your group safe").font(.title.bold())
                    Text("Vloh is for private groups of people you know. Do not post sexual exploitation, pornography, threats, harassment, hateful content, graphic violence, or material you have no right to share. Get permission before filming or sharing another person.")
                    Text("Captions and messages are checked for known abusive phrases before posting. Private invitations restrict who can contribute. Group owners can remove content and revoke invitations. This is a trusted private space, not a public or anonymous feed.")
                    Text("Use a vlog's menu or a message's context menu to report content, hide it, or block its author. Blocking hides their vlogs and messages across your groups on this device. Group owners can remove members through Manage group → Manage invitations. Contact support for content concerns, including a description and evidence you choose to share.")
                    Text("Group owners are responsible for moderating their private groups. Reports to support must be reviewed and acted on promptly. Vloh is not an emergency service.")
                }
                Link("Contact support: yaportmax@gmail.com", destination: URL(string: "mailto:yaportmax@gmail.com")!)
            }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.navigationTitle(kind == .privacy ? "Privacy policy" : "Community rules").navigationBarTitleDisplayMode(.inline)
    }
}
struct ReportTarget: Identifiable { let id = UUID(); var contentID: String; var group: GroupID; var author: String; var text: String; var video: URL? = nil }
struct ReportView: View {
    let target: ReportTarget
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "Harassment or threats"
    @State private var details = ""
    @State private var attachVideo = false
    @State private var compose = false
    @State private var sent = false
    var body: some View {
        NavigationStack {
            Form {
                Section("What happened?") {
                    Picker("Reason", selection: $reason) { ForEach(["Harassment or threats", "Hateful content", "Sexual content", "Privacy or consent", "Other"], id: \.self) { Text($0) } }
                    TextField("Add details", text: $details, axis: .vertical).lineLimit(3...7)
                    if target.video != nil { Toggle("Attach this video as evidence", isOn: $attachVideo) }
                    Text("Your report opens in Mail for you to review and send. It is not submitted until you send that email.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if MFMailComposeViewController.canSendMail() { Button("Review report email") { compose = true }.accessibilityIdentifier("compose-report") }
                    else { Link("Send report through your mail app", destination: mailURL); Text("If no mail app is configured, contact yaportmax@gmail.com with the content ID below.").font(.caption).foregroundStyle(.secondary) }
                    Text("Content ID: " + target.contentID).font(.caption).textSelection(.enabled)
                    Button("Hide this content") { store.hide(target.contentID, group: target.group); dismiss() }
                    Button("Block this member") { if !store.isBlocked(target.author) { store.toggleBlock(target.author) }; dismiss() }
                }
            }.navigationTitle(sent ? "Report sent" : "Report content").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $compose) { ReportMail(body: bodyText, video: attachVideo ? target.video : nil) { didSend in compose = false; sent = didSend } }
        }
    }
    private var bodyText: String { "Vloh content report\nReason: \(reason)\nContent: \(target.contentID)\nGroup: \(target.group.key)\nAuthor: \(target.author)\n\n\(target.text)\n\n\(details)" }
    private var mailURL: URL { var parts = URLComponents(); parts.scheme = "mailto"; parts.path = "yaportmax@gmail.com"; parts.queryItems = [URLQueryItem(name: "subject", value: "Vloh content report"), URLQueryItem(name: "body", value: bodyText)]; return parts.url! }
}
struct ReportMail: UIViewControllerRepresentable {
    let body: String
    var video: URL?
    let onFinish: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController(); controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(["yaportmax@gmail.com"]); controller.setSubject("Vloh content report"); controller.setMessageBody(body, isHTML: false)
        if let video, let size = try? video.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 10 * 1024 * 1024, let data = try? Data(contentsOf: video) { controller.addAttachmentData(data, mimeType: "video/mp4", fileName: "reported-video.mp4") }
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { onFinish(result == .sent) }
    }
}
struct BlockedMembersView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        List { if store.blockedAuthors.isEmpty { ContentUnavailableView("No blocked members", systemImage: "person.crop.circle.badge.checkmark") }; ForEach(Array(store.blockedAuthors).sorted(), id: \.self) { id in HStack { Text(store.archive.members.first { $0.id == id }?.name ?? "Blocked member"); Spacer(); Button("Unblock") { store.toggleBlock(id) } } } }.navigationTitle("Blocked members")
    }
}
