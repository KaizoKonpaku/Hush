import CoreMedia
import CoreVideo
import Foundation
import Synchronization
import Testing
@testable import Hush

struct LiveCaptureTests {
    @Test func liveFramesAreDownsampledAndStoppedOutputsIgnoreLateFrames() throws {
        var pixel: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 2560, 1440, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess)
        let buffer = try #require(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 127, CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var description: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 5),
            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: try #require(description), sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        let values = Mutex<[CapturedFrame]>([])
        let output = CaptureFrameOutput { frame in values.withLock { $0.append(frame) } }
        output.process(try #require(sample))
        let frame = try #require(values.withLock { $0.first })
        #expect(frame.image?.width == 1280)
        #expect(frame.image?.height == 720)
        #expect(frame.jpeg.count < 1024 * 1024)
        let rotatedFrames = Mutex<[CapturedFrame]>([])
        let rotatedOutput = CaptureFrameOutput { frame in rotatedFrames.withLock { $0.append(frame) } }
        rotatedOutput.process(try #require(sample), orientation: .right)
        let rotated = try #require(rotatedFrames.withLock { $0.first })
        #expect(rotated.image?.width == 720)
        #expect(rotated.image?.height == 1280)
        output.stop()
        output.process(try #require(sample))
        #expect(values.withLock { $0.count } == 1)
    }

    @Test func invalidLiveImageIsNeverWrittenToAttachmentStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let importer = AttachmentImporter(root: root)
        await #expect(throws: HushError.self) {
            try await importer.importCapturedImage(Data("not an image".utf8), name: "Bad frame")
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
