import Foundation

/// One recorded scan. Plain Codable struct — SwiftData's @Model macro
/// doesn't fully expand on the Linux Swift toolchain (xtool path), so we
/// persist via a JSON file managed by SessionsStore.
struct Session: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    let duration: TimeInterval
    let wallCount: Int
    let objectCount: Int

    /// URL of the scan folder under Documents/scans/<UUID>.
    var folderURL: URL? {
        let fm = FileManager.default
        guard let docs = try? fm.url(for: .documentDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: false) else { return nil }
        return docs.appendingPathComponent("scans", isDirectory: true)
                   .appendingPathComponent(id.uuidString, isDirectory: true)
    }
}
