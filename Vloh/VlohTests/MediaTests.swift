import XCTest
import AVFoundation
import UIKit
@testable import Vloh

final class MediaTests: XCTestCase {
    @MainActor func testImportTrimAndMixedOrientationExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let landscape = folder.appendingPathComponent("landscape.mp4")
        let portrait = folder.appendingPathComponent("portrait.mp4")
        try await makeVideo(at: landscape, rotated: false)
        try await makeVideo(at: portrait, rotated: true)
        let service = MediaService(root: folder, cache: folder.appendingPathComponent("cache"))
        var first = try await service.importClip(from: landscape)
        var second = try await service.importClip(from: portrait)
        first.start = 0.2; first.end = 0.8
        second.start = 0.1; second.end = 0.6
        let draft = Draft(group: GroupID(zone: "test", owner: "test", shared: false), clips: [first, second])
        let exported = try await service.export(draft)
        let videoURL = await service.exportURL(exported.video)
        let posterURL = await service.exportURL(exported.poster)
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1.1, accuracy: 0.08)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 720); XCTAssertEqual(size.height, 1280)
        let data = try Data(contentsOf: posterURL)
        XCTAssertNotNil(UIImage(data: data))
        let originalURL = await service.clipURL(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        var finished = draft; finished.exportedFile = exported.video
        await service.cleanup(finished)
        XCTAssertFalse(FileManager.default.fileExists(atPath: videoURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: posterURL.path))
    }
    @MainActor func testInvalidVideoPreservesSource() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("broken.mov")
        try Data("not a movie".utf8).write(to: source)
        let service = MediaService(root: folder, cache: folder)
        do { _ = try await service.importClip(from: source); XCTFail("Invalid movie accepted") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    @MainActor private func makeVideo(at url: URL, rotated: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? VlohError.message("Fixture encoder failed") }
                try await Task.sleep(for: .milliseconds(2))
            }
            var pixel: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, nil, &pixel), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, rotated ? 160 : 80, CVPixelBufferGetDataSize(buffer)) }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished(); writer.endSession(atSourceTime: CMTime(value: 30, timescale: 30))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
