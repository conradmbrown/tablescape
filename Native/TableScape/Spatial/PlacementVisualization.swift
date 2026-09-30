import Foundation
import simd

/// Lightweight setup geometry in room coordinates. Render without board/game transforms or clipping.
@MainActor
enum PlacementVisualization {
    private static var geometryCache: [String: RenderGeometry] = [:]

    static func nodes(for placement: TablePlacement) -> [RenderNode] {
        guard !placement.snapshot.isConfirmed else { return [] }
        var result: [RenderNode] = []
        if placement.isPlacingCorners {
            let corners = placement.manualCorners
            if corners.isEmpty, let device = placement.devicePose {
                let forward = SIMD3(device.columns.2.x, 0, device.columns.2.z)
                let center = SIMD3(device.columns.3.x, placement.manualHeight, device.columns.3.z) - forward * 0.9
                let guide = TableGeometry.rectangle(width: 1.2, depth: 0.8, center: center)
                result += polygon(guide, color: SIMD4(1, 0.7, 0.15, 0.10), outline: SIMD4(1, 0.8, 0.3, 0.7))
            }
            if let geometry = placement.manualGeometry {
                result += polygon(geometry, color: SIMD4(0.15, 1, 0.7, 0.16), outline: SIMD4(0.15, 1, 0.7, 1))
            } else if corners.count > 1 {
                for index in 1..<corners.count {
                    result.append(line(corners[index - 1], corners[index], color: SIMD4(1, 0.7, 0.1, 0.95), key: "manual-\(index)"))
                }
                if corners.count == 4 {
                    result.append(line(corners[3], corners[0], color: SIMD4(1, 0.25, 0.2, 1), key: "manual-close"))
                }
            }
            for (index, corner) in corners.enumerated() {
                let color = index == corners.count - 1 ? SIMD4<Float>(1, 1, 0.8, 1) : SIMD4<Float>(1, 0.7, 0.1, 1)
                result.append(marker(at: corner, color: color))
            }
            return result
        }
        let device = placement.devicePose?.columns.3 ?? SIMD4<Float>(0, 1.6, 0, 1)
        let candidates = placement.surfaces.sorted { a, b in
            if a.id == b.id { return false }
            if a.id == placement.selectedSurfaceID { return true }
            if b.id == placement.selectedSurfaceID { return false }
            return simd_distance(a.originFromTable.columns.3, device) < simd_distance(b.originFromTable.columns.3, device)
        }
        for surface in candidates.prefix(8) {
            let selected = surface.id == placement.selectedSurfaceID
            result += polygon(surface.geometry,
                              color: selected ? SIMD4(0.1, 1, 0.7, 0.20) : SIMD4(0.1, 0.6, 1, 0.08),
                              outline: selected ? SIMD4(0.1, 1, 0.7, 1) : SIMD4(0.3, 0.75, 1, 0.65))
        }
        return result
    }

    private static func cached(_ key: String, make: () -> NativeMesh) -> RenderGeometry {
        if let geometry = geometryCache[key] { return geometry }
        // Bounds setup memory even when ARKit continually refines plane meshes.
        if geometryCache.count >= 96 { geometryCache.removeAll(keepingCapacity: true) }
        let geometry = RenderGeometry(make())
        geometryCache[key] = geometry
        return geometry
    }

    private static func polygon(_ table: TableGeometry, color: SIMD4<Float>, outline: SIMD4<Float>) -> [RenderNode] {
        let points = table.boundary
        guard points.count >= 3 else { return [] }
        let key = points.map { "\($0.x),\($0.y)" }.joined(separator: ";")
        let fill = cached("fill:\(key):\(color)") {
            let center = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
            var vertices = [NativeVertex(position: SIMD3(center.x, 0.002, center.y), color: color)]
            vertices += points.map { NativeVertex(position: SIMD3($0.x, 0.002, $0.y), color: color) }
            var indices: [UInt32] = []
            for index in points.indices { indices += [0, UInt32(index + 1), UInt32((index + 1) % points.count + 1)] }
            return NativeMesh(vertices: vertices, indices: indices)
        }
        let border = cached("border:\(key):\(outline)") {
            var vertices: [NativeVertex] = [], indices: [UInt32] = []
            for index in points.indices {
                let a = points[index], b = points[(index + 1) % points.count]
                let edge = b - a
                guard simd_length(edge) > 0.0001 else { continue }
                let perpendicular = simd_normalize(SIMD2(-edge.y, edge.x)) * 0.004
                let offset = UInt32(vertices.count)
                for p in [a - perpendicular, b - perpendicular, b + perpendicular, a + perpendicular] {
                    vertices.append(NativeVertex(position: SIMD3(p.x, 0.004, p.y), color: outline))
                }
                indices += [offset, offset + 1, offset + 2, offset, offset + 2, offset + 3]
            }
            return NativeMesh(vertices: vertices, indices: indices)
        }
        return [RenderNode(geometry: fill, transform: table.originFromTable), RenderNode(geometry: border, transform: table.originFromTable)]
    }

    private static func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, color: SIMD4<Float>, key: String) -> RenderNode {
        let edge = b - a
        let horizontal = SIMD2(edge.x, edge.z)
        let offset = simd_length(horizontal) > 0.0001 ? simd_normalize(SIMD3(-edge.z, 0, edge.x)) * 0.005 : SIMD3<Float>(0.005, 0, 0)
        let geometry = cached("line:\(key):\(a):\(b):\(color)") {
            let vertices = [a - offset, b - offset, b + offset, a + offset].map { NativeVertex(position: $0 + SIMD3(0, 0.004, 0), color: color) }
            return NativeMesh(vertices: vertices, indices: [0, 1, 2, 0, 2, 3])
        }
        return RenderNode(geometry: geometry)
    }

    private static func marker(at point: SIMD3<Float>, color: SIMD4<Float>) -> RenderNode {
        let geometry = cached("marker:\(color)") {
            let r: Float = 0.016
            let points: [SIMD3<Float>] = [SIMD3(0, r, 0), SIMD3(r, 0, 0), SIMD3(0, 0, r), SIMD3(-r, 0, 0), SIMD3(0, 0, -r), SIMD3(0, -r, 0)]
            return NativeMesh(vertices: points.map { NativeVertex(position: $0, color: color) }, indices: [0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1, 5, 2, 1, 5, 3, 2, 5, 4, 3, 5, 1, 4])
        }
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(point + SIMD3(0, 0.018, 0), 1)
        return RenderNode(geometry: geometry, transform: transform)
    }
}
