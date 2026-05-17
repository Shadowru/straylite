import SwiftUI

/// Live capture screen with the diagnostics consolidated into a single
/// compact top-right column, leaving the bottom for the timer + record
/// button. This avoids the bottom-edge overflow seen on smaller phones.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SessionsStore
    @StateObject private var coordinator = CaptureCoordinator()
    @State private var now = Date()

    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ARViewContainer(coordinator: coordinator)
                    .ignoresSafeArea()
                ObjectWireframeOverlay(
                    room: coordinator.liveRoom,
                    camera: coordinator.latestCamera,
                    viewSize: geo.size
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Top row: close (left) | HUD column (right) ──
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
                        // Constrain so liveRoom updates can't grow this column
                        // past the right edge.
                        .fixedSize(horizontal: true, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    // Coaching banner on its own row, centred.
                    CoachingBanner(
                        instruction: coordinator.coachingInstruction,
                        lastDetectionAt: coordinator.lastDetectionAt,
                        now: now
                    )
                    .padding(.top, 6)

                    Spacer(minLength: 0)

                    // ── Bottom: status pill + time + record ──
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
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
