import SwiftUI
import RoomPlan

/// Heuristic checks on the CapturedRoom output that warn the user to
/// reconsider a re-scan BEFORE uploading to the backend (which can take
/// several minutes of VLM time).
struct SanityWarningsView: View {
    let room: CapturedRoom

    private var warnings: [String] {
        var w: [String] = []

        // Walls: each should be 1–8m long. Multiples of small walls = L-shape.
        let lengths = room.walls.map { $0.dimensions.x }
        for (i, l) in lengths.enumerated() {
            if l < 0.8 {
                w.append("Wall #\(i): only \(String(format: "%.2f", l)) m — likely partial")
            } else if l > 8 {
                w.append("Wall #\(i): \(String(format: "%.1f", l)) m — unusually long, may be misclassified")
            }
        }

        // Room must have at least 3 walls for a proper closure
        if room.walls.count < 3 {
            w.append("Only \(room.walls.count) walls found — RoomPlan didn't close the room")
        }

        // Low-confidence walls
        let lowConfWalls = room.walls.filter { $0.confidence != .high }.count
        if lowConfWalls > 0 {
            w.append("\(lowConfWalls) wall\(lowConfWalls == 1 ? "" : "s") at medium/low confidence")
        }

        // Object size sanity
        for (i, obj) in room.objects.enumerated() {
            let d = obj.dimensions
            let minDim = min(d.x, d.y, d.z)
            let maxDim = max(d.x, d.y, d.z)
            let cat = String(describing: obj.category)
            if minDim < 0.15 {
                w.append("Object #\(i) (\(cat)): tiny \(String(format: "%.2fm", minDim)) — likely noise")
            }
            if maxDim > 4 {
                w.append("Object #\(i) (\(cat)): huge \(String(format: "%.2fm", maxDim)) — possibly merged with another")
            }
            if obj.confidence == .low {
                w.append("Object #\(i) (\(cat)) at LOW confidence — bbox may be wrong")
            }
        }

        return w
    }

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(warnings.count) sanity warning\(warnings.count == 1 ? "" : "s")",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, msg in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.orange)
                        Text(msg).font(.caption).foregroundStyle(.primary)
                    }
                }
            }
            .padding(10)
            .background(.orange.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("No sanity issues detected")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            .padding(10)
            .background(.green.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
