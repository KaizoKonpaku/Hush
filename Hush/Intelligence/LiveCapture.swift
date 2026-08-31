import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Observation
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif
import Synchronization
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct CapturedFrame: Sendable {
    let jpeg: Data
    let capturedAt: Date
    var image: CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

final class CaptureFrameOutput: NSObject, @unchecked Sendable {
    private struct State {
        let context = CIContext(options: [.cacheIntermediates: false])
        var lastFrame: ContinuousClock.Instant?
        var stopped = false
    }
    private let state = Mutex(State())
    private let onFrame: @Sendable (CapturedFrame) -> Void
    let queue = DispatchQueue(label: "org.kaizosha.Hush.live-frames", qos: .userInitiated)

    init(onFrame: @escaping @Sendable (CapturedFrame) -> Void) { self.onFrame = onFrame }
    func stop() { state.withLock { $0.stopped = true } }

    func process(_ sample: CMSampleBuffer, orientation: CGImagePropertyOrientation = .up) {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let frame = state.withLock { state -> CapturedFrame? in
            guard !state.stopped else { return nil }
            if let last = state.lastFrame, last.duration(to: .now) < .milliseconds(200) { return nil }
            state.lastFrame = .now
            let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
            let dimension = max(image.extent.width, image.extent.height)
            guard dimension > 0 else { return nil }
            let scale = min(1, 1280 / dimension)
            let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cgImage = state.context.createCGImage(resized, from: resized.extent) else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return CapturedFrame(jpeg: data as Data, capturedAt: Date())
        }
        if let frame { onFrame(frame) }
    }
}

#if canImport(ScreenCaptureKit)
extension CaptureFrameOutput: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let info = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = info.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
        let orientation = (info.first?[.videoOrientation] as? NSNumber)
            .flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
        process(sampleBuffer, orientation: orientation)
    }
}
#endif

#if os(macOS) || os(iOS)
extension CaptureFrameOutput: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        process(sampleBuffer)
    }
}

actor CameraCaptureEngine {
    private let session = AVCaptureSession()
    private var output: AVCaptureVideoDataOutput?
    private var rotation: AVCaptureDevice.RotationCoordinator?

    func start(output handler: CaptureFrameOutput, front: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        #if os(iOS)
        session.automaticallyConfiguresApplicationAudioSession = false
        #endif
        let device: AVCaptureDevice?
        #if os(iOS)
        device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
        #else
        device = AVCaptureDevice.default(for: .video)
        #endif
        guard let device else { throw HushError.message("No camera is connected. Attach an image or share a screen instead.") }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw HushError.message("This camera cannot be opened right now.") }
        session.addInput(input)
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(handler, queue: handler.queue)
        guard session.canAddOutput(output) else { throw HushError.message("The camera could not deliver video frames.") }
        session.addOutput(output)
        self.output = output
        rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }

    func run() {
        updateRotation()
        session.startRunning()
    }

    func updateRotation() {
        guard let connection = output?.connection(with: .video), let rotation else { return }
        let angle = rotation.videoRotationAngleForHorizonLevelCapture
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }

    func stop() {
        session.stopRunning()
        output?.setSampleBufferDelegate(nil, queue: nil)
    }
}
#endif

// The picker supplies an immutable selection; this box only transports it to the main actor.
#if canImport(ScreenCaptureKit)
private struct ScreenSelection: @unchecked Sendable { let filter: SCContentFilter }

private final class ScreenPickerObserver: NSObject, SCContentSharingPickerObserver, Sendable {
    let updated: @Sendable (ScreenSelection) -> Void
    let cancelled: @Sendable () -> Void
    let failed: @Sendable (Error) -> Void

    init(updated: @escaping @Sendable (ScreenSelection) -> Void, cancelled: @escaping @Sendable () -> Void,
         failed: @escaping @Sendable (Error) -> Void) {
        self.updated = updated
        self.cancelled = cancelled
        self.failed = failed
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        updated(ScreenSelection(filter: filter))
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) { cancelled() }
    func contentSharingPickerStartDidFailWithError(_ error: Error) { failed(error) }
}
#endif

@MainActor @Observable
final class LiveCapture: NSObject {
    enum Source: String { case camera, screen }
    private(set) var source: Source?
    private(set) var frame: CapturedFrame?
    private(set) var isStarting = false
    private(set) var frontCamera = false
    var isActive: Bool { source != nil }
    var title: String { source == .camera ? "Live camera" : "Live screen" }
    static var supportsScreenCapture: Bool {
        #if canImport(ScreenCaptureKit)
        true
        #else
        false
        #endif
    }
    @ObservationIgnored var onError: (@MainActor (Error) -> Void)?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var output: CaptureFrameOutput?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var rotationObserver: NSObjectProtocol?
    @ObservationIgnored private var pickerSessionID: UUID?
    #if canImport(ScreenCaptureKit)
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var pickerObserver: ScreenPickerObserver?
    #endif
    #if os(macOS) || os(iOS)
    @ObservationIgnored private var camera: CameraCaptureEngine?
    #endif

    func startCamera() {
        #if os(macOS) || os(iOS)
        stop()
        source = .camera
        isStarting = true
        let id = UUID()
        operationID = id
        startTask = Task {
            do {
                await stopTask?.value
                guard await AVCaptureDevice.requestAccess(for: .video) else {
                    throw HushError.message("Allow camera access in Settings to use live camera context.")
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                let engine = CameraCaptureEngine()
                camera = engine
                let output = makeOutput(id: id)
                self.output = output
                try await engine.start(output: output, front: frontCamera)
                try Task.checkCancellation()
                guard operationID == id else { await engine.stop(); return }
                await engine.run()
                guard operationID == id else { await engine.stop(); return }
                isStarting = false
                #if os(iOS)
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                rotationObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
                    Task { await engine.updateRotation() }
                }
                #endif
            } catch { fail(error, id: id) }
        }
        #else
        onError?(HushError.message("Direct camera access is not available on this platform. Use a shared screen or an image attachment."))
        #endif
    }

