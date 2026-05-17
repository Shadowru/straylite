import SwiftUI
import simd
import ARKit
import RoomPlan

// MARK: - Live counter HUD

/// Small badge in the top-right showing live RoomPlan counts.
struct LiveCounterView: View {
    let room: CapturedRoom?

    var body: some View {
        let w = room?.walls.count ?? 0
        let d = room?.doors.count ?? 0
        let win = room?.windows.count ?? 0
        let obj = room?.objects.count ?? 0

        VStack(alignment: .leading, spacing: 2) {
            row("Walls",   w,   "square.split.bottomrightquarter")
            row("Doors",   d,   "door.left.hand.open")
            row("Windows", win, "window.vertical.open")
            row("Objects", obj, "cube")
        }
        .font(.system(size: 12, design: .rounded).monospacedDigit())
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ label: String, _ n: Int, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).frame(width: 14)
            Text("\(label)")
            Spacer(minLength: 6)
            Text("\(n)").bold().foregroundStyle(n > 0 ? .green : .white.opacity(0.8))
        }
        .frame(width: 110, alignment: .leading)
    }
}

// MARK: - Coaching banner

/// Apple-generated RoomCaptureSession.Instruction string plus a "seconds
/// since last new detection" hint when the scan stalls.
struct CoachingBanner: View {
    let instruction: String?
    let lastDetectionAt: Date?
    let now: Date

    var body: some View {
        let stale = secondsSinceDetection
        let label: String
        let color: Color
        if let inst = instruction, !inst.isEmpty {
            label = inst
            color = .yellow
        } else if let stale, stale > 6 {
            label = "Nothing new for \(Int(stale)) s — try a different angle"
            color = .orange
        } else if let stale, stale > 0, lastDetectionAt != nil {
            label = "Last detection: \(Int(stale)) s ago"
            color = .white
        } else {
            label = ""
            color = .white
        }

        return Group {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
    }

    private var secondsSinceDetection: TimeInterval? {
        guard let lastDetectionAt else { return nil }
        return now.timeIntervalSince(lastDetectionAt)
    }
}

// MARK: - Top-down minimap

/// 2D top-down minimap. Walls = green lines, objects = small rectangles,
/// camera = triangle pointing at heading.
struct MinimapView: View {
    let room: CapturedRoom?
    let camera: ARCamera?
    let size: CGFloat = 100

    private var cameraTransform: simd_float4x4 {
        camera?.transform ?? matrix_identity_float4x4
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            guard let r = room else { return }
            // Collect everything in world XZ plane.
            var allPoints: [CGPoint] = []
            for w in r.walls + r.doors + r.windows + r.openings {
                let p = CGPoint(x: CGFloat(w.transform.columns.3.x),
                                y: CGFloat(w.transform.columns.3.z))
                allPoints.append(p)
            }
            for o in r.objects {
                allPoints.append(CGPoint(x: CGFloat(o.transform.columns.3.x),
                                         y: CGFloat(o.transform.columns.3.z)))
            }
            let cam = CGPoint(x: CGFloat(cameraTransform.columns.3.x),
                              y: CGFloat(cameraTransform.columns.3.z))
            allPoints.append(cam)
            guard allPoints.count > 1 else { return }

            let xs = allPoints.map(\.x)
            let zs = allPoints.map(\.y)
            let minX = xs.min()!, maxX = xs.max()!
            let minZ = zs.min()!, maxZ = zs.max()!
            let pad: CGFloat = 6
            let spanX = max(0.001, maxX - minX)
            let spanZ = max(0.001, maxZ - minZ)
            let scaleX = (canvasSize.width  - 2 * pad) / spanX
            let scaleZ = (canvasSize.height - 2 * pad) / spanZ
            let scale = min(scaleX, scaleZ)

            func project(_ p: CGPoint) -> CGPoint {
                CGPoint(x: pad + (p.x - minX) * scale,
                        y: pad + (p.y - minZ) * scale)
            }

            // Walls as thick green lines along their X axis
            for w in r.walls {
                let center = CGPoint(x: CGFloat(w.transform.columns.3.x),
                                     y: CGFloat(w.transform.columns.3.z))
                let dim = w.dimensions
                let half = CGFloat(dim.x) / 2
                // Wall extends along its local X axis; xform.col 0 is that axis.
                let xAxis = w.transform.columns.0
                let dirX = CGFloat(xAxis.x)
                let dirZ = CGFloat(xAxis.z)
                let p1 = CGPoint(x: center.x - dirX * half,
                                 y: center.y - dirZ * half)
                let p2 = CGPoint(x: center.x + dirX * half,
                                 y: center.y + dirZ * half)
                var path = Path()
                path.move(to: project(p1))
                path.addLine(to: project(p2))
                ctx.stroke(path, with: .color(.green), lineWidth: 2)
            }
            // Doors orange, windows blue
            for d in r.doors {
                drawSegment(ctx: ctx, item: d, scale: scale, minX: minX, minZ: minZ,
                            pad: pad, color: .orange)
            }
            for w in r.windows {
                drawSegment(ctx: ctx, item: w, scale: scale, minX: minX, minZ: minZ,
                            pad: pad, color: .cyan)
            }
            // Objects as tiny squares
            for o in r.objects {
                let p = project(CGPoint(x: CGFloat(o.transform.columns.3.x),
                                        y: CGFloat(o.transform.columns.3.z)))
                let rect = CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)
                ctx.fill(Path(rect), with: .color(.yellow))
            }
            // Camera as a triangle pointing forward (-Z world axis after rotation)
            let camP = project(cam)
            let forward = cameraTransform.columns.2
            let angle = atan2(-Double(forward.x), -Double(forward.z))  // top-down 'up' = -Z
            ctx.translateBy(x: camP.x, y: camP.y)
            ctx.rotate(by: .radians(angle))
            var tri = Path()
            tri.move(to: CGPoint(x: 0, y: -5))
            tri.addLine(to: CGPoint(x: 4, y: 5))
            tri.addLine(to: CGPoint(x: -4, y: 5))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(.white))
            ctx.stroke(tri, with: .color(.blue), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func drawSegment(ctx: GraphicsContext,
                             item: CapturedRoom.Surface,
                             scale: CGFloat, minX: CGFloat, minZ: CGFloat,
                             pad: CGFloat, color: Color) {
        let center = CGPoint(x: CGFloat(item.transform.columns.3.x),
                             y: CGFloat(item.transform.columns.3.z))
        let half = CGFloat(item.dimensions.x) / 2
        let xAxis = item.transform.columns.0
        let dirX = CGFloat(xAxis.x), dirZ = CGFloat(xAxis.z)
        var path = Path()
        path.move(to: CGPoint(x: pad + (center.x - dirX * half - minX) * scale,
                              y: pad + (center.y - dirZ * half - minZ) * scale))
        path.addLine(to: CGPoint(x: pad + (center.x + dirX * half - minX) * scale,
                                  y: pad + (center.y + dirZ * half - minZ) * scale))
        ctx.stroke(path, with: .color(color), lineWidth: 3)
    }
}

// MARK: - 3D bbox wireframe over the camera feed

/// Projects 8 OBB corners of every detected RoomPlan object into the
/// current camera view and draws a wireframe. Colour by confidence.
struct ObjectWireframeOverlay: View {
    let room: CapturedRoom?
    let camera: ARCamera?
    let viewSize: CGSize

