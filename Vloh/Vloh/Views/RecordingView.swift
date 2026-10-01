import SwiftUI
import AVFoundation
import UIKit
import Combine

@MainActor @Observable
final class Recorder {
    let engine = CameraEngine()
    private var fixture = false
    private var fixtureClip: (@MainActor (URL) async throws -> Void)?
    var ready = false
    var recording = false
    var finishing = false
    var saving = 0
    var startedAt: Date?
    var error: String?
    var permissionDenied = false
    var closeRequested = false
    func prepare(onClip: @escaping @MainActor (URL) async throws -> Void) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { fixture = true; fixtureClip = onClip; ready = true; return }
        #endif
        let camera = await AVCaptureDevice.requestAccess(for: .video)
        guard camera else { permissionDenied = true; return }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard mic else { permissionDenied = true; return }
        engine.prepare(onReady: { [weak self] message in Task { @MainActor in self?.error = message; self?.ready = message == nil } }, onClip: { [weak self] url, message in
            Task { @MainActor in
                guard let self else { return }
                self.recording = false; self.finishing = false; self.startedAt = nil
                if let message { self.error = message; return }
                self.saving += 1
                do { try await onClip(url) } catch { self.error = error.localizedDescription }
                self.saving -= 1
            }
        })
    }
    func toggle(folder: URL, draftID: UUID, remaining: Double) {
        guard ready, !finishing else { return }
        #if DEBUG
        if fixture {
            if recording {
                recording = false; startedAt = nil; saving += 1
                Task {
                    do {
                        guard let source = Bundle.main.url(forResource: "Preview", withExtension: "mp4") else { throw VlohError.message("Missing video fixture") }
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let file = folder.appendingPathComponent(draftID.uuidString + "-" + UUID().uuidString + "-" + String(Int(Date.now.timeIntervalSince1970 * 1000)) + ".mov")
                        try FileManager.default.copyItem(at: source, to: file); try await fixtureClip?(file)
                    } catch { self.error = error.localizedDescription }
                    self.saving -= 1
                }
            } else { recording = true; startedAt = .now }
            return
        }
        #endif
        if recording { finishing = true; engine.stopRecording() }
        else {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(draftID.uuidString + "-" + UUID().uuidString + "-" + String(Int(Date.now.timeIntervalSince1970 * 1000)) + ".mov")
                recording = true; startedAt = .now; engine.record(to: url, seconds: min(120, remaining))
            } catch { self.error = error.localizedDescription }
        }
    }
}
struct RecordingView: View {
    @Binding var draft: Draft
    let onClip: @MainActor (URL) async throws -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @State private var recorder = Recorder()
    @State private var now = Date.now
    private var canFinish: Bool { !recorder.recording && !recorder.finishing && recorder.saving == 0 }
    private var recordingWindowRemaining: Double {
        guard let day = draft.vlogDay, let group = store.archive.groups.first(where: { $0.id == draft.group }) else { return 0 }
        let window = VlogCalendar.window(for: day, in: group)
        return now >= window.start ? max(0, window.end.timeIntervalSince(now)) : 0
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if recorder.ready { CameraPreview(engine: recorder.engine).ignoresSafeArea() }
            else if recorder.permissionDenied {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill").font(.largeTitle)
                    Text("Allow Camera and Microphone to record").font(.title2.bold()).multilineTextAlignment(.center)
                    Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.buttonStyle(.borderedProminent)
                    Text("You can also import clips from your draft.").font(.subheadline)
                }.padding(32)
            } else { ProgressView("Opening camera…").tint(.white) }
            VStack {
                HStack {
                    Button { if canFinish { dismiss() } else { recorder.closeRequested = true; if recorder.recording { recorder.finishing = true; recorder.engine.stopRecording() } } } label: { Image(systemName: "xmark").frame(width: 48, height: 48).background(.black.opacity(0.45), in: Circle()) }.accessibilityLabel("Save and close camera").accessibilityIdentifier("close-camera")
                    Spacer()
                    VStack(spacing: 4) {
                        Text(store.archive.groups.first { $0.id == draft.group }?.name ?? "Your day").font(.headline)
                        Text("\(draft.clips.count) clips saved").font(.caption).accessibilityIdentifier("recorded-clip-count")
                    }.padding(12).background(.black.opacity(0.45), in: Capsule())
                    Spacer()
                    Button { recorder.engine.flip { message in Task { @MainActor in recorder.error = message } } } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 48, height: 48).background(.black.opacity(0.45), in: Circle()) }.disabled(!recorder.ready || recorder.recording || recorder.finishing).accessibilityLabel("Switch camera")
                }.padding()
                Spacer()
                if let message = recorder.error { Text(message).font(.subheadline).padding().background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal) }
                VStack(spacing: 16) {
                    if let day = draft.vlogDay, let group = store.archive.groups.first(where: { $0.id == draft.group }), recordingWindowRemaining <= 0 {
                        let window = VlogCalendar.window(for: day, in: group)
                        Text(now < window.start ? "Filming opens " + VlogCalendar.label(window.start, in: group, format: "EEE 'at' h:mm a") : "Filming has closed for this day. Review your saved clips to edit and share.").font(.subheadline).multilineTextAlignment(.center)
                    }
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let elapsed = recorder.startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                        Text(recorder.recording ? "\(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))" : "Tap to record your next moment")
                            .font(.subheadline.monospacedDigit()).padding(8).background(.black.opacity(0.4), in: Capsule())
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(Duration.seconds(draft.totalDuration).formatted(.time(pattern: .minuteSecond))).font(.headline.monospacedDigit()); Text("of 10 min").font(.caption) }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { recorder.toggle(folder: store.root.appendingPathComponent("PendingCapture"), draftID: draft.id, remaining: min(Limits.vlogSeconds - draft.totalDuration, recordingWindowRemaining)) } label: {
                            ZStack { Circle().stroke(.white, lineWidth: 4).frame(width: 84, height: 84); if recorder.recording { RoundedRectangle(cornerRadius: 7).fill(.red).frame(width: 32, height: 32) } else { Circle().fill(.red).frame(width: 70, height: 70) } }
                        }.disabled(!recorder.ready || recorder.finishing || (!recorder.recording && (draft.clips.count + recorder.saving >= Limits.clips || draft.totalDuration >= Limits.vlogSeconds || recordingWindowRemaining <= 0)))
                            .accessibilityLabel(recorder.recording ? "Stop recording" : "Start recording").accessibilityIdentifier("capture-toggle")
                        Button("Review") { dismiss() }.font(.headline).frame(maxWidth: .infinity, alignment: .trailing).disabled(!canFinish).accessibilityIdentifier("review-clips")
                    }
                    Text(recorder.saving > 0 ? "Saving clip…" : "Clips save automatically. Keep recording whenever you're ready.").font(.caption).multilineTextAlignment(.center)
                }.padding(24).background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            }
        }.foregroundStyle(.white)
        .interactiveDismissDisabled(!canFinish)
        .task { await recorder.prepare(onClip: onClip) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
        .onDisappear { recorder.engine.stop() }
        .onChange(of: canFinish) { _, value in if value && recorder.closeRequested { dismiss() } }
        .onChange(of: scene) { _, value in if value != .active { recorder.finishing = recorder.recording; recorder.engine.stopRecording() } }
    }
}
struct CameraPreview: UIViewRepresentable {
    let engine: CameraEngine
    func makeUIView(context: Context) -> CameraPreviewSurface { let view = CameraPreviewSurface(); view.layerView.session = engine.session; view.layerView.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ uiView: CameraPreviewSurface, context: Context) {}
}
final class CameraPreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var layerView: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