    func flipCamera() {
        guard source == .camera else { return }
        frontCamera.toggle()
        startCamera()
    }

    func startScreen() {
        #if canImport(ScreenCaptureKit)
        stop()
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else {
            onError?(HushError.message("Screen sharing is not available on this device or is restricted by system settings."))
            return
        }
        source = .screen
        isStarting = true
        operationID = UUID()
        let session = UUID()
        pickerSessionID = session
        var configuration = SCContentSharingPickerConfiguration()
        #if os(macOS)
        configuration.allowedPickerModes = [.singleWindow, .singleDisplay, .singleApplication]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "org.kaizosha.HUSH"]
        picker.maximumStreamCount = 1
        #else
        configuration.showsMicrophoneControl = false
        #if os(iOS)
        configuration.showsCameraControl = false
        #endif
        #endif
        picker.defaultConfiguration = configuration
        let observer = ScreenPickerObserver(updated: { [weak self] selection in
            Task { @MainActor in
                guard let self, self.pickerSessionID == session else { return }
                self.startScreen(selection: selection)
            }
        }, cancelled: { [weak self] in
            Task { @MainActor in
                guard let self, self.pickerSessionID == session, self.stream == nil else { return }
                self.stop()
            }
        }, failed: { [weak self] error in
            Task { @MainActor in
                guard let self, self.pickerSessionID == session, let id = self.operationID else { return }
                self.fail(error, id: id)
            }
        })
        pickerObserver = observer
        picker.add(observer)
        picker.isActive = true
        picker.present()
        #else
        onError?(HushError.message("Live screen sharing requires a physical OS 27 device. This simulator SDK does not include ScreenCaptureKit."))
        #endif
    }

    func stop() {
        operationID = nil
        startTask?.cancel()
        output?.stop()
        output = nil
        frameTask?.cancel()
        frameTask = nil
        #if canImport(ScreenCaptureKit)
        let oldStream = stream
        stream = nil
        #endif
        let previousStop = stopTask
        #if os(macOS) || os(iOS)
        let oldCamera = camera
        camera = nil
        #endif
        stopTask = Task {
            await previousStop?.value
            #if canImport(ScreenCaptureKit)
            try? await oldStream?.stopCapture()
            #endif
            #if os(macOS) || os(iOS)
            await oldCamera?.stop()
            #endif
        }
        pickerSessionID = nil
        #if canImport(ScreenCaptureKit)
        if let pickerObserver {
            SCContentSharingPicker.shared.remove(pickerObserver)
            SCContentSharingPicker.shared.isActive = false
        }
        pickerObserver = nil
        #endif
        if let rotationObserver { NotificationCenter.default.removeObserver(rotationObserver) }
        rotationObserver = nil
        #if os(iOS)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        #endif
        frame = nil
        source = nil
        isStarting = false
    }

    private func makeOutput(id: UUID) -> CaptureFrameOutput {
        frameTask?.cancel()
        let (frames, continuation) = AsyncStream<CapturedFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        frameTask = Task { [weak self] in
            for await frame in frames {
                guard let self, self.operationID == id else { return }
                self.frame = frame
            }
        }
        return CaptureFrameOutput { frame in continuation.yield(frame) }
    }

    func waitUntilStopped() async { await stopTask?.value }

    #if canImport(ScreenCaptureKit)
    private func startScreen(selection: ScreenSelection) {
        guard source == .screen, operationID != nil else { return }
        let id = UUID()
        operationID = id
        let previousStream = stream
        stream = nil
        output?.stop()
        output = nil
        frame = nil
        isStarting = true
        startTask?.cancel()
        startTask = Task {
            do {
                await stopTask?.value
                try await previousStream?.stopCapture()
                try Task.checkCancellation()
                guard operationID == id else { return }
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = false
                #if !os(visionOS)
                let size = selection.filter.contentRect.size
                if size.width > 0, size.height > 0 {
                    let scale = min(1, 1280 / max(size.width, size.height))
                    configuration.width = max(2, Int(size.width * scale))
                    configuration.height = max(2, Int(size.height * scale))
                }
                #endif
                #if os(macOS)
                configuration.captureMicrophone = false
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5)
                configuration.queueDepth = 3
                configuration.showsCursor = true
                configuration.streamName = "Hush live context"
                #endif
                let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: self)
                let output = makeOutput(id: id)
                self.output?.stop()
                self.output = output
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                self.stream = stream
                try await stream.startCapture()
                guard operationID == id else { try? await stream.stopCapture(); return }
                isStarting = false
            } catch { fail(error, id: id) }
        }
    }
    #endif

    private func fail(_ error: Error, id: UUID) {
        guard operationID == id else { return }
        stop()
        if !(error is CancellationError) { onError?(error) }
    }

}

#if canImport(ScreenCaptureKit)
extension LiveCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let identity = ObjectIdentifier(stream)
        Task { @MainActor [weak self] in
            guard let self, let active = self.stream, ObjectIdentifier(active) == identity, let id = self.operationID else { return }
            self.fail(error, id: id)
        }
    }
}
#endif
