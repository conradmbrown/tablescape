#if TABLE_GEOMETRY_CHECKS
import Foundation
import simd

@main
struct GeometryChecks {
    static func main() throws {
        let rectangle: [SIMD3<Float>] = [SIMD3(-0.6, 0.75, -0.4), SIMD3(0.6, 0.75, -0.4), SIMD3(0.6, 0.75, 0.4), SIMD3(-0.6, 0.75, 0.4)]
        let table = try TableGeometry.validating(corners: rectangle)
        precondition(abs(table.size.x - 1.2) < 0.001 && abs(table.size.y - 0.8) < 0.001)
        precondition(abs(table.originFromTable.columns.3.y - 0.75) < 0.001)
        precondition(TableGeometry.contains(SIMD2(0, 0), boundary: table.boundary))
        precondition(!TableGeometry.contains(SIMD2(0.8, 0), boundary: table.boundary))
        let hit = table.intersect(rayOrigin: SIMD3(0, 2, 0), rayDirection: SIMD3(0, -1, 0))
        precondition(hit != nil && abs(hit!.y - 0.75) < 0.001)
        precondition(table.intersect(rayOrigin: SIMD3(0, 2, 0), rayDirection: SIMD3(0, 1, 0)) == nil)
        precondition(table.intersect(rayOrigin: SIMD3(1, 2, 0), rayDirection: SIMD3(0, -1, 0)) == nil)
        precondition(table.intersect(rayOrigin: SIMD3(0, 2, 0), rayDirection: SIMD3(1, 0, 0)) == nil)
        let reversed = try TableGeometry.validating(corners: rectangle.reversed())
        precondition(TableGeometry.signedArea(reversed.boundary) > 0)
        try rejected([rectangle[0], rectangle[2], rectangle[1], rectangle[3]], .notConvex)
        try rejected([rectangle[0], rectangle[1], rectangle[2], rectangle[0]], .duplicateCorner)
        var nonplanar = rectangle; nonplanar[2].y += 0.1
        try rejected(nonplanar, .notCoplanar)
        try rejected([SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)], .notHorizontal)
        try rejected([SIMD3(0, 0, 0), SIMD3(0.15, 0, 0), SIMD3(0.15, 0, 0.15), SIMD3(0, 0, 0.15)], .tooSmall)
        try rejected([SIMD3(0, 0, 0), SIMD3(5, 0, 0), SIMD3(5, 0, 1), SIMD3(0, 0, 1)], .tooLarge)
        var invalid = rectangle; invalid[0].x = .nan
        try rejected(invalid, .invalidCoordinate)
        let hull = TableGeometry.convexHull([SIMD2(1, 1), SIMD2(-1, 1), SIMD2(-1, -1), SIMD2(1, -1), SIMD2(0, 0), SIMD2(1, 1)])
        precondition(hull.count == 4 && abs(TableGeometry.signedArea(hull) - 4) < 0.001)
        let circle = (0..<40).map { index in let angle = Float(index) * 2 * .pi / 40; return SIMD2(cos(angle), sin(angle)) }
        let bounded = TableGeometry.boundedHull(circle)
        precondition(bounded.count == 8 && TableGeometry.signedArea(bounded) > 0)
        precondition(bounded.allSatisfy { TableGeometry.contains($0, boundary: circle) })
        precondition(TableGeometry.signedArea(bounded) < TableGeometry.signedArea(circle))
        // Translating/rotating the room must leave table-local dimensions and clipping intact.
        let angle = Float.pi / 3
        let moved = rectangle.map { SIMD3(cos(angle) * $0.x + sin(angle) * $0.z + 4, $0.y, -sin(angle) * $0.x + cos(angle) * $0.z - 2) }
        let transformed = try TableGeometry.validating(corners: moved)
        precondition(simd_distance(table.size, transformed.size) < 0.001)
        precondition(abs(TableGeometry.signedArea(table.boundary) - TableGeometry.signedArea(transformed.boundary)) < 0.001)
        let virtual = TableGeometry.virtualCenter(viewerTransform: matrix_identity_float4x4, distance: 1.6, drop: 0.45)
        precondition(simd_distance(virtual, SIMD3(0, -0.45, -1.6)) < 0.0001)
        let yawed = simd_float4x4(columns: (SIMD4(0,0,-1,0),SIMD4(0,1,0,0),SIMD4(1,0,0,0),SIMD4(3,1.7,4,1)))
        let positioned = TableGeometry.virtualCenter(viewerTransform: yawed, distance: 1.6, drop: 0.45)
        precondition(simd_distance(positioned, SIMD3(1.4,1.25,4)) < 0.0001)
        var vertical = matrix_identity_float4x4; vertical.columns.2 = SIMD4(0,1,0,0)
        precondition(simd_distance(TableGeometry.virtualCenter(viewerTransform: vertical, distance: .nan, drop: .nan), virtual) < 0.0001)
        print("PASS: tabletop geometry, ray picking, winding, rejection cases, convex hull, rigid-transform invariance, and eye-relative virtual placement")
    }
    private static func rejected(_ corners: [SIMD3<Float>], _ expected: TableGeometry.ValidationError) throws {
        do { _ = try TableGeometry.validating(corners: corners); preconditionFailure("Expected \(expected)") }
        catch let error as TableGeometry.ValidationError { precondition(error == expected, "Expected \(expected), got \(error)") }
    }
}
#endif
