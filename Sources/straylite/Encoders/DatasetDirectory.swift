import Foundation

/// Creates and exposes a per-scan directory under the app's Documents.
/// Mirrors the Stray Scanner format (rgb.mp4 / depth/*.png / odometry.csv /
/// imu.csv) plus our additions (roomplan.usdz / roomplan.json).
struct DatasetDirectory {
    let id: UUID
    let url: URL
    let createdAt: Date

    static func make() throws -> DatasetDirectory {
        let id = UUID()
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let scans = docs.appendingPathComponent("scans", isDirectory: true)
        try FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        let dir = scans.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("rgb", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("depth", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("confidence", isDirectory: true),
            withIntermediateDirectories: true
        )
        return DatasetDirectory(id: id, url: dir, createdAt: Date())
    }

    var rgbDir:         URL { url.appendingPathComponent("rgb",        isDirectory: true) }
    var depthDir:       URL { url.appendingPathComponent("depth",      isDirectory: true) }
    var confidenceDir:  URL { url.appendingPathComponent("confidence", isDirectory: true) }
    var odometryFile:   URL { url.appendingPathComponent("odometry.csv") }
    var roomplanUSDZ:   URL { url.appendingPathComponent("roomplan.usdz") }
    var roomplanJSON:   URL { url.appendingPathComponent("roomplan.json") }
    var manifestFile:   URL { url.appendingPathComponent("manifest.json") }
}
