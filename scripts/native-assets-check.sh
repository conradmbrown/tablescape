#!/usr/bin/env bash
# Original asset + live backend fixture checks, all outputs and compiler caches on the SSD.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
checks="$build_root/AssetChecks"
scape_require_storage_path "$checks" "$build_root/ModuleCache"
mkdir -p "$checks" "$build_root/ModuleCache"
python3 - "$checks" "${SCAPE_GATEWAY:-http://127.0.0.1:18890}" <<'PY_LIVE'
import urllib.request,json,pathlib,time,sys,uuid
base=sys.argv[2].rstrip('/')
out=pathlib.Path(sys.argv[1])
out.mkdir(parents=True,exist_ok=True)
def req(path,method='GET',body=None,token=None):
    headers={'Content-Type':'application/json'}
    if token: headers['Authorization']='Bearer '+token
    with urllib.request.urlopen(urllib.request.Request(base+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method),timeout=20) as r:
        return r.read()
session=json.loads(req('/v1/session','POST',{'username':'unitya'+uuid.uuid4().hex[:6],'startLumbridge':True}))
token=session['token']
try:
    for _ in range(30):
        data=req('/v1/state',token=token); state=json.loads(data)
        if not state.get('pending'): break
        time.sleep(.2)
    player=state['player']
    x=int(player['x'])//16*16;z=int(player['z'])//16*16
    terrain=req(f'/v1/chunk?x={x}&z={z}&level={state["level"]}',token=token)
    sequence=req('/v1/sequence/'+str(player['ready']),token=token)
    (out/'terrain.json').write_bytes(terrain)
    (out/'sequence.json').write_bytes(sequence)
    (out/'parts.json').write_text(json.dumps(player['parts']))
    print(json.dumps({'terrainBytes':len(terrain),'sequenceBytes':len(sequence),'sequenceId':player['ready'],'models':[m for part in player['parts'] for m in part['models']],'x':x,'z':z,'level':state['level']}))
finally:
    req('/v1/session','DELETE',token=token)
PY_LIVE
cat > "$checks/NativeAssetChecks.swift" <<'SWIFT_CHECKS'
import Foundation
import simd

