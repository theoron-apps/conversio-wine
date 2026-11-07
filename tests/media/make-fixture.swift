import AVFoundation
import CoreMedia
import CoreVideo

// Original synthetic fixture: one second of colored H.264 frames and silent AAC.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 64000, AVVideoMaxKeyFrameIntervalKey: 1]])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video,
    sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
    AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
writer.add(video); writer.add(audio)
guard writer.startWriting() else { fatalError("\(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)
for frame in 0..<30 {
    while !video.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
    var pixel: CVPixelBuffer?
    precondition(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess)
    CVPixelBufferLockBaseAddress(pixel!, [])
    let bytes = CVPixelBufferGetBaseAddress(pixel!)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(pixel!)
    for y in 0..<64 { for x in 0..<64 {
        let p = y*stride+x*4
        bytes[p]=255; bytes[p+1]=UInt8(frame*8); bytes[p+2]=UInt8(x*4); bytes[p+3]=UInt8(y*4)
    } }
    CVPixelBufferUnlockBaseAddress(pixel!, [])
    precondition(adaptor.append(pixel!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
}
video.markAsFinished()
var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 4,
    mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
var description: CMAudioFormatDescription?
precondition(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &format, layoutSize: 0,
    layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr)
var block: CMBlockBuffer?
precondition(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil,
    blockLength: 48000*4, blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
    dataLength: 48000*4, flags: 0, blockBufferOut: &block) == noErr)
precondition(CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: 48000*4) == noErr)
var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
var sample: CMSampleBuffer?; var sampleSize = 4
precondition(CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: description,
    sampleCount: 48000, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
    sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr)
while !audio.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
precondition(audio.append(sample!)); audio.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
precondition(done.wait(timeout: .now()+15) == .success)
precondition(writer.status == .completed, "\(String(describing: writer.error))")
print(output.path)
