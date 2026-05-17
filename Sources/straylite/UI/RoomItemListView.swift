import SwiftUI
import RoomPlan

/// Structured breakdown of every RoomPlan element: counts per category,
/// confidence per item, dimensions. Read straight from CapturedRoom.
struct RoomItemListView: View {
    let room: CapturedRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            wallRow
            portalRows
            if !room.objects.isEmpty {
                Text("Objects (\(room.objects.count))")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(Array(grouped(room.objects).enumerated()), id: \.offset) { _, group in
                    objectGroupRow(name: group.name, items: group.items)
                }
            }
        }
    }

    private var wallRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.split.bottomrightquarter")
                .foregroundStyle(.green)
                .frame(width: 18)
            Text("\(room.walls.count) walls")
                .font(.headline)
            Spacer()
            confidenceSummary(room.walls.map(\.confidence))
        }
    }

    @ViewBuilder
    private var portalRows: some View {
        if !room.doors.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "door.left.hand.open")
                    .foregroundStyle(.orange).frame(width: 18)
                Text("\(room.doors.count) door\(room.doors.count == 1 ? "" : "s")")
                Spacer()
                confidenceSummary(room.doors.map(\.confidence))
            }
        }
        if !room.windows.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "window.vertical.open")
                    .foregroundStyle(.cyan).frame(width: 18)
                Text("\(room.windows.count) window\(room.windows.count == 1 ? "" : "s")")
                Spacer()
                confidenceSummary(room.windows.map(\.confidence))
            }
        }
        if !room.openings.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.3x1")
                    .foregroundStyle(.yellow).frame(width: 18)
                Text("\(room.openings.count) opening\(room.openings.count == 1 ? "" : "s")")
                Spacer()
                confidenceSummary(room.openings.map(\.confidence))
            }
        }
    }

    private func objectGroupRow(name: String, items: [CapturedRoom.Object]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: iconFor(category: name))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text("\(items.count) × \(name)")
                Spacer()
                confidenceSummary(items.map(\.confidence))
            }
            // Show dim ranges
            let widths = items.map { Double($0.dimensions.x) }
            let heights = items.map { Double($0.dimensions.y) }
            let depths = items.map { Double($0.dimensions.z) }
            Text(String(format: "%.2f–%.2f × %.2f–%.2f × %.2f–%.2f m",
                        widths.min() ?? 0, widths.max() ?? 0,
                        heights.min() ?? 0, heights.max() ?? 0,
                        depths.min() ?? 0, depths.max() ?? 0))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.leading, 26)
        }
    }

    // MARK: - helpers

    private struct Group {
        let name: String
        let items: [CapturedRoom.Object]
    }

    private func grouped(_ items: [CapturedRoom.Object]) -> [Group] {
        let byCat = Dictionary(grouping: items) { String(describing: $0.category) }
        return byCat.map { Group(name: $0.key, items: $0.value) }
            .sorted { $0.items.count > $1.items.count }
    }

    private func confidenceSummary(_ confs: [CapturedRoom.Confidence]) -> some View {
        let high = confs.filter { $0 == .high }.count
        let med = confs.filter { $0 == .medium }.count
        let low = confs.filter { $0 == .low }.count
        return HStack(spacing: 4) {
            if high > 0 { pill("\(high)", .green) }
            if med  > 0 { pill("\(med)",  .yellow) }
            if low  > 0 { pill("\(low)",  .red) }
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private func iconFor(category: String) -> String {
        switch category {
        case "chair":         return "chair"
        case "table",
             "diningTable":   return "table.furniture"
        case "sofa":          return "sofa"
        case "bed":           return "bed.double"
        case "storage":       return "archivebox"
        case "refrigerator":  return "refrigerator"
        case "sink":          return "drop"
        case "toilet":        return "toilet"
        case "bathtub":       return "bathtub"
        case "television":    return "tv"
        case "fireplace":     return "flame"
        case "stairs":        return "stairs"
        case "oven":          return "oven"
        case "dishwasher":    return "dishwasher"
        case "washerDryer":   return "washer"
        default:               return "cube"
        }
    }
}
