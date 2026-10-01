import SwiftUI
import AVKit

struct FullscreenPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var player: AVPlayer?
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player { PlayerSurface(player: player).ignoresSafeArea().accessibilityIdentifier("fullscreen-video") }
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 48, height: 48).background(.black.opacity(0.6), in: Circle()) }.padding(16).accessibilityLabel("Close full screen").accessibilityIdentifier("close-fullscreen")
        }.onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = AVPlayer(url: url); player?.play()
        }.onDisappear { player?.pause(); player = nil }
        .onChange(of: phase) { _, value in if value != .active { player?.pause() } }
    }
}
