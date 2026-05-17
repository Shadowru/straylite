import SwiftUI

/// Details of one session + a share button that exposes the scan folder
/// (or its zip) via the standard share sheet.
struct SessionDetailView: View {
    let session: Session
    @State private var isSharing = false
    @State private var shareURL: URL?
    @State private var isZipping = false
    @State private var zipError: String?

    // Upload state
    @State private var isUploading = false
    @State private var uploadProgress: String?
    @State private var uploadResultURL: URL?
    @State private var uploadError: String?

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
            Section("Upload") {
                let settings = AppSettings.current()
                if settings.canUpload {
                    Button {
                        uploadToServer(settings: settings)
                    } label: {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text(uploadProgress ?? "Working…")
                            } else {
                                Label("Upload to backend", systemImage: "icloud.and.arrow.up")
                            }
                        }
                    }
                    .disabled(session.folderURL == nil || isUploading)
                    Text("Server: \(settings.serverURL)")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let url = uploadResultURL {
                        Button {
                            shareURL = url
                            isSharing = true
                        } label: {
                            Label("Share returned .set", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let err = uploadError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Configure server URL + token in Settings to upload directly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Share") {
                Button {
                    shareAsZip()
                } label: {
                    HStack {
                        if isZipping {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text("Zipping…")
                        } else {
                            Label("Share scan (.zip)", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .disabled(session.folderURL == nil || isZipping)
                if let err = zipError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(session.name)
        .sheet(isPresented: $isSharing) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func uploadToServer(settings: AppSettings) {
        guard let folder = session.folderURL,
              FileManager.default.fileExists(atPath: folder.path) else { return }
        isUploading = true
        uploadProgress = "Zipping…"
        uploadError = nil
        uploadResultURL = nil
        let zipName = session.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
        Task.detached {
            do {
                let zip = try FolderZipper.zip(folder, named: zipName)
                await MainActor.run { uploadProgress = "Uploading…" }
                let service = UploadService()
                for await event in service.upload(zipURL: zip, settings: settings) {
                    switch event {
                    case .uploading(let sent, let total):
                        let mb = Double(sent) / 1_048_576
                        let totMb = Double(total) / 1_048_576
                        let pct = total > 0 ? Int(100 * Double(sent) / Double(total)) : 0
                        await MainActor.run {
                            uploadProgress = String(format: "Uploading %d%% (%.1f / %.1f MB)",
                                                    pct, mb, totMb)
                        }
                    case .pending:
                        await MainActor.run { uploadProgress = "Queued on server…" }
                    case .processing(let message):
                        await MainActor.run { uploadProgress = message }
                    case .done(let localURL):
                        await MainActor.run {
                            isUploading = false
                            uploadResultURL = localURL
                            uploadProgress = nil
                        }
                    case .failed(let reason):
                        await MainActor.run {
                            isUploading = false
                            uploadError = reason
                            uploadProgress = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadError = "Zip failed: \(error.localizedDescription)"
                    uploadProgress = nil
                }
            }
        }
    }

    private func shareAsZip() {
        guard let folder = session.folderURL,
              FileManager.default.fileExists(atPath: folder.path) else { return }
        isZipping = true
        zipError = nil
        let zipName = session.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
        Task.detached {
            do {
                let url = try FolderZipper.zip(folder, named: zipName)
                await MainActor.run {
                    shareURL = url
                    isZipping = false
                    isSharing = true
                }
            } catch {
                await MainActor.run {
                    isZipping = false
                    zipError = "Zip failed: \(error.localizedDescription)"
                }
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
