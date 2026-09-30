import Foundation
import simd

func scTranslation(_ v: SIMD3<Float>) -> simd_float4x4 {
    var m = matrix_identity_float4x4; m.columns.3 = SIMD4(v, 1); return m
}
func scScale(_ v: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(diagonal: SIMD4(v,1))
}
func scYaw(_ angle: Float) -> simd_float4x4 { simd_float4x4(simd_quatf(angle: angle, axis: SIMD3(0,1,0))) }
func scLookAt(_ eye: SIMD3<Float>, _ target: SIMD3<Float>) -> simd_float4x4 {
    let z = simd_normalize(eye-target), x = simd_normalize(simd_cross(SIMD3<Float>(0,1,0),z)), y = simd_cross(z,x)
    let world = simd_float4x4(SIMD4(x,0),SIMD4(y,0),SIMD4(z,0),SIMD4(eye,1))
    return world.inverse
}
func scPerspective(_ fov: Float, _ aspect: Float, near: Float = 0.02, far: Float = 50) -> simd_float4x4 {
    let y = 1/tan(fov/2), x = y/aspect, z = near/(far-near)
    return simd_float4x4(SIMD4(x,0,0,0),SIMD4(0,y,0,0),SIMD4(0,0,z,-1),SIMD4(0,0,far*z,0))
}
func scPoint(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> { let v=m*SIMD4(p,1); return SIMD3(v.x,v.y,v.z)/v.w }
func scDirection(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> { let v=m*SIMD4(p,0); return simd_normalize(SIMD3(v.x,v.y,v.z)) }
func scRayTriangle(_ origin: SIMD3<Float>, _ direction: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float? {
    let ab=b-a, ac=c-a, h=simd_cross(direction,ac), det=simd_dot(ab,h)
    if abs(det)<0.000001 { return nil }
    let f=1/det, s=origin-a, u=f*simd_dot(s,h)
    if u<0 || u>1 { return nil }
    let q=simd_cross(s,ab), v=f*simd_dot(direction,q)
    if v<0 || u+v>1 { return nil }
    let t=f*simd_dot(ac,q); return t>0 ? t : nil
}
func scInside(_ p: SIMD2<Float>, _ boundary: [SIMD2<Float>]) -> Bool {
    guard boundary.count >= 3 else { return false }
    var pos=false,neg=false
    for i in boundary.indices { let a=boundary[i], b=boundary[(i+1)%boundary.count], e=b-a, v=p-a, d=e.x*v.y-e.y*v.x; pos = pos || d>0.0001; neg = neg || d < -0.0001 }
    return !(pos && neg)
}
