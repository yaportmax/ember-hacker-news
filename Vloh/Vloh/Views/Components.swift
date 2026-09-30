import SwiftUI
import AVKit
import CloudKit
import UIKit

struct Notice: View {
    let text: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.secondary)
            if let retry { Button("Try again", action: retry).frame(minHeight: 44) }
        }.padding(.vertical, 8)
    }
}
struct Avatar: View {
    let name: String
    var body: some View {
        Text(String(name.prefix(1)).uppercased()).font(.headline.weight(.semibold))
            .frame(width: 40, height: 40).background(.orange.opacity(0.13), in: Circle()).foregroundStyle(.orange)
            .accessibilityHidden(true)
    }
}
struct Poster: View {
    let vlog: Vlog
    @Environment(AppStore.self) private var store
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .secondarySystemBackground))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            Image(systemName: "play.circle.fill").font(.system(size: 46)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.35))
        }
        .frame(height: 240).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: vlog.id) {
            if let url = try? await store.file(for: vlog, poster: true) {
                let loaded = await Task.detached { UIImage(contentsOfFile: url.path) }.value
                image = loaded
            }
        }
        .accessibilityHidden(true)
    }
}
struct CloudShareView: UIViewControllerRepresentable {
    let share: CKShare
    let title: String
    var onError: (String) -> Void
    var onClose: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: "iCloud.com.maxyaport.vloh"))
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudShareView
        init(_ parent: CloudShareView) { self.parent = parent }
        func itemTitle(for csc: UICloudSharingController) -> String? { parent.title }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { parent.onError(error.localizedDescription) }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { parent.onClose() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { parent.onClose() }
    }
}
struct CameraView: UIViewControllerRepresentable {
    let onRecord: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.mediaTypes = ["public.movie"]
        picker.cameraCaptureMode = .video; picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 120
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL { parent.onRecord(url) }
            parent.dismiss()
        }
    }
}
struct FilePlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VideoPlayer(player: player).frame(minHeight: 240)
            .onAppear {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try? AVAudioSession.sharedInstance().setActive(true)
                player = AVPlayer(url: url)
            }
            .onDisappear { player?.pause(); player = nil }
            .onChange(of: phase) { _, value in if value != .active { player?.pause() } }
    }
}
struct SharePresentation: Identifiable { let id = UUID(); let share: CKShare; let group: VlohGroup }
struct DraftPresentation: Identifiable { var id: UUID; var draft: Draft }