    var body: some View {
        Canvas { ctx, _ in
            guard let r = room, let cam = camera,
                  viewSize.width > 0, viewSize.height > 0 else { return }

            // Apple-supplied projection: handles orientation, fov, distortion.
            // Returns CGPoint(NaN, NaN) for points outside the visible frustum.
            func project(_ world: simd_float3) -> CGPoint? {
                let p = cam.projectPoint(world,
                                         orientation: .portrait,
                                         viewportSize: viewSize)
                if p.x.isNaN || p.y.isNaN { return nil }
                return p
            }

            for o in r.objects {
                drawBox(o.transform, o.dimensions,
                        color: confidenceColor(o.confidence),
                        ctx: ctx, project: project)
            }
            for w in r.walls {
                drawBox(w.transform, w.dimensions,
                        color: .green.opacity(0.45),
                        ctx: ctx, project: project)
            }
            for d in r.doors {
                drawBox(d.transform, d.dimensions, color: .orange,
                        ctx: ctx, project: project)
            }
            for w in r.windows {
                drawBox(w.transform, w.dimensions, color: .cyan,
                        ctx: ctx, project: project)
            }
        }
        .allowsHitTesting(false)
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
        let world: [CGPoint?] = local.map { p in
            let wh = transform * simd_float4(p.x, p.y, p.z, 1)
            return project(simd_float3(wh.x, wh.y, wh.z))
        }
        // 12 edges
        let edges: [(Int, Int)] = [
            (0,1),(1,2),(2,3),(3,0),   // back face
            (4,5),(5,6),(6,7),(7,4),   // front face
            (0,4),(1,5),(2,6),(3,7),   // connectors
        ]
        for (a, b) in edges {
            guard let pa = world[a], let pb = world[b] else { continue }
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            ctx.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }
}

// MARK: - Quality HUD (blur + depth coverage)

struct QualityHUD: View {
    let blurScore: Double           // 0..1
    let depthCoverage: Double       // 0..1
    let hasSceneDepth: Bool
    let depthDiag: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            qualityRow(label: "Sharpness", value: blurScore,
                       icon: "camera.metering.spot")
            qualityRow(label: "Depth",
                       value: hasSceneDepth ? depthCoverage : 0,
                       icon: hasSceneDepth ? "cube.transparent" : "exclamationmark.triangle")
            if !depthDiag.isEmpty {
                Text(depthDiag)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(hasSceneDepth ? .green : .orange)
            }
        }
        .font(.system(size: 11, design: .rounded).monospacedDigit())
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func qualityRow(label: String, value: Double, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).frame(width: 14)
            Text(label)
            Spacer(minLength: 4)
            // Tiny bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(barColor(value))
                        .frame(width: max(2, geo.size.width * CGFloat(value)))
                }
            }
            .frame(width: 56, height: 5)
        }
        .frame(width: 130, alignment: .leading)
    }

    private func barColor(_ v: Double) -> Color {
        if v < 0.3 { return .red }
        if v < 0.7 { return .yellow }
        return .green
    }
}

// MARK: - Depth heatmap (toggleable, full-screen)

/// Renders the LiDAR depth map as a coloured overlay aligned with the
/// live preview. Optional; toggled by a button in CaptureView.
struct DepthHeatmap: View {
    let coordinator: CaptureCoordinator
    @State private var image: UIImage?
    @State private var timer: Timer?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.55)
                    .blendMode(.screen)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                Task { @MainActor in
                    image = await Self.render(coordinator: coordinator)
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private static func render(coordinator: CaptureCoordinator) async -> UIImage? {
        // Need access to the latest ARFrame; for simplicity we cheat and use
        // coordinator.previewImage as fallback — proper implementation would
        // expose the raw depth. Phase 2.
        nil
    }
}
