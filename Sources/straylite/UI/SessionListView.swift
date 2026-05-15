import SwiftUI

/// Lists historic Session entities sorted by newest first. Tap a row to see
/// details and share the dataset folder.
struct SessionListView: View {
    @EnvironmentObject private var store: SessionsStore

    var body: some View {
        Group {
            if store.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No scans yet", systemImage: "shippingbox")
                } description: {
                    Text("Tap the + button to record your first room scan.")
                }
            } else {
                List {
                    ForEach(store.sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                    }
                    .onDelete { offsets in
                        store.remove(at: offsets)
                    }
                }
            }
        }
    }

    private func sessionRow(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.name).font(.headline)
            HStack(spacing: 8) {
                Label(s.createdAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                Label(formatDuration(s.duration),
                      systemImage: "stopwatch")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label("\(s.wallCount) walls", systemImage: "square.split.bottomrightquarter")
                Label("\(s.objectCount) objects", systemImage: "cube")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let secs = Int(s)
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}
