import SwiftUI
import simd
import RoomPlan

/// Renders the sharpest captured RGB frame with RoomPlan OBBs projected
/// onto it using the saved camera intrinsics + pose. Lets the user visually
/// verify that what RoomPlan thinks is in the room corresponds to what the
/// camera actually saw.
struct ProjectedOBBPreview: View {
    let room: CapturedRoom
    let frame: SessionDataLoader.BestFrame

    var body: some View {
        GeometryReader { geo in
            let imageAspect = frame.imageSize.width / frame.imageSize.height
            let viewWidth = geo.size.width
            let viewHeight = viewWidth / imageAspect
            let viewSize = CGSize(width: viewWidth, height: viewHeight)
            let pose = frame.pose
            let intr = frame.intrinsics
            let imgSize = frame.imageSize

            ZStack(alignment: .topLeading) {
                Image(uiImage: frame.image)
                    .resizable()
                    .frame(width: viewWidth, height: viewHeight)

                Canvas { ctx, _ in
                    let viewToCam = pose.inverse

                    func project(_ world: simd_float3) -> CGPoint? {
                        let cam4 = viewToCam * simd_float4(world.x, world.y, world.z, 1)
                        if cam4.z >= -0.05 { return nil }
                        let normalised = simd_float3(cam4.x / -cam4.z,
                                                     cam4.y / -cam4.z, 1)
                        let pixel = intr * normalised
                        let px = CGFloat(pixel.x), py = CGFloat(pixel.y)
                        if !px.isFinite || !py.isFinite { return nil }
                        return CGPoint(
                            x: px / imgSize.width  * viewSize.width,
                            y: py / imgSize.height * viewSize.height
                        )
                    }

                    for o in room.objects {
                        drawBox(o.transform, o.dimensions,
                                color: confidenceColor(o.confidence),
                                ctx: ctx, project: project)
                    }
                    for w in room.walls {
                        drawBox(w.transform, w.dimensions,
                                color: .green.opacity(0.4),
                                ctx: ctx, project: project)
                    }
                    for d in room.doors {
                        drawBox(d.transform, d.dimensions, color: .orange,
                                ctx: ctx, project: project)
                    }
                    for w in room.windows {
                        drawBox(w.transform, w.dimensions, color: .cyan,
                                ctx: ctx, project: project)
                    }
                }
                .frame(width: viewWidth, height: viewHeight)
                .allowsHitTesting(false)

                // Tag
                Text("Frame #\(frame.frameIndex)  ·  sharp \(String(format: "%.2f", frame.sharpness))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
            .frame(height: viewHeight)
        }
        .aspectRatio(frame.imageSize.width / frame.imageSize.height,
                     contentMode: .fit)
    }

    private func confidenceColor(_ c: CapturedRoom.Confidence) -> Color {
        switch c {
        case .high:   return .green
        case .medium: return .yellow
        case .low:    return .red
        @unknown default: return .white
        }
    }

    private func drawBox(_ transform: simd_float4x4,
                         _ dims: simd_float3,
                         color: Color,
                         ctx: GraphicsContext,
                         project: (simd_float3) -> CGPoint?) {
        let hx = dims.x / 2, hy = dims.y / 2, hz = dims.z / 2
        let local: [simd_float3] = [
            simd_float3(-hx, -hy, -hz), simd_float3( hx, -hy, -hz),
            simd_float3( hx,  hy, -hz), simd_float3(-hx,  hy, -hz),
            simd_float3(-hx, -hy,  hz), simd_float3( hx, -hy,  hz),
            simd_float3( hx,  hy,  hz), simd_float3(-hx,  hy,  hz),
        ]
        let pts: [CGPoint?] = local.map { p in
            let wh = transform * simd_float4(p.x, p.y, p.z, 1)
            return project(simd_float3(wh.x, wh.y, wh.z))
        }
        let edges: [(Int, Int)] = [
            (0,1),(1,2),(2,3),(3,0),
            (4,5),(5,6),(6,7),(7,4),
            (0,4),(1,5),(2,6),(3,7),
        ]
        for (a, b) in edges {
            guard let pa = pts[a], let pb = pts[b] else { continue }
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            ctx.stroke(path, with: .color(color), lineWidth: 1.2)
        }
    }
}
