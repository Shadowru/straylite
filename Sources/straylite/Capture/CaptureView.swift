import SwiftUI

/// Live capture screen: ARView fills the screen, overlay shows a record
/// button, timer, and status.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SessionsStore
    @StateObject private var coordinator = CaptureCoordinator()

    var body: some View {
        ZStack {
            ARViewContainer(coordinator: coordinator)
                .ignoresSafeArea()

            VStack {
                // Top: dismiss + status text
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
                    Text(statusLabel)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .padding()

                Spacer()

                // Bottom: timer + record button
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
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            coordinator.store = store
        }
        .onChange(of: coordinator.state) { _, new in
            if case .finished = new {
                // Auto-dismiss after a short delay; future: navigate to detail
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
