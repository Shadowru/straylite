import Foundation
import UIKit
import ARKit
import RoomPlan
import Combine
@preconcurrency import CoreImage

/// Owns the ARSession and the RoomCaptureSession that piggybacks on it.
/// Encoder hookups (RGB/depth/odometry) live in `session(_:didUpdate:)`.
@MainActor
final class CaptureCoordinator: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case finalising
        case finished(roomSummary: String)
        case failed(reason: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var capturedRoom: CapturedRoom?
    @Published private(set) var datasetURL: URL?
    @Published private(set) var previewImage: UIImage?

    // Live overlay signals — updated continuously while scanning.
    @Published private(set) var liveRoom: CapturedRoom?                  // every ~150ms
    @Published private(set) var latestCamera: ARCamera?                  // for projectPoint()
    @Published private(set) var coachingInstruction: String?
    @Published private(set) var lastDetectionAt: Date?                   // for "X seconds since new"
    @Published private(set) var blurScore: Double = 1.0                  // 0 = blurry, 1 = sharp
    @Published private(set) var depthCoverage: Double = 0.0              // 0..1 fraction of valid LiDAR pixels
    @Published private(set) var hasSceneDepth: Bool = false
    @Published private(set) var depthDiag: String = ""                   // why depth is missing

    private var lastCounts: (Int, Int, Int, Int) = (0, 0, 0, 0)
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // CIContext is documented as thread-safe; declared nonisolated so the
    // off-main rendering closure can use it without an actor hop.
    nonisolated private let previewContext = CIContext(options: [.useSoftwareRenderer: false])
    nonisolated private let previewQueue = DispatchQueue(label: "straylite.preview", qos: .userInitiated)
    private var previewThrottle: Int = 0
    private var previewInFlight = false

    let session = ARSession()
    private var roomCaptureSession: RoomCaptureSession?
    private var startTime: Date?
    private var tickerCancellable: AnyCancellable?

    // Encoders (created at start, finalised at stop).
    private var dataset: DatasetDirectory?
    private var rgbEncoder: RGBJPEGEncoder?
    private var depthEncoder: DepthEncoder?
    private var odometryEncoder: OdometryCSVEncoder?
    // Throttle: save every Nth frame to keep dataset size manageable
    private let frameStride = 5
    private var inboundFrameCount = 0

    // Persistence hook — injected by CaptureView so the coordinator can
    // persist a Session entity once RoomPlan finalises.
    var store: SessionsStore?
    var sessionName: String?

    override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard state == .idle else { return }
        let config = ARWorldTrackingConfiguration()
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            state = .failed(reason: "ARKit / sceneDepth not supported on this device.")
            return
        }
        // Request BOTH depth variants; ARFrame exposes whichever fires.
        // RoomCaptureSession may run its own .run(config) internally and
        // drop semantics it doesn't know about, so we re-apply ours after
        // room capture has started (see end of this method).
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // Prepare on-disk dataset folder + encoders.
        let now = Date()
        do {
            let ds = try DatasetDirectory.make()
            dataset = ds
            datasetURL = ds.url
            rgbEncoder = RGBJPEGEncoder(outDir: ds.rgbDir)
            depthEncoder = DepthEncoder(depthDir: ds.depthDir,
                                        confidenceDir: ds.confidenceDir)
            odometryEncoder = try OdometryCSVEncoder(fileURL: ds.odometryFile,
                                                    sessionStart: now)
        } catch {
            state = .failed(reason: "Could not create dataset: \(error.localizedDescription)")
            return
        }

        session.run(config)

        if RoomCaptureSession.isSupported {
            let room = RoomCaptureSession(arSession: session)
            room.delegate = self
            room.run(configuration: .init())
            self.roomCaptureSession = room

            // RoomCaptureSession internally re-runs the ARSession with its
            // own config and may strip semantics it doesn't request. Re-apply
            // ours so depth streams are still attached to each ARFrame.
            session.run(config, options: [.resetSceneReconstruction])
        }

        startTime = now
        inboundFrameCount = 0
        tickerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let t = self.startTime else { return }
                self.elapsedSeconds = Date().timeIntervalSince(t)
            }
        state = .running
    }

    func stop() {
        guard state == .running else { return }
        state = .finalising
        tickerCancellable?.cancel()
        tickerCancellable = nil
        // Stop RoomPlan first so the delegate fires while AR is still active;
        // ARSession is paused only after we receive captureSession(_:didEndWith:_:).
        roomCaptureSession?.stop(pauseARSession: false)
    }

    private func finishWith(error: String?) {
        session.pause()
        roomCaptureSession = nil

        rgbEncoder?.finish()
        depthEncoder?.finish()
        odometryEncoder?.finish()

        if let room = capturedRoom, let ds = dataset {
            RoomPlanExporter.export(room, to: ds)
            persistSession(room: room, dataset: ds)
        }

        rgbEncoder = nil
        depthEncoder = nil
        odometryEncoder = nil

        if let error {
            state = .failed(reason: error)
        } else if let room = capturedRoom {
            let summary = "\(room.walls.count) walls, \(room.objects.count) objects"
            state = .finished(roomSummary: summary)
        } else {
            state = .failed(reason: "No room data returned from RoomPlan.")
        }
    }

    private func persistSession(room: CapturedRoom, dataset: DatasetDirectory) {
        guard let store else { return }
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let session = Session(
            id: dataset.id,
            name: sessionName ?? "Scan \(dataset.createdAt.formatted(date: .abbreviated, time: .shortened))",
            createdAt: dataset.createdAt,
            duration: duration,
            wallCount: room.walls.count,
            objectCount: room.objects.count
        )
        store.add(session)
    }
}

