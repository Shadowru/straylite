import SwiftUI

/// Live capture screen. Layout (bottom-to-top after live preview):
///   - background    full-screen camera feed
///   - overlay       3D wireframes projected from RoomPlan
///   - top           close (left) + counter + minimap (right)
///   - center        coaching banner
///   - bottom-left   quality HUD
///   - bottom-right  status pill
///   - bottom        time + record button (centred horizontally)
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SessionsStore
    @StateObject private var coordinator = CaptureCoordinator()
    @State private var now = Date()

    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── live camera feed
                ARViewContainer(coordinator: coordinator)
                    .ignoresSafeArea()

                // ── 3D wireframes over the feed
                ObjectWireframeOverlay(
                    room: coordinator.liveRoom,
                    camera: coordinator.latestCamera,
                    viewSize: geo.size
                )
                .ignoresSafeArea()

                // ── HUD (in safe area so the close button isn't under the notch)
                VStack(spacing: 0) {
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
                                        camera: coordinator.latestCamera)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    CoachingBanner(
                        instruction: coordinator.coachingInstruction,
                        lastDetectionAt: coordinator.lastDetectionAt,
                        now: now
                    )
                    .padding(.top, 8)

                    Spacer()

                    HStack(alignment: .bottom) {
                        QualityHUD(
                            blurScore: coordinator.blurScore,
                            depthCoverage: coordinator.depthCoverage,
                            hasSceneDepth: coordinator.hasSceneDepth,
                            depthDiag: coordinator.depthDiag
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

                    // Record group, centered horizontally regardless of HUD widths
                    VStack(spacing: 10) {
                        Text(timeLabel)
                            .font(.system(.title2, design: .monospaced))
                            .foregroundStyle(.white)
                        RecordButton(isRecording: coordinator.state == .running) {
                            switch coordinator.state {
                            case .idle:     coordinator.start()
                            case .running:  coordinator.stop()
                            case .finalising, .finished, .failed: break
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
