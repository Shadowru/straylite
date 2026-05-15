import Foundation
import RoomPlan

/// Persist the final `CapturedRoom` from RoomPlan as both USDZ and JSON.
/// Safe to call on the main thread; both writes are atomic.
enum RoomPlanExporter {
    static func export(_ room: CapturedRoom, to dir: DatasetDirectory) {
        do {
            try room.export(to: dir.roomplanUSDZ, exportOptions: .parametric)
        } catch {
            print("RoomPlan USDZ export failed: \(error)")
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(room)
            try data.write(to: dir.roomplanJSON, options: .atomic)
        } catch {
            print("RoomPlan JSON export failed: \(error)")
        }
    }
}
