import SwiftUI
import ARKit
import CoreImage

/// Lightweight ARKit camera preview that doesn't depend on RealityKit or
/// SceneKit — both of those auto-link CoreAudioTypes which is header-only
/// in the xtool/Linux SDK and fails at link time.
///
/// We just subscribe to ARSessionDelegate, convert ARFrame.capturedImage
/// to a UIImage via CIContext, and display it. No 3D, no audio.
struct ARViewContainer: View {
    @ObservedObject var coordinator: CaptureCoordinator

    var body: some View {
        // Use Color as a flexible base + Image as an overlay so the image's
        // intrinsic dimensions can't propagate up the SwiftUI layout tree
        // and warp sibling views once the first frame arrives.
        Color.black
            .overlay {
                if let img = coordinator.previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .clipped()
    }
}
