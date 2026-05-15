import Foundation
import Combine

/// ObservableObject persistence for sessions backed by a single JSON file
/// at Documents/sessions.json. Atomic writes, in-memory cache.
@MainActor
final class SessionsStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    private let fileURL: URL

    init() {
        let docs = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.fileURL = (docs ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("sessions.json")
        load()
    }

    func add(_ session: Session) {
        sessions.insert(session, at: 0)
        save()
    }

    func remove(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        if let folder = session.folderURL {
            try? FileManager.default.removeItem(at: folder)
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        for i in offsets.sorted(by: >) {
            let s = sessions[i]
            if let folder = s.folderURL {
                try? FileManager.default.removeItem(at: folder)
            }
            sessions.remove(at: i)
        }
        save()
    }

    // MARK: - private

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Session].self, from: data) {
            sessions = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sessions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