// MARK: - RoomCaptureSessionDelegate

extension CaptureCoordinator: RoomCaptureSessionDelegate {
    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didEndWith data: CapturedRoomData,
                                    error: Error?) {
        if let error {
            Task { @MainActor in self.finishWith(error: error.localizedDescription) }
            return
        }
        Task { @MainActor in
            do {
                let room = try await RoomBuilder(options: [.beautifyObjects])
                    .capturedRoom(from: data)
                self.capturedRoom = room
                self.finishWith(error: nil)
            } catch {
                self.finishWith(error: "RoomBuilder failed: \(error.localizedDescription)")
            }
        }
    }

    // Incremental updates: fires every ~150 ms with the current room snapshot.
    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didUpdate room: CapturedRoom) {
        Task { @MainActor in self.applyLive(room: room) }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didAdd room: CapturedRoom) {
        Task { @MainActor in self.applyLive(room: room) }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didChange room: CapturedRoom) {
        Task { @MainActor in self.applyLive(room: room) }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didRemove room: CapturedRoom) {
        Task { @MainActor in self.applyLive(room: room) }
    }

    // Apple-generated coaching string: "Move closer", "Hold still", etc.
    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didProvide instruction: RoomCaptureSession.Instruction) {
        let text: String
        switch instruction {
        case .moveCloseToWall:    text = "Move closer to the wall"
        case .moveAwayFromWall:   text = "Move away from the wall"
        case .slowDown:           text = "Slow down"
        case .turnOnLight:        text = "Turn on the light"
        case .normal:             text = ""
        case .lowTexture:         text = "Low texture — face a textured surface"
        @unknown default:         text = "\(instruction)"
        }
        Task { @MainActor in
            self.coachingInstruction = text.isEmpty ? nil : text
        }
    }

    private func applyLive(room: CapturedRoom) {
        self.liveRoom = room
        let counts = (room.walls.count, room.doors.count,
                      room.windows.count, room.objects.count)
        let total = counts.0 + counts.1 + counts.2 + counts.3
        let prevTotal = lastCounts.0 + lastCounts.1 + lastCounts.2 + lastCounts.3
        if total > prevTotal {
            lastDetectionAt = Date()
            haptic.impactOccurred()
        }
        lastCounts = counts
    }
}

// MARK: - ARSessionDelegate

