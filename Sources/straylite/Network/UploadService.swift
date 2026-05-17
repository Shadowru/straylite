import Foundation

/// Multipart POST of a scan zip to /api/upload + status polling + result
/// download. URLSession-based; no third-party deps.
///
/// Usage:
///   let svc = UploadService()
///   for try await event in svc.upload(zipURL: ..., settings: AppSettings.current()) {
///       switch event {
///       case .uploading(let bytesSent, let total): …
///       case .pending:                              …
///       case .processing(let message):              …
///       case .done(let setURL):                     …  // local URL of downloaded .set
///       case .failed(let reason):                   …
///       }
///   }
final class UploadService: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    enum Event {
        case uploading(bytesSent: Int64, total: Int64)
        case pending
        case processing(message: String)
        case done(localSetURL: URL)
        case failed(reason: String)
    }

    enum UploadError: LocalizedError {
        case badServer
        case http(Int, String)
        case missingJobID
        var errorDescription: String? {
            switch self {
            case .badServer:                return "Server URL is not configured"
            case .http(let code, let body): return "HTTP \(code): \(body)"
            case .missingJobID:             return "Server response had no job_id"
            }
        }
    }

    private struct UploadResponse: Decodable {
        let job_id: String
        let status_url: String
        let download_url: String
    }

    private struct StatusResponse: Decodable {
        let status: String
        let message: String?
        let download_url: String?
    }

    private var progressContinuation: AsyncStream<Event>.Continuation?
    private var taskByID: [Int: AsyncStream<Event>.Continuation] = [:]

    /// Returns an AsyncStream that fires multiple events: upload progress,
    /// status changes during processing, and finally a `.done` with the
    /// local URL of the downloaded `.set`, or `.failed`.
    func upload(zipURL: URL, settings: AppSettings) -> AsyncStream<Event> {
        AsyncStream<Event> { continuation in
            Task.detached {
                guard settings.canUpload, let base = URL(string: settings.serverURL) else {
                    continuation.yield(.failed(reason: UploadError.badServer.localizedDescription))
                    continuation.finish()
                    return
                }
                do {
                    // 1. Upload
                    let resp = try await self.postMultipart(
                        zipURL: zipURL,
                        settings: settings,
                        base: base,
                        continuation: continuation
                    )

                    // 2. Poll status
                    while true {
                        try await Task.sleep(for: .seconds(3))
                        let st = try await self.fetchStatus(jobID: resp.job_id,
                                                            settings: settings,
                                                            base: base)
                        switch st.status {
                        case "pending":
                            continuation.yield(.pending)
                        case "processing":
                            continuation.yield(.processing(message: st.message ?? "Processing…"))
                        case "done":
                            // 3. Download .set
                            let local = try await self.downloadResult(
                                jobID: resp.job_id, settings: settings, base: base)
                            continuation.yield(.done(localSetURL: local))
                            continuation.finish()
                            return
                        case "error":
                            continuation.yield(.failed(reason: st.message ?? "Conversion failed"))
                            continuation.finish()
                            return
                        default:
                            continuation.yield(.processing(message: "Status: \(st.status)"))
                        }
                    }
                } catch {
                    continuation.yield(.failed(reason: error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - private

    private func postMultipart(zipURL: URL,
                               settings: AppSettings,
                               base: URL,
                               continuation: AsyncStream<Event>.Continuation) async throws -> UploadResponse {
        let endpoint = base.appendingPathComponent("api/upload")
        let boundary = "Boundary-\(UUID().uuidString)"

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.uploadToken)",
                     forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 600

        // Build the multipart body to a temp file so we don't keep all bytes
        // in memory (zips can be 150-300 MB).
        let bodyTmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: bodyTmp.path, contents: nil)
        let writer = try FileHandle(forWritingTo: bodyTmp)
        defer { try? writer.close(); try? FileManager.default.removeItem(at: bodyTmp) }

        func write(_ s: String) throws {
            try writer.write(contentsOf: Data(s.utf8))
        }
        // use_vlm
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"use_vlm\"\r\n\r\n\(settings.useVLM ? "true" : "false")\r\n")
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"vlm_frames\"\r\n\r\n\(settings.vlmFrames)\r\n")
        // file
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(zipURL.lastPathComponent)\"\r\nContent-Type: application/zip\r\n\r\n")
        let reader = try FileHandle(forReadingFrom: zipURL)
        defer { try? reader.close() }
        while autoreleasepool(invoking: {
            let chunk = reader.availableData
            if chunk.isEmpty { return false }
            try? writer.write(contentsOf: chunk)
            return true
        }) {}
        try write("\r\n--\(boundary)--\r\n")
        try writer.synchronize()

        let session = URLSession(configuration: .default,
                                 delegate: self,
                                 delegateQueue: nil)
        let (data, response) = try await session.upload(for: req, fromFile: bodyTmp,
                                                        delegate: self)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.http(0, "no response")
        }
        if http.statusCode != 200 {
            throw UploadError.http(http.statusCode,
                                   String(data: data, encoding: .utf8) ?? "")
        }
        guard let resp = try? JSONDecoder().decode(UploadResponse.self, from: data) else {
            throw UploadError.missingJobID
        }
        return resp
    }

    private func fetchStatus(jobID: String,
                             settings: AppSettings,
                             base: URL) async throws -> StatusResponse {
        let url = base.appendingPathComponent("api/jobs/\(jobID)")
        var req = URLRequest(url: url)
        req.setValue("Bearer \(settings.uploadToken)",
                     forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UploadError.http((response as? HTTPURLResponse)?.statusCode ?? 0,
                                   String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    private func downloadResult(jobID: String,
                                settings: AppSettings,
                                base: URL) async throws -> URL {
        let url = base.appendingPathComponent("api/jobs/\(jobID)/result")
        var req = URLRequest(url: url)
        req.setValue("Bearer \(settings.uploadToken)",
                     forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UploadError.http((response as? HTTPURLResponse)?.statusCode ?? 0,
                                   String(data: data, encoding: .utf8) ?? "")
        }
        let local = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-\(jobID).set")
        try data.write(to: local, options: .atomic)
        return local
    }

    // MARK: - URLSessionTaskDelegate (upload progress)

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        // We don't yet wire this into the AsyncStream; left as a hook for
        // future progress UI.
        _ = (totalBytesSent, totalBytesExpectedToSend)
    }
}
