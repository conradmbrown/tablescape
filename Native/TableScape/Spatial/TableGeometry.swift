import Foundation
import simd

/// All dimensions are metres. Board space uses X/Z for the tabletop and +Y up.
struct TableGeometry: Sendable {
    let originFromTable: simd_float4x4
    let size: SIMD2<Float>
    /// Counterclockwise polygon in table-local X/Z coordinates.
    let boundary: [SIMD2<Float>]

    enum ValidationError: Error, LocalizedError, Equatable {
        case fourCornersRequired, invalidCoordinate, duplicateCorner, notHorizontal, notCoplanar, notConvex, tooSmall, tooLarge
        var errorDescription: String? {
            switch self {
            case .fourCornersRequired: "Place exactly four corners in order around the table."
            case .invalidCoordinate: "A corner has an invalid position. Place it again."
            case .duplicateCorner: "Keep each corner at least 10 cm from the others."
            case .notHorizontal: "Choose a horizontal tabletop, within 15° of level."
            case .notCoplanar: "The corners must lie on one flat surface, within 3 cm."
            case .notConvex: "Place corners clockwise around the edge. Crossed or inward edges are not supported."
            case .tooSmall: "The board must be at least 20 cm wide and deep, with 0.04 m² of area."
            case .tooLarge: "Choose a board no larger than 4 m in either direction."
            }
        }
    }

    /// Explicit virtual-board placement, relative to eye-level origin rather than an assumed floor height.
    /// Called once per placement request; the returned board does not follow the viewer afterward.
    static func virtualCenter(viewerTransform: simd_float4x4, distance: Float, drop: Float) -> SIMD3<Float> {
        let origin = viewerTransform.columns.3.xyz
        var forward = SIMD3(-viewerTransform.columns.2.x, 0, -viewerTransform.columns.2.z)
        if !simd_length(forward).isFinite || simd_length(forward) < 0.001 { forward = SIMD3(0, 0, -1) }
        else { forward = simd_normalize(forward) }
        let safeDistance = distance.isFinite ? min(max(distance, 0.8), 2.8) : 1.6
        let safeDrop = drop.isFinite ? min(max(drop, 0.15), 1.1) : 0.45
        return origin + forward * safeDistance - SIMD3(0, safeDrop, 0)
    }

    /// Preview and volumetric windows remain playable before physical placement.
    /// This footprint does not confirm an AR table or change tracking visibility.
    static func renderBoundary(boundary: [SIMD2<Float>], size: SIMD2<Float>) -> [SIMD2<Float>] {
        if boundary.count >= 3 { return boundary }
        return rectangle(width: size.x, depth: size.y, center: .zero).boundary
    }

    static func rectangle(width: Float, depth: Float, center: SIMD3<Float>) -> TableGeometry {
        let w = min(max(width, 0.2), 4), d = min(max(depth, 0.2), 4)
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(center, 1)
        return TableGeometry(originFromTable: transform, size: SIMD2(w, d), boundary: [SIMD2(-w / 2, -d / 2), SIMD2(w / 2, -d / 2), SIMD2(w / 2, d / 2), SIMD2(-w / 2, d / 2)])
    }

