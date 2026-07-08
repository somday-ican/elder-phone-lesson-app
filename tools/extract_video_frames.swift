import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    fputs("Usage: swift extract_video_frames.swift input.mp4 output_dir count\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2], isDirectory: true)
let count = max(1, Int(args[3]) ?? 8)

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let asset = AVURLAsset(url: inputURL)
let durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: 720, height: 1280)

for index in 0..<count {
    let second = count == 1 ? 0 : (durationSeconds * Double(index) / Double(count - 1))
    let time = CMTime(seconds: min(max(second, 0), max(durationSeconds - 0.05, 0)), preferredTimescale: 600)
    let image = try generator.copyCGImage(at: time, actualTime: nil)
    let fileURL = outputURL.appendingPathComponent(String(format: "frame_%02d.jpg", index))
    guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw NSError(domain: "extract", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create image destination."])
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "extract", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not write \(fileURL.path)."])
    }
}

print("duration=\(durationSeconds)")
print("frames=\(count)")
