import SwiftUI
import AVKit

@MainActor @Observable
final class TrimPlayback {
    var player: AVPlayer?
    var position = 0.0
    var playing = false
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    func open(_ url: URL, clip: Clip) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url); self.player = player
        setRange(clip, seekTo: clip.start)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in self?.position = seconds; self?.playing = self?.player?.rate != 0 }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in Task { @MainActor in self?.playing = false } }
    }
    func setRange(_ clip: Clip, seekTo: Double? = nil) {
        player?.pause(); playing = false
        player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: clip.end, preferredTimescale: 600)
        if let seekTo { seek(seekTo) }
    }
    func seek(_ seconds: Double) { position = seconds; player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    func toggle(_ clip: Clip) {
        if playing { player?.pause(); playing = false }
        else { if position < clip.start || position >= clip.end - 0.03 { seek(clip.start) }; player?.play(); playing = true }
    }
    func close() { player?.pause(); if let timeObserver { player?.removeTimeObserver(timeObserver) }; if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; self.timeObserver = nil; self.endObserver = nil; player = nil }
}
struct TrimView: View {
    @State var clip: Clip
    let onSave: (Clip) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var playback = TrimPlayback()
    @State private var frames: [Data] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    Color.black
                    if let player = playback.player { PlayerSurface(player: player, controls: false) }
                    else { ProgressView().tint(.white) }
                }.clipShape(RoundedRectangle(cornerRadius: 18)).frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 16) {
                    HStack {
                        Button { playback.toggle(clip) } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 48, height: 48).background(.orange.opacity(0.15), in: Circle()) }.accessibilityLabel(playback.playing ? "Pause preview" : "Play trimmed clip").accessibilityIdentifier("play-trim")
                        VStack(alignment: .leading) { Text("\(clip.length, specifier: "%.1f") seconds kept").font(.headline); Text("Original: \(clip.duration, specifier: "%.1f") seconds").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Reset") { clip.start = 0; clip.end = clip.duration; playback.setRange(clip, seekTo: 0) }.disabled(clip.start == 0 && clip.end == clip.duration)
                    }
                    TrimTimeline(clip: $clip, frames: frames, position: playback.position) { edge in playback.setRange(clip, seekTo: edge) } onScrub: { position in playback.player?.pause(); playback.playing = false; playback.seek(position) }
                    HStack {
                        Text("Start \(clip.start, specifier: "%.1f")s").accessibilityIdentifier("trim-start-value")
                        Spacer()
                        Text("End \(clip.end, specifier: "%.1f")s").accessibilityIdentifier("trim-end-value")
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text("Drag the yellow handles to trim. Tap or drag inside the strip to scrub.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(.horizontal, 4)
            }.padding(20).frame(maxWidth: 750).frame(maxWidth: .infinity)
            .navigationTitle("Trim clip").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(clip); dismiss() }.fontWeight(.semibold).disabled(clip.length <= 0).accessibilityIdentifier("save-trim") }
            }
            .task {
                let url = await store.media.clipURL(clip)
                playback.open(url, clip: clip)
                do { frames = try await store.media.timeline(clip) } catch { self.error = "Preview frames couldn't load. You can still trim and play the clip." }
            }
            .onDisappear { playback.close() }
        }
    }
}
struct TrimTimeline: View {
    @Binding var clip: Clip
    let frames: [Data]
    let position: Double
    let onTrim: (Double) -> Void
    let onScrub: (Double) -> Void
    private var minimum: Double { min(0.1, clip.duration) }
    var body: some View {
        GeometryReader { geometry in
            let inset = 20.0, width = max(1, geometry.size.width - inset * 2)
            let start = inset + width * clip.start / clip.duration
            let end = inset + width * clip.end / clip.duration
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill().frame(width: width / CGFloat(max(1, frames.count)), height: 64).clipped() }
                    }
                }.frame(width: width, height: 64).background(.gray.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 8)).offset(x: inset)
                Rectangle().fill(.black.opacity(0.65)).frame(width: max(0, start - inset), height: 64).offset(x: inset)
                Rectangle().fill(.black.opacity(0.65)).frame(width: max(0, inset + width - end), height: 64).offset(x: end)
                Rectangle().stroke(.yellow, lineWidth: 3).frame(width: max(1, end - start), height: 68).offset(x: start)
                Color.clear.contentShape(Rectangle()).frame(width: max(1, end - start), height: 64).offset(x: start)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim-timeline")).onChanged { value in onScrub(min(clip.end, max(clip.start, (value.location.x - inset) / width * clip.duration))) })
                Rectangle().fill(.white).frame(width: 2, height: 70).offset(x: min(end, max(start, inset + width * position / clip.duration))).allowsHitTesting(false)
                handle(start: true).offset(x: start - 20)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim-timeline")).onChanged { value in clip.start = min(clip.end - minimum, max(0, (value.location.x - inset) / width * clip.duration)); onTrim(clip.start) })
                handle(start: false).offset(x: end - 20)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim-timeline")).onChanged { value in clip.end = max(clip.start + minimum, min(clip.duration, (value.location.x - inset) / width * clip.duration)); onTrim(max(clip.start, clip.end - minimum)) })
            }.coordinateSpace(name: "trim-timeline")
        }.frame(height: 76)
    }
    private func handle(start: Bool) -> some View {
        ZStack { RoundedRectangle(cornerRadius: 6).fill(.yellow).frame(width: 16, height: 76); Capsule().fill(.black.opacity(0.6)).frame(width: 3, height: 28) }.frame(width: 40, height: 76).contentShape(Rectangle())
            .accessibilityElement().accessibilityLabel(start ? "Trim start" : "Trim end").accessibilityValue(String(format: "%.1f seconds", start ? clip.start : clip.end)).accessibilityIdentifier(start ? "trim-start-handle" : "trim-end-handle")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 0.1 : -0.1
                if start { clip.start = min(clip.end - minimum, max(0, clip.start + delta)); onTrim(clip.start) }
                else { clip.end = max(clip.start + minimum, min(clip.duration, clip.end + delta)); onTrim(clip.end - minimum) }
            }
    }
}
struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    var controls = true
    func makeUIViewController(context: Context) -> AVPlayerViewController { let view = AVPlayerViewController(); view.player = player; view.showsPlaybackControls = controls; view.videoGravity = .resizeAspect; view.allowsPictureInPicturePlayback = true; return view }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) { controller.player = player; controller.showsPlaybackControls = controls }
}
