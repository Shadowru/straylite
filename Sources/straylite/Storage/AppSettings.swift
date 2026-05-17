import Foundation
import Combine

/// User-tunable settings persisted in UserDefaults. Backed by @AppStorage
/// in SwiftUI views, exposed here too as a snapshot for non-View callers
/// (e.g. UploadService).
enum SettingsKey {
    static let serverURL = "serverURL"
    static let uploadToken = "uploadToken"
    static let useVLM = "useVLM"
    static let vlmFrames = "vlmFrames"
    static let hapticsEnabled = "hapticsEnabled"
}

struct AppSettings {
    let serverURL: String
    let uploadToken: String
    let useVLM: Bool
    let vlmFrames: Int
    let hapticsEnabled: Bool

    static func current() -> AppSettings {
        let d = UserDefaults.standard
        return AppSettings(
            serverURL:   d.string(forKey: SettingsKey.serverURL)   ?? "",
            uploadToken: d.string(forKey: SettingsKey.uploadToken) ?? "",
            useVLM:      d.object(forKey: SettingsKey.useVLM) as? Bool ?? true,
            vlmFrames:   max(1, d.integer(forKey: SettingsKey.vlmFrames) == 0
                                ? 3
                                : d.integer(forKey: SettingsKey.vlmFrames)),
            hapticsEnabled: d.object(forKey: SettingsKey.hapticsEnabled) as? Bool ?? false
        )
    }

    /// Convenience: server is "ready" only when URL + token are both set.
    var canUpload: Bool {
        guard !serverURL.isEmpty, !uploadToken.isEmpty else { return false }
        return URL(string: serverURL) != nil
    }
}
