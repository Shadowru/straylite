import SwiftUI

/// Live capture screen: AR feed + a stack of diagnostic overlays.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SessionsStore
    @StateObject private var coordinator = CaptureCoordinator()
    @State private var now = Date()

    // Driver for the "X seconds since detection" badge — refreshes 4×/sec.
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ARViewContainer(coordinator: coordinator)
                    .ignoresSafeArea()

                // 3D wireframe of detected objects, projected onto the camera feed.
                ObjectWireframeOverlay(
                    room: coordinator.liveRoom,
                    cameraTransform: coordinator.cameraTransform,
                    imageResolution: coordinator.imageResolution,
                    intrinsics: coordinator.cameraIntrinsics,
                    viewSize: geo.size
                )
                .ignoresSafeArea()

                VStack {
                    // ─── Top row ─────────────────────────────────────
                    HStack(alignment: .top) {
                        Button {
                            coordinator.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            LiveCounterView(room: coordinator.liveRoom)
                            MinimapView(room: coordinator.liveRoom,
                                        cameraTransform: coordinator.cameraTransform)
                        }
                    }
                    .padding()

                    // ─── Coaching banner (centered, just below counter) ───
                    CoachingBanner(
                        instruction: coordinator.coachingInstruction,
                        lastDetectionAt: coordinator.lastDetectionAt,
                        now: now
                    )
                    .padding(.top, -4)

                    Spacer()

                    // ─── Bottom row: quality HUD left, status pill right ──
                    HStack(alignment: .bottom) {
                        QualityHUD(
                            blurScore: coordinator.blurScore,
                            depthCoverage: coordinator.depthCoverage,
                            hasSceneDepth: coordinator.hasSceneDepth
                        )
                        Spacer()
                        Text(statusLabel)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                    .padding(.horizontal)

                    // ─── Record control ─────────────────────────────
                    VStack(spacing: 12) {
                        Text(timeLabel)
                            .font(.system(.title2, design: .monospaced))
                            .foregroundStyle(.white)
                        RecordButton(isRecording: coordinator.state == .running) {
                            switch coordinator.state {
                            case .idle:
                                coordinator.start()
                            case .running:
                                coordinator.stop()
                            case .finalising, .finished, .failed:
                                break
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            coordinator.store = store
        }
        .onReceive(clock) { date in
            now = date
        }
        .onChange(of: coordinator.state) { _, new in
            if case .finished = new {
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    dismiss()
                }
            }
        }
    }

    private var statusLabel: String {
        switch coordinator.state {
        case .idle:                       return "Ready"
        case .running:                    return "Recording…"
        case .finalising:                 return "Processing…"
        case .finished(let summary):      return summary
        case .failed(let reason):         return reason
        }
    }

    private var timeLabel: String {
        let secs = Int(coordinator.elapsedSeconds)
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}

private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                RoundedRectangle(cornerRadius: isRecording ? 6 : 36)
                    .fill(.red)
                    .frame(width: isRecording ? 32 : 60,
                           height: isRecording ? 32 : 60)
                    .animation(.spring(duration: 0.25), value: isRecording)
            }
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}
