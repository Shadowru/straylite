import Foundation
import UIKit
import simd
import RoomPlan

/// Lazily reads the contents of a finished scan from disk so SessionDetailView
/// can render previews without keeping anything in memory between sessions.
enum SessionDataLoader {

    /// Camera intrinsics + pose + image for a single recorded frame, used
    /// for the "projected OBBs over a key frame" preview.
    struct BestFrame {
        let image: UIImage
        let frameIndex: Int
        let pose: simd_float4x4
        let intrinsics: simd_float3x3
        let imageSize: CGSize          // landscape buffer size, e.g. 1920×1440
        let sharpness: Double
    }

    struct Loaded {
        let room: CapturedRoom?
        let bestFrame: BestFrame?
    }

    static func load(folder: URL) async -> Loaded {
        async let room = loadRoom(folder: folder)
        async let frame = loadBestFrame(folder: folder)
        return await Loaded(room: room, bestFrame: frame)
    }

    // MARK: - room

    private static func loadRoom(folder: URL) async -> CapturedRoom? {
        let url = folder.appendingPathComponent("roomplan.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CapturedRoom.self, from: data)
    }

    // MARK: - best frame (highest sharpness, or middle of odometry if no score)

    private static func loadBestFrame(folder: URL) async -> BestFrame? {
        let odoURL = folder.appendingPathComponent("odometry.csv")
        guard let csv = try? String(contentsOf: odoURL, encoding: .utf8) else { return nil }
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }

        let header = lines[0].components(separatedBy: ",")
        let sharpCol = header.firstIndex(of: "sharpness")
        // Schema: frame,timestamp,fx,fy,cx,cy,x,y,z,qx,qy,qz,qw[,sharpness]
        // Each parsed row is an array of (column-name → value).
        struct Row { let index: Int; let fields: [Double] }
        var rows: [Row] = []
        for line in lines.dropFirst() {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 13,
                  let idx = Int(parts[0]) else { continue }
            let nums = parts.dropFirst().map { Double($0) ?? .nan }
            rows.append(Row(index: idx, fields: Array(nums)))
        }
        guard !rows.isEmpty else { return nil }

        let chosen: Row
        if let sharpCol, sharpCol > 0 {
            let scoreIdx = sharpCol - 1  // we dropped `frame`
            let scored = rows.filter {
                $0.fields.count > scoreIdx && $0.fields[scoreIdx].isFinite
            }
            if let best = scored.max(by: { $0.fields[scoreIdx] < $1.fields[scoreIdx] }) {
                chosen = best
            } else {
                chosen = rows[rows.count / 2]
            }
        } else {
            chosen = rows[rows.count / 2]
        }

        // Load the JPG file. Filename pattern is %06d.jpg (RGBJPEGEncoder).
        let rgbDir = folder.appendingPathComponent("rgb")
        let frameURL = rgbDir.appendingPathComponent(String(format: "%06d.jpg",
                                                            chosen.index))
        guard let img = UIImage(contentsOfFile: frameURL.path) else { return nil }

        // Reconstruct intrinsics + pose from CSV (in landscape buffer coords).
        let f = chosen.fields
        // Layout (after dropping frame): ts, fx, fy, cx, cy, x, y, z, qx, qy, qz, qw [, sharpness]
        guard f.count >= 12 else { return nil }
        let fx = Float(f[1]), fy = Float(f[2])
        let cx = Float(f[3]), cy = Float(f[4])
        // simd_float3x3 takes columns
        let intr = simd_float3x3(
            simd_float3(fx, 0, 0),
            simd_float3(0, fy, 0),
            simd_float3(cx, cy, 1)
        )
        let tx = Float(f[5]), ty = Float(f[6]), tz = Float(f[7])
        let qx = Float(f[8]), qy = Float(f[9]), qz = Float(f[10]), qw = Float(f[11])
        let quat = simd_quatf(ix: qx, iy: qy, iz: qz, r: qw)
        var pose = simd_matrix4x4(quat)
        pose.columns.3 = simd_float4(tx, ty, tz, 1)

        let sharp = (sharpCol != nil && f.count > sharpCol! - 1)
            ? f[sharpCol! - 1] : .nan

        // Buffer is landscape — its full pixel resolution comes from intrinsics
        // (cx/cy ≈ half of W/H). Use UIImage size directly; CIImage save was
        // unrotated so UIImage.size matches buffer size.
        return BestFrame(
            image: img,
            frameIndex: chosen.index,
            pose: pose,
            intrinsics: intr,
            imageSize: img.size,
            sharpness: sharp
        )
    }
}
