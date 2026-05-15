import Foundation
import ARKit

/// Streams per-frame camera pose + intrinsics to `odometry.csv`.
/// Schema (matches Stray Scanner format conventions):
///   frame, timestamp, fx, fy, cx, cy, x, y, z, qx, qy, qz, qw
/// where (x,y,z) is camera position in ARKit world space and (qx,qy,qz,qw)
/// is the rotation quaternion. timestamp is seconds since session start.
final class OdometryCSVEncoder {
    private let fileURL: URL
    private var handle: FileHandle?
    private let sessionStart: Date
    private var frameIndex: Int = 0
    private let queue = DispatchQueue(label: "straylite.odometry", qos: .utility)

    init(fileURL: URL, sessionStart: Date) throws {
        self.fileURL = fileURL
        self.sessionStart = sessionStart
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: fileURL)
        try writeHeader()
    }

    func add(frame: ARFrame) {
        let idx = frameIndex
        frameIndex += 1
        let ts = frame.timestamp
        let intr = frame.camera.intrinsics
        let trans = frame.camera.transform
        queue.async { [weak self] in
            self?.write(index: idx, timestamp: ts, intrinsics: intr, transform: trans)
        }
    }

    func finish() {
        queue.sync { }  // drain
        try? handle?.close()
        handle = nil
    }

    // MARK: - private

    private func writeHeader() throws {
        let header = "frame,timestamp,fx,fy,cx,cy,x,y,z,qx,qy,qz,qw\n"
        try handle?.write(contentsOf: Data(header.utf8))
    }

    private func write(index: Int,
                       timestamp: TimeInterval,
                       intrinsics: simd_float3x3,
                       transform: simd_float4x4) {
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]
        let tx = transform.columns.3.x
        let ty = transform.columns.3.y
        let tz = transform.columns.3.z
        let q  = simd_quatf(transform)
        let line = String(
            format: "%06d,%.6f,%.4f,%.4f,%.4f,%.4f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
            index, timestamp, fx, fy, cx, cy, tx, ty, tz,
            q.imag.x, q.imag.y, q.imag.z, q.real
        )
        if let data = line.data(using: .utf8) {
            try? handle?.write(contentsOf: data)
        }
    }
}
