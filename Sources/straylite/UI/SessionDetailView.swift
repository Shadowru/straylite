import SwiftUI

/// Details of one session + a share button that exposes the scan folder
/// (or its zip) via the standard share sheet.
struct SessionDetailView: View {
    let session: Session
    @State private var isSharing = false
    @State private var shareURL: URL?

    var body: some View {
        Form {
            Section("Metadata") {
                LabeledContent("Name", value: session.name)
                LabeledContent("ID", value: session.id.uuidString)
                LabeledContent("Created",
                               value: session.createdAt.formatted(date: .abbreviated,
                                                                   time: .standard))
                LabeledContent("Duration", value: formatDuration(session.duration))
                LabeledContent("Walls", value: "\(session.wallCount)")
                LabeledContent("Objects", value: "\(session.objectCount)")
            }
            Section("Files") {
                if let folder = session.folderURL {
                    Text(folder.path)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                    Text("\(fileCount(at: folder)) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Folder missing").foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    if let folder = session.folderURL,
                       FileManager.default.fileExists(atPath: folder.path) {
                        shareURL = folder
                        isSharing = true
                    }
                } label: {
                    Label("Share scan folder", systemImage: "square.and.arrow.up")
                }
                .disabled(session.folderURL == nil)
            }
        }
        .navigationTitle(session.name)
        .sheet(isPresented: $isSharing) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let secs = Int(s)
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    private func fileCount(at url: URL) -> Int {
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var n = 0
        while enumerator?.nextObject() != nil { n += 1 }
        return n
    }
}

/// UIActivityViewController wrapper so SwiftUI can present the iOS share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {}
}
