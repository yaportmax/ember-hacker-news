import AVFoundation
import Foundation

// Session mutation and capture commands are confined to this serial queue.
// Delegate callbacks only forward Sendable values to the main actor.
final class CameraEngine: NSObject, @unchecked Sendable, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "vloh.camera", qos: .userInitiated)
    private let output = AVCaptureMovieFileOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var completion: (@Sendable (URL, String?) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func prepare(onReady: @escaping @Sendable (String?) -> Void, onClip: @escaping @Sendable (URL, String?) -> Void) {
        queue.async { [self] in
            completion = onClip
            do {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
                try AVAudioSession.sharedInstance().setActive(true)
                if !configured {
                    session.beginConfiguration()
                    session.sessionPreset = .hd1280x720
                    defer { session.commitConfiguration() }
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let microphone = AVCaptureDevice.default(for: .audio) else { throw VlohError.message("Camera or microphone unavailable.") }
                    let video = try AVCaptureDeviceInput(device: camera)
                    let audio = try AVCaptureDeviceInput(device: microphone)
                    guard session.canAddInput(video), session.canAddInput(audio), session.canAddOutput(output) else { throw VlohError.message("Couldn't start the camera.") }
                    session.addInput(video); session.addInput(audio); session.addOutput(output)
                    input = video; configured = true
                    if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in self?.stopRecording() })
                }
                if !session.isRunning { session.startRunning() }
                onReady(nil)
            } catch { onReady(error.localizedDescription) }
        }
    }
    func record(to url: URL, seconds: Double) {
        queue.async { [self] in
            guard session.isRunning, !output.isRecording else { completion?(url, "The camera was interrupted. Try recording again."); return }
            output.maxRecordedDuration = CMTime(seconds: max(0.1, seconds), preferredTimescale: 600)
            output.startRecording(to: url, recordingDelegate: self)
        }
    }
    func stopRecording() { queue.async { [self] in if output.isRecording { output.stopRecording() } } }
    func stop() { queue.async { [self] in if output.isRecording { output.stopRecording() }; if session.isRunning { session.stopRunning() }; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } }
    func flip(_ finished: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let old = input, !output.isRecording else { finished(nil); return }
            do {
                let position: AVCaptureDevice.Position = old.device.position == .back ? .front : .back
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { throw VlohError.message("That camera isn't available.") }
                let replacement = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration(); defer { session.commitConfiguration() }
                session.removeInput(old)
                guard session.canAddInput(replacement) else { session.addInput(old); throw VlohError.message("Couldn't switch cameras.") }
                session.addInput(replacement); input = replacement
                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = position == .front }
                }
                finished(nil)
            } catch { finished(error.localizedDescription) }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let nsError = error as NSError?
        let succeeded = nsError == nil || (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        queue.async { [self] in completion?(outputFileURL, succeeded ? nil : nsError?.localizedDescription ?? "Couldn't save that recording.") }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
