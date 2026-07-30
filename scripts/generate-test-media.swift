import AVFoundation
import CoreVideo
import Foundation

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = projectRoot.appendingPathComponent(
    "Test Media/Movies/Interstellar (2014)/Interstellar (2014).mp4"
)
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try? FileManager.default.removeItem(at: output)

let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let width = 640
let height = 360
let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]
)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ]
)
guard writer.canAdd(input) else {
    fatalError("Could not create the test video encoder.")
}
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

for frame in 0..<90 {
    while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.005)
    }
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
    guard let buffer = pixelBuffer else { continue }
    CVPixelBufferLockBaseAddress(buffer, [])
    let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * rowBytes + x * 4
            bytes[offset] = UInt8((x + frame * 2) % 255)
            bytes[offset + 1] = UInt8((y * 2 + frame) % 255)
            bytes[offset + 2] = UInt8((frame * 3) % 255)
            bytes[offset + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(
        buffer,
        withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)
    )
}

input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else {
    fatalError(writer.error?.localizedDescription ?? "Test video generation failed.")
}

let copies = [
    projectRoot.appendingPathComponent("Test Media/Movies/Alien.1979.1080p.mp4"),
    projectRoot.appendingPathComponent("Test Media/TV Shows/The Expanse/Season 01/The Expanse S01E01.mp4"),
    projectRoot.appendingPathComponent("Test Media/TV Shows/The Expanse/Season 01/The Expanse S01E02.mp4")
]
for copy in copies {
    try FileManager.default.createDirectory(
        at: copy.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try? FileManager.default.removeItem(at: copy)
    try FileManager.default.copyItem(at: output, to: copy)
}

print("Generated \(copies.count + 1) copyright-free test clips.")
