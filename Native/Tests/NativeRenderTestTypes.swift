import simd
final class RenderGeometry: @unchecked Sendable {
    let mesh: NativeMesh
    init(_ mesh: NativeMesh) {self.mesh=mesh}
}
struct RenderNode: @unchecked Sendable {
    let geometry: RenderGeometry
    var transform=matrix_identity_float4x4
    var billboard=false
    var tint=SIMD4<Float>(repeating:1)
}
