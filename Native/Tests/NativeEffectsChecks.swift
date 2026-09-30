import Foundation
import simd

@main struct Checks {
    @MainActor static func main() async throws {
        let source=URL(fileURLWithPath:CommandLine.arguments[1]),build=URL(fileURLWithPath:CommandLine.arguments[2])
        let definitions=try JSONSerialization.jsonObject(with:Data(contentsOf:source.appendingPathComponent("Native/Tests/Fixtures/original-effects.json"))) as! [JSONObject]
        let store=NativeAssetStore(fetch:{_ in throw NativeAssetError.missing("offline effects verification")},packURL:source.appendingPathComponent("Native/TableScape/Resources/AssetPack"),cacheURL:build.appendingPathComponent("EffectsCache"))
        let effects=NativeEffects(store:store)
        var projectile=definitions[0];projectile.merge(["event":1,"kind":"projectile","tick":100,"x":0,"y":1,"z":0,"dstX":4,"dstY":1,"dstZ":0,"duration":2.0,"peak":16,"arc":0,"target":0]) {$1}
        var ground=definitions[1];ground.merge(["event":2,"kind":"ground","tick":100,"x":2,"y":1,"z":2,"duration":2.0]) {$1}
        var attached=definitions[2];attached.merge(["event":3,"kind":"attached","tick":100,"height":1.0,"duration":2.0]) {$1}
        var delayed=definitions[1];delayed.merge(["event":4,"kind":"ground","tick":100,"x":5,"y":1,"z":2,"duration":2.0,"delay":1.0]) {$1}
        let state:JSONObject=["tick":100,"level":0,"player":["id":1,"x":10,"y":2,"z":10,"effects":[attached]],"effects":[projectile,ground,delayed]]
        _=await effects.update(state:state,now:100)
        for _ in 0..<200 where effects.spawnedCount<4 {try await Task.sleep(nanoseconds:1_000_000)}
        guard effects.spawnedCount==4,effects.projectileCount==1,effects.attachedCount==1 else {fatalError("effect loading: \(effects.spawnedCount) \(effects.lastError ?? "")")}
        let start=await effects.update(state:state,now:100)
        guard start.contains(where:{$0.geometry.mesh.sourceModel==3081}),start.contains(where:{$0.geometry.mesh.sourceModel==3091}) else {fatalError("original effects absent")}
        guard !start.contains(where:{$0.transform.columns.3.x==5}) else {fatalError("effect ignored delay")}
        let attachment=start.first(where:{$0.geometry.mesh.sourceModel==3091})!
        guard attachment.transform.columns.3.x==10.5,attachment.transform.columns.3.y==3,attachment.transform.columns.3.z==10.5 else {fatalError("attachment position")}
        let half=await effects.update(state:state,now:101)
        let moving=half.first(where:{$0.geometry.mesh.sourceModel==3081})!
        guard abs(moving.transform.columns.3.x-2)<0.001,moving.transform.columns.3.y>1 else {fatalError("projectile arc")}
        guard half.contains(where:{$0.transform.columns.3.x==5}) else {fatalError("delayed effect never started")}
        let endpoint=await effects.update(state:state,now:102).first(where:{$0.geometry.mesh.sourceModel==3081})!
        guard abs(endpoint.transform.columns.3.x-4)<0.001,abs(endpoint.transform.columns.3.y-1)<0.001 else {fatalError("projectile endpoint")}
        for node in start+half {for vertex in node.geometry.mesh.vertices {guard vertex.position.x.isFinite,vertex.position.y.isFinite,vertex.position.z.isFinite else {fatalError("effect animation invalid")}}}
        let expired=await effects.update(state:state,now:120)
        guard expired.isEmpty,effects.spawnedCount==4,effects.activeCount==0,effects.sampledFrames>0 else {fatalError("expiry or duplicate replay")}
        effects.reset();_=await effects.update(state:state,now:130)
        for _ in 0..<200 where effects.spawnedCount<8 {try await Task.sleep(nanoseconds:1_000_000)}
        guard effects.spawnedCount==8 else {fatalError("reset did not reopen new event epoch")}
        // The actual effects consumer must light raw cached geometry for each
        // instance, keeping world placement and alpha independent of shading.
        guard NativeDefinitionLighting.npc(type:1043)==SIMD2(70,350),
              NativeDefinitionLighting.effect(type:76)==SIMD2(100,100),
              NativeDefinitionLighting.effect(type:90)==SIMD2(30,30),
              NativeDefinitionLighting.npc(type:-1)==SIMD2<Int>.zero,
              NativeDefinitionLighting.effect(type:-1)==SIMD2<Int>.zero else {fatalError("original definition lighting units/IDs")}
        let lightingEffects=NativeEffects(store:store)
        let rawModel=try await store.model(3081)
        let rawMeshes=rawModel.mesh(lit:false)
        let lightingBase:JSONObject=["event":11,"kind":"ground","model":3081,"sequence":-1,"tick":200,
                                    "x":0,"y":1,"z":0,"duration":2.0]
        var brighter=lightingBase;brighter.merge(["event":12,"x":3,"lightAmbient":96,"lightContrast":850]) {$1}
        var rotated=lightingBase;rotated.merge(["event":13,"x":6,"angle":90]) {$1}
        var shifted=lightingBase;shifted.merge(["event":14,"x":9]) {$1}
        var fallback=lightingBase;fallback.merge(["event":15,"x":12,"type":90]) {$1}
        var explicitEquivalent=lightingBase;explicitEquivalent.merge(["event":16,"x":15,"lightAmbient":94,"lightContrast":880]) {$1}
        var explicitOverride=fallback;explicitOverride.merge(["event":17,"x":18,"lightAmbient":64,"lightContrast":850]) {$1}
        let lightingState:JSONObject=["tick":200,"level":0,"effects":[lightingBase,brighter,rotated,shifted,fallback,explicitEquivalent,explicitOverride]]
        _=await lightingEffects.update(state:lightingState,now:200)
        for _ in 0..<200 where lightingEffects.spawnedCount<7 {
            _=await lightingEffects.update(state:lightingState,now:200)
            try await Task.sleep(nanoseconds:1_000_000)
        }
        guard lightingEffects.spawnedCount==7 else {fatalError("lighting effect fixtures did not load")}
        let litNodes=await lightingEffects.update(state:lightingState,now:200)
        func meshes(at x:Float)->[NativeMesh] {litNodes.filter {$0.transform.columns.3.x==x}.map { $0.geometry.mesh }}
        func colors(_ meshes:[NativeMesh])->[SIMD4<Float>] {meshes.flatMap { $0.vertices.map(\.color) }}
        let normal=meshes(at:0),normalColors=colors(normal)
        guard !normalColors.isEmpty,normalColors != colors(rawMeshes) else {fatalError("effect consumer left original models unlit")}
        guard normalColors==colors(meshes(at:9)) else {fatalError("world translation changed effect lighting")}
        guard normalColors != colors(meshes(at:3)) else {fatalError("effect lighting overrides were ignored")}
        guard normalColors != colors(meshes(at:6)) else {fatalError("ground effect local rotation did not affect lighting")}
        guard colors(meshes(at:12))==colors(meshes(at:15)),normalColors != colors(meshes(at:12)) else {fatalError("effect type fallback differs from original explicit lighting")}
        guard normalColors==colors(meshes(at:18)) else {fatalError("explicit effect lighting did not override type fallback")}
        guard normal.count==rawMeshes.count else {fatalError("lighting changed effect mesh grouping")}
        for i in normal.indices {
            guard normal[i].indices==rawMeshes[i].indices,
                  normal[i].vertices.map(\.position)==rawMeshes[i].vertices.map(\.position),
                  normal[i].vertices.map({$0.color.w})==rawMeshes[i].vertices.map({$0.color.w}) else {fatalError("lighting changed effect geometry or alpha")}
        }
        print("PASS effect lighting consumer: directional shading, local rotation, original definition fallback/units, explicit override precedence, shared raw cache, translation invariance and unchanged geometry/alpha")
        print("PASS original Wind Strike projectile/impact + teleport: async load, recolor/animation, attachment position, delayed start, ballistic midpoint/endpoint, snapshot deduplication, expiry, reset; sampledFrames=\(effects.sampledFrames)")
    }
}
