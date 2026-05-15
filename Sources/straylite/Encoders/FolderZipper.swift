import Foundation

/// Zips a folder into a temp .zip file suitable for UIActivityViewController.
/// Uses `NSFileCoordinator.coordinate(readingItemAt:options:.forUploading)` —
/// the same path Files.app uses when you tap "Share" on a folder.
enum FolderZipper {

    enum Error: Swift.Error {
        case noTempURL
        case coordinatorFailed(Swift.Error)
    }

    /// Synchronous (blocks until zip is produced and copied to a stable URL).
    /// Returns a URL to a .zip in the temp directory. Call from a background
    /// queue if you don't want to freeze the UI on big folders.
    static func zip(_ folder: URL, named name: String? = nil) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var copiedURL: URL?
        var caught: Swift.Error?

        coordinator.coordinate(readingItemAt: folder,
                               options: [.forUploading],
                               error: &coordError) { tempZipURL in
            // tempZipURL is valid only inside this block; copy to a stable temp
            // location so the share sheet has time to use it.
            let stableName = (name ?? folder.lastPathComponent) + ".zip"
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(stableName)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: tempZipURL, to: dest)
                copiedURL = dest
            } catch {
                caught = error
            }
        }

        if let err = caught { throw Error.coordinatorFailed(err) }
        if let err = coordError { throw Error.coordinatorFailed(err) }
        guard let url = copiedURL else { throw Error.noTempURL }
        return url
    }
}
