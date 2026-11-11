import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Testing
@testable import PrivacyAirPods

@Test func captureUsesDisplayTimeAndRejectsMissingOrIncompleteMetadata() throws {
    var pixels: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &pixels) == kCVReturnSuccess)
    let pixelBuffer = try #require(pixels)
    var description: CMVideoFormatDescription?
    #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &description) == noErr)
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: 999, timescale: 1), decodeTimeStamp: .invalid)
    var result: CMSampleBuffer?
    #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: try #require(description), sampleTiming: &timing, sampleBufferOut: &result) == noErr)
    let sample = try #require(result)
    let attachments = try #require(CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true))
    let values = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
    func set(_ key: SCStreamFrameInfo, _ value: NSNumber) {
        let name = key.rawValue as NSString
        CFDictionarySetValue(values, Unmanaged.passUnretained(name).toOpaque(), Unmanaged.passUnretained(value).toOpaque())
    }
    set(.status, NSNumber(value: SCFrameStatus.complete.rawValue))
    // PTS가 있어도 displayTime이 없으면 대체 시각으로 승인하지 않아야 함.
    #expect(CapturedScreenFrame(sample) == nil)
    set(.displayTime, NSNumber(value: UInt64(123)))
    let frame = try #require(CapturedScreenFrame(sample))
    #expect(frame.displayTime == 123)
    #expect(frame.image.extent.size == CGSize(width: 16, height: 16))
    set(.status, NSNumber(value: SCFrameStatus.idle.rawValue))
    #expect(CapturedScreenFrame(sample) == nil)
}
