import SwiftUI
import SceneKit

/// Inline SceneKit viewer that loads the captured `roomplan.usdz`. Lets the
/// user orbit the scene with one finger.
///
/// Uses bare SCNView (not ARSCNView) — the latter auto-links the audio
/// frameworks that wouldn't link cleanly on the xtool Darwin SDK.
struct Room3DPreview: UIViewRepresentable {
    let usdzURL: URL

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        if let scene = try? SCNScene(url: usdzURL, options: nil) {
            view.scene = scene
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene == nil,
           let scene = try? SCNScene(url: usdzURL, options: nil) {
            uiView.scene = scene
        }
    }
}
