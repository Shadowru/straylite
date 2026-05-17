import SwiftUI
import RoomPlan

/// Details of one session with on-device previews of the captured room
/// before upload: 2D floor plan, structured item list, sanity warnings,
/// 3D SceneKit viewer, and a projected-OBB overlay on the sharpest frame.
struct SessionDetailView: View {
    let session: Session

    @State private var loaded: SessionDataLoader.Loaded?
    @State private var isLoadingScan = true

    // Upload state
    @State private var isUploading = false
    @State private var uploadProgress: String?
    @State private var uploadResultURL: URL?
    @State private var uploadError: String?

    // Share state
    @State private var isSharing = false
    @State private var shareURL: URL?
    @State private var isZipping = false
    @State private var zipError: String?

    var body: some View {
        Form {
            metadataSection
            if isLoadingScan {
                Section { ProgressView("Loading scan data…") }
            } else {
                if let room = loaded?.room {
                    sanitySection(room: room)
                    floorPlanSection(room: room)
                    room3DSection
                    itemListSection(room: room)
                    if let frame = loaded?.bestFrame {
                        projectedSection(room: room, frame: frame)
                    }
                }
                uploadSection
                shareSection
            }
        }
        .navigationTitle(session.name)
        .sheet(isPresented: $isSharing) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .task {
            guard let folder = session.folderURL else { isLoadingScan = false; return }
            loaded = await SessionDataLoader.load(folder: folder)
            isLoadingScan = false
        }
    }

    // MARK: - Sections

    private var metadataSection: some View {
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
    }

    private func sanitySection(room: CapturedRoom) -> some View {
        Section {
            SanityWarningsView(room: room)
        }
    }

    private func floorPlanSection(room: CapturedRoom) -> some View {
        Section("Floor plan") {
            FloorPlanView(room: room)
                .frame(height: 240)
        }
    }

    @ViewBuilder
    private var room3DSection: some View {
        if let folder = session.folderURL {
            let usdz = folder.appendingPathComponent("roomplan.usdz")
            if FileManager.default.fileExists(atPath: usdz.path) {
                Section("3D preview") {
                    Room3DPreview(usdzURL: usdz)
                        .frame(height: 280)
                        .background(.black,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func itemListSection(room: CapturedRoom) -> some View {
        Section("Detected items") {
            RoomItemListView(room: room)
        }
    }

    private func projectedSection(room: CapturedRoom,
                                  frame: SessionDataLoader.BestFrame) -> some View {
        Section("Projected OBBs on key frame") {
            ProjectedOBBPreview(room: room, frame: frame)
        }
    }

    private var uploadSection: some View {
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
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text("Configure server URL + token in Settings to upload directly.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var shareSection: some View {
        Section("Share") {
            Button {
                shareAsZip()
            } label: {
                HStack {
                    if isZipping {
                        ProgressView().controlSize(.small).padding(.trailing, 4)
                        Text("Zipping…")
                    } else {
                        Label("Share scan (.zip)", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .disabled(session.folderURL == nil || isZipping)
            if let err = zipError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

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
