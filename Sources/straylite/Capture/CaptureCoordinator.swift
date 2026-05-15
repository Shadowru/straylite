import Foundation
import UIKit
import ARKit
import RoomPlan
import Combine
import CoreImage

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

    private let previewContext = CIContext(options: [.useSoftwareRenderer: false])
    private var previewThrottle: Int = 0

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
        config.frameSemantics.insert(.sceneDepth)
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
}

// MARK: - ARSessionDelegate

extension CaptureCoordinator: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Update preview at ~6 fps regardless of recording state.
            self.previewThrottle += 1
            if self.previewThrottle % 10 == 0 {
                self.previewImage = self.makePreview(from: pixelBuffer)
            }
            guard self.state == .running else { return }
            self.inboundFrameCount += 1
            if self.inboundFrameCount % self.frameStride != 0 { return }
            self.rgbEncoder?.add(frame: frame)
            self.depthEncoder?.add(frame: frame)
            self.odometryEncoder?.add(frame: frame)
        }
    }

    private func makePreview(from buffer: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
            .oriented(.right)  // ARKit gives landscape buffers; phone is portrait
        guard let cg = previewContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