    static func validating(corners: [SIMD3<Float>]) throws -> TableGeometry {
        guard corners.count == 4 else { throw ValidationError.fourCornersRequired }
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { throw ValidationError.invalidCoordinate }
        for a in 0..<4 {
            for b in (a + 1)..<4 where simd_distance(corners[a], corners[b]) < 0.10 { throw ValidationError.duplicateCorner }
        }
        let firstEdge = corners[1] - corners[0]
        var normal = simd_cross(firstEdge, corners[3] - corners[0])
        guard simd_length(normal) > 0.0001 else { throw ValidationError.notConvex }
        normal = simd_normalize(normal)
        if normal.y < 0 { normal = -normal }
        guard normal.y >= cos(Float.pi / 12) else { throw ValidationError.notHorizontal }
        guard abs(simd_dot(corners[2] - corners[0], normal)) <= 0.03 else { throw ValidationError.notCoplanar }
        let center = corners.reduce(.zero, +) / 4
        let xAxis = simd_normalize(firstEdge - simd_dot(firstEdge, normal) * normal)
        let zAxis = simd_cross(xAxis, normal)
        var polygon = corners.map { SIMD2(simd_dot($0 - center, xAxis), simd_dot($0 - center, zAxis)) }
        let turns = (0..<4).map { cross(polygon[($0 + 1) % 4] - polygon[$0], polygon[($0 + 2) % 4] - polygon[($0 + 1) % 4]) }
        guard turns.allSatisfy({ $0 > 0.0001 }) || turns.allSatisfy({ $0 < -0.0001 }) else { throw ValidationError.notConvex }
        if signedArea(polygon) < 0 { polygon.reverse() }
        let low = polygon.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let high = polygon.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        let size = high - low
        guard size.x >= 0.2, size.y >= 0.2, signedArea(polygon) >= 0.04 else { throw ValidationError.tooSmall }
        guard size.x <= 4, size.y <= 4 else { throw ValidationError.tooLarge }
        return TableGeometry(originFromTable: simd_float4x4(columns: (SIMD4(xAxis, 0), SIMD4(normal, 0), SIMD4(zAxis, 0), SIMD4(center, 1))), size: size, boundary: polygon)
    }

    static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
    static func signedArea(_ polygon: [SIMD2<Float>]) -> Float {
        guard polygon.count > 2 else { return 0 }
        return polygon.indices.reduce(0) { $0 + cross(polygon[$1], polygon[($1 + 1) % polygon.count]) } / 2
    }

    static func contains(_ point: SIMD2<Float>, boundary: [SIMD2<Float>], tolerance: Float = 0.001) -> Bool {
        guard boundary.count >= 3 else { return false }
        return boundary.indices.allSatisfy { cross(boundary[($0 + 1) % boundary.count] - boundary[$0], point - boundary[$0]) >= -tolerance }
    }

    func intersect(rayOrigin: SIMD3<Float>, rayDirection: SIMD3<Float>) -> SIMD3<Float>? {
        let tableFromOrigin = simd_inverse(originFromTable)
        let origin = (tableFromOrigin * SIMD4(rayOrigin, 1)).xyz
        let direction = (tableFromOrigin * SIMD4(rayDirection, 0)).xyz
        guard abs(direction.y) > 0.00001 else { return nil }
        let t = -origin.y / direction.y
        guard t >= 0, t <= 10 else { return nil }
        let point = origin + direction * t
        guard Self.contains(SIMD2(point.x, point.z), boundary: boundary) else { return nil }
        return (originFromTable * SIMD4(point, 1)).xyz
    }

    /// Removing convex vertices makes an inward approximation, so a bounded Metal
    /// clip polygon cannot protrude outside the original convex hull.
    static func boundedHull(_ polygon: [SIMD2<Float>], maximumVertices: Int = 8) -> [SIMD2<Float>] {
        var result = polygon
        let limit = max(3, maximumVertices)
        while result.count > limit {
            let remove = result.indices.min { a, b in
                let aBefore = result[(a + result.count - 1) % result.count], aAfter = result[(a + 1) % result.count]
                let bBefore = result[(b + result.count - 1) % result.count], bAfter = result[(b + 1) % result.count]
                return abs(cross(result[a] - aBefore, aAfter - result[a])) < abs(cross(result[b] - bBefore, bAfter - result[b]))
            }!
            result.remove(at: remove)
        }
        return result
    }

    /// Monotonic hull produces a stable, ordered outline from ARKit's triangulated mesh.
    static func convexHull(_ input: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let points = Array(Set(input.filter { $0.x.isFinite && $0.y.isFinite })).sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard points.count >= 3 else { return [] }
        var lower: [SIMD2<Float>] = [], upper: [SIMD2<Float>] = []
        for point in points {
            while lower.count >= 2, cross(lower.last! - lower[lower.count - 2], point - lower.last!) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        for point in points.reversed() {
            while upper.count >= 2, cross(upper.last! - upper[upper.count - 2], point - upper.last!) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