extension CaptureCoordinator: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let camera = frame.camera
        let smoothed = frame.smoothedSceneDepth
        let rawDepth = frame.sceneDepth
        let sd = smoothed ?? rawDepth
        let depthMap = sd?.depthMap
        let confMap = sd?.confidenceMap

        let diag: String
        if smoothed != nil && rawDepth != nil { diag = "depth: smoothed + raw" }
        else if smoothed != nil               { diag = "depth: smoothed only" }
        else if rawDepth != nil               { diag = "depth: raw only" }
        else                                  { diag = "depth: BOTH nil" }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.latestCamera = camera
            self.hasSceneDepth = (depthMap != nil)
            self.depthDiag = diag

            // Render at ~30 fps: every 2nd frame, off the main thread, with
            // a single-flight gate so back-pressure doesn't queue up.
            self.previewThrottle += 1
            if self.previewThrottle % 2 == 0 && !self.previewInFlight {
                self.previewInFlight = true
                self.renderPreview(from: pixelBuffer)
            }
            // Compute blur + depth coverage every 6th frame (~10 Hz)
            if self.previewThrottle % 6 == 0 {
                self.updateQuality(from: pixelBuffer,
                                    depth: depthMap,
                                    confidence: confMap)
            }
            guard self.state == .running else { return }
            self.inboundFrameCount += 1
            if self.inboundFrameCount % self.frameStride != 0 { return }
            self.rgbEncoder?.add(frame: frame)
            self.depthEncoder?.add(frame: frame)
            self.odometryEncoder?.add(frame: frame)
        }
    }

    /// Compute a 0..1 blur score (1 = sharp) via gradient stddev on a tiny
    /// 64×64 luma downsample, plus a 0..1 depth-coverage fraction from the
    /// confidence map.
    private func updateQuality(from buffer: CVPixelBuffer,
                                depth: CVPixelBuffer?,
                                confidence: CVPixelBuffer?) {
        // Run on the preview queue to avoid jamming main.
        previewQueue.async { [weak self] in
            guard let self else { return }
            let base = CIImage(cvPixelBuffer: buffer).applyingFilter("CIPhotoEffectMono")
            let inputScale = 64.0 / max(base.extent.width, 1)
            let ci = base.applyingFilter("CILanczosScaleTransform",
                                          parameters: ["inputScale": inputScale])
            let arr = NSMutableData(length: 64 * 64 * 4)!
            self.previewContext.render(
                ci,
                toBitmap: arr.mutableBytes,
                rowBytes: 64 * 4,
                bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            let ptr = arr.bytes.bindMemory(to: UInt8.self, capacity: 64 * 64 * 4)
            // Sobel-x abs as a quick sharpness proxy
            var acc: Double = 0
            var sq: Double = 0
            var n: Double = 0
            for y in 1..<63 {
                for x in 1..<63 {
                    let lx = Int(ptr[(y * 64 + x - 1) * 4])
                    let rx = Int(ptr[(y * 64 + x + 1) * 4])
                    let g = abs(rx - lx)
                    acc += Double(g)
                    sq += Double(g * g)
                    n += 1
                }
            }
            let mean = acc / max(n, 1)
            let variance = max(0, sq / max(n, 1) - mean * mean)
            // Empirically: variance ≥ 250 = sharp, ≤ 30 = blurry
            let sharp = min(1.0, max(0.0, (variance - 30) / 220))

            // Depth coverage: fraction of pixels with confidence > low
            var coverage = 0.0
            if let confidence {
                CVPixelBufferLockBaseAddress(confidence, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
                let w = CVPixelBufferGetWidth(confidence)
                let h = CVPixelBufferGetHeight(confidence)
                let stride = CVPixelBufferGetBytesPerRow(confidence)
                if let base = CVPixelBufferGetBaseAddress(confidence) {
                    let bytes = base.assumingMemoryBound(to: UInt8.self)
                    var ok = 0, total = 0
                    for y in 0..<h {
                        for x in 0..<w {
                            if bytes[y * stride + x] >= 1 { ok += 1 }
                            total += 1
                        }
                    }
                    coverage = total > 0 ? Double(ok) / Double(total) : 0
                }
            } else if depth == nil {
                coverage = 0
            }

            DispatchQueue.main.async {
                self.blurScore = sharp
                self.depthCoverage = coverage
            }
        }
    }

    private func renderPreview(from buffer: CVPixelBuffer) {
        previewQueue.async { [weak self] in
            guard let self else { return }
            let ci = CIImage(cvPixelBuffer: buffer).oriented(.right)
            let cg = self.previewContext.createCGImage(ci, from: ci.extent)
            let img = cg.map { UIImage(cgImage: $0) }
            DispatchQueue.main.async {
                self.previewImage = img
                self.previewInFlight = false
            }
        }
    }
}
