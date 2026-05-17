import SwiftUI
import simd
import RoomPlan

/// Top-down 2D floor plan of a captured room — the same drawing logic as the
/// in-scan minimap, scaled up for the detail view.
struct FloorPlanView: View {
    let room: CapturedRoom

    var body: some View {
        Canvas { ctx, size in
            // Collect points to derive view extents.
            var pts: [CGPoint] = []
            for s in room.walls + room.doors + room.windows + room.openings {
                pts.append(CGPoint(x: CGFloat(s.transform.columns.3.x),
                                   y: CGFloat(s.transform.columns.3.z)))
            }
            for o in room.objects {
                pts.append(CGPoint(x: CGFloat(o.transform.columns.3.x),
                                   y: CGFloat(o.transform.columns.3.z)))
            }
            guard pts.count > 1 else { return }
            let xs = pts.map(\.x), zs = pts.map(\.y)
            let minX = xs.min()!, maxX = xs.max()!
            let minZ = zs.min()!, maxZ = zs.max()!
            let pad: CGFloat = 18
            let spanX = max(0.5, maxX - minX)
            let spanZ = max(0.5, maxZ - minZ)
            let scale = min((size.width - 2 * pad) / spanX,
                            (size.height - 2 * pad) / spanZ)
            func project(_ p: CGPoint) -> CGPoint {
                CGPoint(x: pad + (p.x - minX) * scale,
                        y: pad + (p.y - minZ) * scale)
            }

            // Walls (heavy green lines)
            for w in room.walls {
                segmentPath(item: w, project: project, ctx: ctx,
                            color: confidenceColor(w.confidence),
                            lineWidth: 4)
            }
            // Doors / windows / openings
            for d in room.doors {
                segmentPath(item: d, project: project, ctx: ctx,
                            color: .orange, lineWidth: 3)
            }
            for w in room.windows {
                segmentPath(item: w, project: project, ctx: ctx,
                            color: .cyan, lineWidth: 3)
            }
            for o in room.openings {
                segmentPath(item: o, project: project, ctx: ctx,
                            color: .yellow, lineWidth: 2)
            }

            // Objects as labelled rectangles
            for obj in room.objects {
                let center = CGPoint(x: CGFloat(obj.transform.columns.3.x),
                                     y: CGFloat(obj.transform.columns.3.z))
                let p = project(center)
                let halfW = CGFloat(obj.dimensions.x) / 2 * scale
                let halfD = CGFloat(obj.dimensions.z) / 2 * scale
                // Apply yaw from transform.col0 (local X)
                let xAxis = obj.transform.columns.0
                let yaw = atan2(Double(xAxis.z), Double(xAxis.x))
                var path = Path()
                let corners: [CGPoint] = [
                    CGPoint(x: -halfW, y: -halfD),
                    CGPoint(x:  halfW, y: -halfD),
                    CGPoint(x:  halfW, y:  halfD),
                    CGPoint(x: -halfW, y:  halfD),
                ].map { c in
                    let s = sin(yaw), co = cos(yaw)
                    return CGPoint(x: p.x + c.x * co - c.y * s,
                                   y: p.y + c.x * s  + c.y * co)
                }
                path.move(to: corners[0])
                for c in corners.dropFirst() { path.addLine(to: c) }
                path.closeSubpath()
                let cat = category(obj.category)
                ctx.fill(path, with: .color(colorFor(category: cat).opacity(0.35)))
                ctx.stroke(path, with: .color(colorFor(category: cat)),
                           lineWidth: 1.2)
            }
        }
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
    }

    private func segmentPath(item: CapturedRoom.Surface,
                              project: (CGPoint) -> CGPoint,
                              ctx: GraphicsContext,
                              color: Color,
                              lineWidth: CGFloat) {
        let center = CGPoint(x: CGFloat(item.transform.columns.3.x),
                             y: CGFloat(item.transform.columns.3.z))
        let half = CGFloat(item.dimensions.x) / 2
        let xAxis = item.transform.columns.0
        let dirX = CGFloat(xAxis.x), dirZ = CGFloat(xAxis.z)
        var path = Path()
        path.move(to: project(CGPoint(x: center.x - dirX * half,
                                      y: center.y - dirZ * half)))
        path.addLine(to: project(CGPoint(x: center.x + dirX * half,
                                          y: center.y + dirZ * half)))
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func confidenceColor(_ c: CapturedRoom.Confidence) -> Color {
        switch c {
        case .high:   return .green
        case .medium: return .yellow
        case .low:    return .red
        @unknown default: return .white
        }
    }

    private func category(_ c: CapturedRoom.Object.Category) -> String {
        // CapturedRoom.Object.Category is a Swift enum; its rawValue or
        // String description is the category name.
        String(describing: c)
    }

    private func colorFor(category: String) -> Color {
        switch category {
        case "chair":          return .pink
        case "table",
             "diningTable":    return .orange
        case "sofa":           return .purple
        case "bed":            return .blue
        case "storage":        return .gray
        case "refrigerator":   return .mint
        case "television":     return .indigo
        default:                return .white
        }
    }
}
