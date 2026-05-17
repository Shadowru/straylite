import SwiftUI

/// Two-layer composition:
///   * HUD layer  — a VStack/HStack respecting the safe area, this is the
///                  primary content driving the layout pass.
///   * Background — camera feed + wireframe overlay, fed via .background()
///                  so its image intrinsic sizes can't propagate up the
///                  layout tree and shove HUD pieces around.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SessionsStore
    @StateObject private var coordinator = CaptureCoordinator()
    @State private var now = Date()

    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // ── Top row: close (left) + spacer + HUD column (right) ──
            HStack(alignment: .top) {
                Button {
                    coordinator.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    LiveCounterView(room: coordinator.liveRoom)
                    QualityHUD(
                        blurScore: coordinator.blurScore,
                        depthCoverage: coordinator.depthCoverage,
                        hasSceneDepth: coordinator.hasSceneDepth
                    )
                    MinimapView(room: coordinator.liveRoom,
                                camera: coordinator.latestCamera)
                }
                .fixedSize(horizontal: true, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            CoachingBanner(
                instruction: coordinator.coachingInstruction,
                lastDetectionAt: coordinator.lastDetectionAt,
                now: now
            )
            .padding(.top, 6)

            Spacer(minLength: 0)

            // ── Bottom: status + time + record (centred horizontally) ──
            VStack(spacing: 8) {
                Text(statusLabel)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                Text(timeLabel)
                    .font(.system(.title3, design: .monospaced))
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
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Camera + wireframes go BEHIND the HUD via background. Their image
        // intrinsic dimensions don't escape into the HUD layout pass.
        .background {
            ZStack {
                ARViewContainer(coordinator: coordinator)
                ObjectWireframeOverlay(
                    room: coordinator.liveRoom,
                    camera: coordinator.latestCamera
                )
            }
            .ignoresSafeArea()
        }
        .onAppear { coordinator.store = store }
        .onReceive(clock) { date in now = date }
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
                    .frame(width: 64, height: 64)
                RoundedRectangle(cornerRadius: isRecording ? 6 : 32)
                    .fill(.red)
                    .frame(width: isRecording ? 28 : 52,
                           height: isRecording ? 28 : 52)
                    .animation(.spring(duration: 0.25), value: isRecording)
            }
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}
