import Foundation
import ARKit
import Accelerate

/// Writes per-frame LiDAR depth + confidence to disk.
///
/// Output format:
///   depth/000NNN.bin       — raw UInt16 little-endian, millimeters,
///                            width×height read from sidecar
///   depth/000NNN.bin.size  — "W,H\n" so consumer knows the shape
///   confidence/000NNN.bin  — UInt8, ARConfidenceLevel.rawValue (0..2)
///
/// We write raw .bin instead of 16-bit PNG to avoid the Image I/O dance —
/// .bin is trivially read on any backend (`numpy.fromfile(..., dtype=uint16)`).
final class DepthEncoder {
    private let depthDir: URL
    private let confidenceDir: URL
    private let queue = DispatchQueue(label: "straylite.depth", qos: .utility)
    private var frameIndex: Int = 0

    init(depthDir: URL, confidenceDir: URL) {
        self.depthDir = depthDir
        self.confidenceDir = confidenceDir
    }

    func add(frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth else { return }
        let idx = frameIndex
        frameIndex += 1
        let depthMap = sceneDepth.depthMap
        let confidenceMap = sceneDepth.confidenceMap
        queue.async { [weak self] in
            self?.encode(depthMap: depthMap, confidenceMap: confidenceMap, index: idx)
        }
    }

    func finish() {
        queue.sync { }
    }

    private func encode(depthMap: CVPixelBuffer,
                        confidenceMap: CVPixelBuffer?,
                        index: Int) {
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let stride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
        let floats = base.assumingMemoryBound(to: Float32.self)

        // Convert metres → millimeters, clamp into UInt16. Anything beyond 65 m
        // gets saturated; in practice depth maps cap at ~5 m.
        var u16 = [UInt16](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let metres = floats[y * stride + x]
                let mm = metres * 1000.0
                if !mm.isFinite || mm < 0 {
                    u16[y * w + x] = 0
                } else if mm > Float(UInt16.max) {
                    u16[y * w + x] = .max
                } else {
                    u16[y * w + x] = UInt16(mm.rounded())
                }
            }
        }
        let depthURL = depthDir.appendingPathComponent(String(format: "%06d.bin", index))
        u16.withUnsafeBufferPointer { buf in
            let data = Data(buffer: buf)
            try? data.write(to: depthURL)
        }
        let sizeURL = depthDir.appendingPathComponent(String(format: "%06d.bin.size", index))
        try? "\(w),\(h)\n".write(to: sizeURL, atomically: false, encoding: .utf8)

        // Confidence: UInt8 raw bytes.
        if let conf = confidenceMap {
            CVPixelBufferLockBaseAddress(conf, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(conf, .readOnly) }
            let cw = CVPixelBufferGetWidth(conf)
            let ch = CVPixelBufferGetHeight(conf)
            let cstride = CVPixelBufferGetBytesPerRow(conf)
            if let cbase = CVPixelBufferGetBaseAddress(conf) {
                let bytes = cbase.assumingMemoryBound(to: UInt8.self)
                var packed = [UInt8](repeating: 0, count: cw * ch)
                for y in 0..<ch {
                    for x in 0..<cw {
                        packed[y * cw + x] = bytes[y * cstride + x]
                    }
                }
                let cURL = confidenceDir.appendingPathComponent(String(format: "%06d.bin", index))
                packed.withUnsafeBufferPointer { buf in
                    try? Data(buffer: buf).write(to: cURL)
                }
            }
        }
    }
}
