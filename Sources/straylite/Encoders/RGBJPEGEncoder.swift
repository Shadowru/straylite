import Foundation
import ARKit
import CoreImage

/// Writes each accepted ARFrame's RGB image to `rgb/000NNN.jpg`.
/// Compared to mp4 this is larger on disk but trivial to consume on a
/// backend without ffmpeg. Frame indices align with `odometry.csv`.
final class RGBJPEGEncoder {
    private let outDir: URL
    private let ciContext: CIContext
    private let queue = DispatchQueue(label: "straylite.rgb", qos: .userInitiated)
    private var frameIndex: Int = 0
    private let quality: CGFloat

    init(outDir: URL, quality: CGFloat = 0.88) {
        self.outDir = outDir
        self.quality = quality
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    func add(frame: ARFrame) {
        let idx = frameIndex
        frameIndex += 1
        let pixelBuffer = frame.capturedImage
        queue.async { [weak self] in
            self?.encode(pixelBuffer: pixelBuffer, index: idx)
        }
    }

    func finish() {
        queue.sync { }  // drain
    }

    private func encode(pixelBuffer: CVPixelBuffer, index: Int) {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let url = outDir.appendingPathComponent(String(format: "%06d.jpg", index))
        let opts: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality
        ]
        do {
            try ciContext.writeJPEGRepresentation(
                of: ci,
                to: url,
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: opts
            )
        } catch {
            print("RGB JPEG write failed (\(index)): \(error)")
        }
    }
}
