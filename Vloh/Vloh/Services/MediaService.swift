import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

struct ImportedMovie: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) } importing: { received in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VlohImports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedMovie(url: destination)
        }
    }
}
actor MediaService {
    let root: URL
    let cache: URL
    init(root: URL, cache: URL) { self.root = root; self.cache = cache }
    func importClip(from source: URL) async throws -> Clip {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= Limits.vlogSeconds,
              !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw VlohError.message("Choose a video shorter than 10 minutes.")
        }
        let directory = root.appendingPathComponent("Clips", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".mov"
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
        var filmedAt: Date?
        if source.deletingLastPathComponent().lastPathComponent == "PendingCapture", let millis = Double(source.deletingPathExtension().lastPathComponent.split(separator: "-").last ?? "") { filmedAt = Date(timeIntervalSince1970: millis / 1000) }
        else {
            let metadata = try await asset.load(.commonMetadata)
            if let item = metadata.first(where: { $0.commonKey == .commonKeyCreationDate }), let value = try await item.load(.stringValue) {
                filmedAt = ISO8601DateFormatter().date(from: value)
                if filmedAt == nil { let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; filmedAt = parser.date(from: value) }
            }
        }
        return Clip(filename: name, duration: duration, end: duration, sourceCapture: source.deletingLastPathComponent().lastPathComponent == "PendingCapture" ? source.lastPathComponent : nil, filmedAt: filmedAt)
    }
    func export(_ draft: Draft) async throws -> (video: String, poster: String) {
        guard !draft.clips.isEmpty, draft.clips.count <= Limits.clips, draft.totalDuration <= Limits.vlogSeconds else {
            throw VlohError.message("Keep your vlog under 10 minutes and 40 clips.")
        }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VlohError.message("Couldn't prepare the video. Your clips are still saved.")
        }
        var audio: AVMutableCompositionTrack?
        let canvas = CGSize(width: 720, height: 1280)
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero
        for clip in draft.clips {
            try Task.checkCancellation()
            guard clip.length > 0 else { throw VlohError.message("One clip is empty. Adjust its trim and try again.") }
            let asset = AVURLAsset(url: root.appendingPathComponent("Clips/" + clip.filename))
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw VlohError.message("One clip has no video track.") }
            let range = CMTimeRange(start: CMTime(seconds: max(0, clip.start), preferredTimescale: 600), duration: CMTime(seconds: clip.length, preferredTimescale: 600))
            try video.insertTimeRange(range, of: sourceVideo, at: cursor)
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                let available = try await sourceAudio.load(.timeRange)
                let audioRange = CMTimeRangeGetIntersection(range, otherRange: available)
                if audioRange.duration.seconds > 0 {
                    if audio == nil { audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
                    guard let audio else { throw VlohError.message("Couldn’t prepare the clip’s audio.") }
                    try audio.insertTimeRange(audioRange, of: sourceAudio, at: cursor + (audioRange.start - range.start))
                }
            }
            let size = try await sourceVideo.load(.naturalSize)
            let transform = try await sourceVideo.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            let factor = min(canvas.width / abs(rect.width), canvas.height / abs(rect.height))
            let normalized = transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                .concatenating(CGAffineTransform(scaleX: factor, y: factor))
                .concatenating(CGAffineTransform(translationX: (canvas.width - abs(rect.width) * factor) / 2, y: (canvas.height - abs(rect.height) * factor) / 2))
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
            layer.setTransform(normalized, at: cursor)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: range.duration)
            instruction.layerInstructions = [layer]
            instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
            instructions.append(instruction)
            cursor = cursor + range.duration
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1280x720) else {
            throw VlohError.message("This video format couldn't be exported.")
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        let directory = root.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = draft.id.uuidString + "-" + UUID().uuidString + ".mp4"
        let destination = directory.appendingPathComponent(filename)
        try await session.export(to: destination, as: .mp4)
        let bytes = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes <= Limits.videoBytes else { try? FileManager.default.removeItem(at: destination); throw VlohError.message("This export is too large. Trim a few clips and try again.") }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 640)
        let image = try await generator.image(at: .zero).image
        guard let data = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let jpeg = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw VlohError.message("Couldn't create a video preview.")
        }
        CGImageDestinationAddImage(jpeg, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(jpeg), let bytes = CFDataGetBytePtr(data) else {
            throw VlohError.message("Couldn't save the video preview.")
        }
        let poster = filename + ".jpg"
        try Data(bytes: bytes, count: CFDataGetLength(data)).write(to: directory.appendingPathComponent(poster), options: .atomic)
        return (filename, poster)
    }
    func timeline(_ clip: Clip) async throws -> [Data] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: root.appendingPathComponent("Clips/" + clip.filename)))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 100, height: 150)
        var frames: [Data] = []
        for index in 0..<10 {
            try Task.checkCancellation()
            let image = try await generator.image(at: CMTime(seconds: clip.duration * Double(index) / 10, preferredTimescale: 600)).image
            let data = NSMutableData()
            guard let target = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
            if CGImageDestinationFinalize(target) { frames.append(data as Data) }
        }
        return frames
    }
    func cleanupClip(_ clip: Clip) { try? FileManager.default.removeItem(at: root.appendingPathComponent("Clips/" + clip.filename)) }
    func clipURL(_ clip: Clip) -> URL { root.appendingPathComponent("Clips/" + clip.filename) }
    func exportURL(_ name: String) -> URL { root.appendingPathComponent("Exports/" + name) }
    func cachedURL(_ vlog: Vlog, poster: Bool = false) -> URL {
        // Zone+owner keeps identical record names in different shares separate.
        let key = Data(vlog.group.key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return cache.appendingPathComponent(key + "-" + vlog.id + (poster ? ".jpg" : ".mp4"))
    }
    func purgeCache(keeping protected: URL? = nil) throws {
        let files = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        let sorted = try files.map { ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])) }.sorted { ($0.1.contentModificationDate ?? .distantPast) < ($1.1.contentModificationDate ?? .distantPast) }
        var bytes = sorted.reduce(0) { $0 + ($1.1.fileSize ?? 0) }
        for (url, values) in sorted where bytes > Limits.cacheBytes && url != protected {
            try FileManager.default.removeItem(at: url); bytes -= values.fileSize ?? 0
        }
    }
    func cleanup(_ draft: Draft) {
        for clip in draft.clips { try? FileManager.default.removeItem(at: root.appendingPathComponent("Clips/" + clip.filename)) }
        if let file = draft.exportedFile {
            try? FileManager.default.removeItem(at: exportURL(file)); try? FileManager.default.removeItem(at: exportURL(file + ".jpg"))
        }
    }
}