@main struct NativeAssetChecks {
    static func main() async throws {
        let source = URL(fileURLWithPath:CommandLine.arguments[1])
        let urls = try FileManager.default.contentsOfDirectory(at:source.appendingPathComponent("models"),includingPropertiesForKeys:nil).filter { $0.pathExtension == "ob2" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var vertices = 0, faces = 0, textured = 0, labeled = 0
        for url in urls {
            let model = try NativeModel.decode(Data(contentsOf:url),id:Int(url.deletingPathExtension().lastPathComponent) ?? -1)
            vertices += model.positions.count; faces += model.faces.count
            textured += model.renderTypes.filter { $0 & 2 != 0 }.count
            labeled += model.vertexLabels.filter { $0 >= 0 }.count
            if model.id % 100 == 0 {
                let meshes = model.mesh(), mirror = model.mesh(mirrored:true)
                guard meshes.reduce(0,{$0+$1.indices.count}) == model.faces.count*3 else { fatalError("triangle loss") }
                for m in meshes.indices { for i in meshes[m].vertices.indices {
                    let a = meshes[m].vertices[i], b = mirror[m].vertices[i]
                    guard a.position.x == b.position.x, a.position.y == b.position.y, a.position.z == -b.position.z else { fatalError("mirror") }
                    guard a.position.x.isFinite, a.color.x.isFinite, a.uv.x.isFinite else { fatalError("non-finite mesh") }
                } }
            }
        }
        for bad in [Data(),Data(repeating:0,count:17),Data(repeating:255,count:30)] {
            do { _ = try NativeModel.decode(bad); fatalError("accepted corrupt model") } catch {}
        }
        let original = NativeMesh(vertices:[NativeVertex(position:SIMD3(1,2,3),color:SIMD4(repeating:1))],indices:[0],vertexLabels:[3],faceLabels:[4])
        let frame = NativeFrame(delay:1,transforms:[NativeTransform(type:1,x:128,y:64,z:-128,labels:[3]),NativeTransform(type:5,x:10,y:0,z:0,labels:[4])])
        let pose = NativeAnimator.apply(meshes:[original],frame:frame)
        guard pose[0].vertices[0].position == SIMD3(2,1.5,2), abs(pose[0].vertices[0].color.w-(1-80.0/255)) < 0.00001 else { fatalError("animation translation or alpha") }
        let noLabel = NativeFrame(delay:1,transforms:[NativeTransform(type:1,x:128,y:0,z:0,labels:[9])])
        guard NativeAnimator.apply(meshes:[original],frame:noLabel)[0].vertices[0].position == original.vertices[0].position else { fatalError("label isolation") }
        let checks = URL(fileURLWithPath:CommandLine.arguments[2])
        let terrain = try NativeTerrain.decode(Data(contentsOf:checks.appendingPathComponent("terrain.json")))
        guard !terrain.meshes.isEmpty, !terrain.locs.isEmpty else { fatalError("live terrain/scenery") }
        let sequence = try JSONDecoder().decode(NativeSequence.self,from:Data(contentsOf:checks.appendingPathComponent("sequence.json")))
        let parts = try JSONDecoder().decode([NativeAssetPart].self,from:Data(contentsOf:checks.appendingPathComponent("parts.json")))
        let pack = URL(fileURLWithPath:CommandLine.arguments[3])
        let store = NativeAssetStore(fetch:{ _ in throw NativeAssetError.missing("offline verification") },packURL:pack,cacheURL:checks.appendingPathComponent("UnusedCache"))
        let assembled = try await NativeComposition.meshes(parts:parts,store:store)
        let posed = NativeAnimator.pose(meshes:assembled,sequence:sequence,time:0.15)
        var moved = 0
        for m in posed.indices { for i in posed[m].vertices.indices {
            let v = posed[m].vertices[i].position
            guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { fatalError("live animation invalid") }
            if simd_length(v-assembled[m].vertices[i].position) > 0.0001 { moved += 1 }
        } }
        guard moved > 0 else { fatalError("live animation static") }
        let emptyPack = checks.appendingPathComponent("EmptyPack"), emptyCache = checks.appendingPathComponent("EmptyCache")
        try FileManager.default.createDirectory(at:emptyPack,withIntermediateDirectories:true)
        try Data(contentsOf:pack.appendingPathComponent("manifest.json")).write(to:emptyPack.appendingPathComponent("manifest.json"))
        let raw = try Data(contentsOf:pack.appendingPathComponent("models/0.ob2"))
        let cold = NativeAssetStore(fetch:{ _ in raw },packURL:emptyPack,cacheURL:emptyCache)
        _ = try await cold.model(0)
        guard try Data(contentsOf:emptyCache.appendingPathComponent("models/0.ob2")) == raw else { fatalError("empty cache not populated") }
        let broken = NativeAssetStore(fetch:{ _ in Data([1,2,3]) },packURL:emptyPack,cacheURL:checks.appendingPathComponent("CorruptCache"))
        do { _ = try await broken.model(0); fatalError("unverified download accepted") } catch NativeAssetError.integrity {} catch { throw error }
        print("PASS liveTerrainMeshes=\(terrain.meshes.count) scenery=\(terrain.locs.count) originalSequence=\(sequence.id) movedVertices=\(moved) coldCacheDownload/hashRejection=verified")
        print("PASS originalModels=\(urls.count) sourceVertices=\(vertices) faces=\(faces) texturedFaces=\(textured) labeledVertices=\(labeled) mirror/finite/truncation/animation/alpha/labels=verified")
    }
}
SWIFT_CHECKS
xcrun swiftc -O -swift-version 6 -module-cache-path "$build_root/ModuleCache"   "$repo_root"/Native/TableScape/Assets/*.swift "$checks/NativeAssetChecks.swift"   -o "$build_root/native-asset-checks"
pack="$repo_root/Native/TableScape/Resources/AssetPack"
"$build_root/native-asset-checks" "$pack" "$checks" "$pack"
