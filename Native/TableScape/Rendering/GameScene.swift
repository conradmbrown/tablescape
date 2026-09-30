import Foundation
import Combine
import simd
import QuartzCore

/// Immutable actor dictionaries belong to one validated session revision. Keeping the
/// decoded arrays and lazy appearance key here avoids repeated Foundation bridging
/// and sorted JSON serialization while animation advances between network updates.
final class NativeSceneStateCache {
    final class Actor {
        let source: JSONObject
        let key: String
        let position: SIMD3<Float>
        private var appearanceKey: String?
        init(_ source: JSONObject, group: String, scenery: Bool) {
            self.source=source
            key=group+":"+(source["key"] as? String ?? String(source.int("id")))
            position=Self.worldPosition(source,scenery:scenery)
        }
        var signature: String {
            if let appearanceKey { return appearanceKey }
            let value=Self.signature(source); appearanceKey=value; return value
        }
        private static let appearanceFields:Set<String>=["models","parts","recolS","recolD","scaleX","scaleY","scaleZ","angle","shape","hillHeights","width","length","lightAmbient","lightContrast"]
        static func signature(_ source:JSONObject)->String {
            let data=try? JSONSerialization.data(withJSONObject:source.filter{appearanceFields.contains($0.key)},options:.sortedKeys)
            return data?.base64EncodedString() ?? ""
        }
        static func worldPosition(_ actor:JSONObject,scenery:Bool)->SIMD3<Float> {
            func number(_ key:String,_ fallback:Float=0)->Float { (actor[key] as? NSNumber)?.floatValue ?? fallback }
            var width=max(1,number(scenery ? "width":"size",1)),length=max(1,number(scenery ? "length":"size",1))
            if scenery && actor.int("angle")&1==1 {swap(&width,&length)}
            return SIMD3(number("x")+width/2+number("offsetX"),number("y")-number("offsetY"),number("z")+length/2+number("offsetZ"))
        }
    }
    struct Group {
        let name:String
        let kind:String
        let scenery:Bool
        var actors:[Actor]
    }
    private(set) var revision:Int?
    private(set) var player:JSONObject=[:]
    private(set) var groups:[Group]=[]
    private var departed:[String:Actor]=[:]
    func reset() {revision=nil;player=[:];groups=[];departed=[:]}
    func refresh(state:JSONObject,revision:Int) {
        guard self.revision != revision else {return}
        self.revision=revision;player=state.object("player");departed=[:]
        let definitions:[(String,String,String?,Bool)]=[("self","player",nil,false),("players","player","players",false),("npcs","npc","npcs",false),("locs","loc","locs",true),("lower","loc","backgroundLocs",true),("items","obj","objects",false)]
        groups=definitions.map {name,kind,collection,scenery in
            let sources=collection.map{state.objects($0)} ?? [player]
            return Group(name:name,kind:kind,scenery:scenery,actors:sources.map{Actor($0,group:name,scenery:scenery)})
        }
    }
    func retainedDeaths(_ sources:[JSONObject])->[Actor] {
        var liveKeys=Set<String>()
        let result=sources.map {source in
            let key=source.string("key",String(source.int("id")))+":"+String(source.int("animEvent"))
            liveKeys.insert(key)
            if let value=departed[key] {return value}
            // Keep the animation/motion identity, but never share the cached source
            // with a live actor that reuses the same NPC slot.
            let value=Actor(source,group:"npcs",scenery:false);departed[key]=value;return value
        }
        departed=departed.filter{liveKeys.contains($0.key)}
        return result
    }
}

#if !SCENE_CACHE_CHECKS
final class RenderGeometry: @unchecked Sendable {
    let id = UUID()
    let mesh: NativeMesh
    init(_ mesh: NativeMesh) { self.mesh=mesh }
}
struct RenderNode: @unchecked Sendable {
    let geometry: RenderGeometry
    var transform = matrix_identity_float4x4
    var tint = SIMD4<Float>(repeating: 1)
    var billboard=false
}
struct RenderSnapshot: @unchecked Sendable {
    var nodes: [RenderNode] = []
    var placementNodes: [RenderNode] = []
    var textures: [Int:Data] = [:]
    var center = SIMD3<Float>.zero
    var scale: Float = 0.038
    var tableQuarterTurns = 0
    var gameToBoard: simd_float4x4 {
        scYaw(-Float(tableQuarterTurns) * .pi / 2) * scScale(SIMD3(scale, scale, -scale)) * scTranslation(-center)
    }
    var board = matrix_identity_float4x4
    var boundary: [SIMD2<Float>] = [SIMD2(-0.65,-0.4),SIMD2(0.65,-0.4),SIMD2(0.65,0.4),SIMD2(-0.65,0.4)]
    var visible = true
    var virtual = false
    var tick = 0
}
final class SceneExchange: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = RenderSnapshot()
    func read() -> RenderSnapshot { lock.lock(); defer { lock.unlock() }; return snapshot }
    func write(_ value: RenderSnapshot) { lock.lock(); snapshot=value; lock.unlock() }
}
struct PickTarget { let kind:String; let actor:JSONObject; let meshes:[NativeMesh]; let transform:simd_float4x4 }
struct ActorMotion {
    var samples: [(Int,SIMD3<Float>)] = []
    mutating func observe(_ p: SIMD3<Float>, tick:Int) {
        if let last=samples.last, tick<last.0 || tick-last.0>8 || simd_distance(last.1,p)>8 { samples=[] }
        if samples.last?.0 != tick { samples.append((tick,p)); if samples.count>32 { samples.removeFirst() } }
    }
    func position(at tick:Double) -> SIMD3<Float> {
        guard let first=samples.first else { return .zero }; if tick<=Double(first.0) { return first.1 }
        for i in 1..<samples.count where tick<Double(samples[i].0) {
            let a=samples[i-1],b=samples[i],t=Float((tick-Double(a.0))/Double(max(1,b.0-a.0)))
            return simd_mix(a.1,b.1,SIMD3(repeating:t))
        }
        return samples.last!.1
    }
    var moving:Bool { samples.count>1 && simd_distance(samples[samples.count-1].1,samples[samples.count-2].1)>0.01 }
    var direction:SIMD3<Float> { samples.count>1 ? samples[samples.count-1].1-samples[samples.count-2].1 : SIMD3(0,0,-1) }
}

@MainActor final class GameScene: ObservableObject {
    @Published var status = "Connect to load the world"
    private(set) var chunkCount = 0
    private(set) var modelCount = 0
    private(set) var triangleCount = 0
    @Published var selectedName = ""
    private(set) var volumeTapCount = 0
    @Published private(set) var volumeInputStatus = "Preparing map input…"
    @Published private(set) var volumeLastSelection = ""
    @Published var tilesAcross:Double = 34
    @Published private(set) var tableQuarterTurns = 0
    func rotateTableClockwise() { setTableRotation((tableQuarterTurns + 1) % 4) }
    func resetTableRotation() { setTableRotation(0) }
    private func setTableRotation(_ turns: Int) {
        tableQuarterTurns = turns
        var snapshot = exchange.read(); snapshot.tableQuarterTurns = turns; exchange.write(snapshot)
    }
    @Published var orbit:Double = 0
    @Published var tilt:Double = 0.8
    private(set) var frameMilliseconds:Double = 0
    let exchange=SceneExchange()
    let session:GameSession
    let placement:TablePlacement
    let assets:NativeAssetStore
    let effects:NativeEffects
    let deaths:NativeDeathRetention
    let combatFeedback=NativeCombatFeedback()
    private var runner:Task<Void,Never>?
    private var chunks:[String:[RenderNode]]=[:]
    private var terrainSurfaces:[String:[NativeMesh]]=[:]
    private var chunkTasks:[String:Task<Void,Never>]=[:]
    private var models:[String:[NativeMesh]]=[:]
    private var modelOrder:[String]=[]
    private var modelBytes=0
    private var statics:[String:[RenderNode]]=[:]
    private var textures:[Int:Data]=[:]
    private var textureLoading:Set<Int>=[]
    private var targets:[PickTarget]=[]
    private var motion:[String:ActorMotion]=[:]
    private var sequences:[Int:NativeSequence]=[:]
    private var sequenceOrder:[Int]=[]
    private var sequenceBytes=0
    private var sequenceLoading:Set<Int>=[]
    private var animationStart:[String:(Int,Double)]=[:]
    private var epoch=0
    private var wasConnected=false
    private var lastTick=0
    private var originTick=0
    private var originTime=0.0
    private var lastCenter=SIMD3<Float>.zero
    private var lastUpdate=CACurrentMediaTime()
    private var identity=""
    private var hoveredIdentity=""
    private var lastHover=0.0
    private var pointMarker:(SIMD3<Float>,Double)?
    private let stateCache=NativeSceneStateCache()
    init(session:GameSession,placement:TablePlacement) {
        self.session=session; self.placement=placement
        assets=NativeAssetStore(fetch:{ path in try await session.data(path:path) })
        effects=NativeEffects(store:assets)
        deaths=NativeDeathRetention(store:assets)
        placement.onSnapshotChanged = { [weak self] _ in self?.publishPlacement() }
    }
    private func publishPlacement() {
        var value=exchange.read();let table=placement.snapshot
        value.board=table.originFromTable;value.boundary=table.renderBoundary;value.visible=table.isConfirmed && (table.isVirtual || table.trackingAvailable);value.virtual=table.isVirtual
        value.placementNodes=PlacementVisualization.nodes(for:placement);exchange.write(value)
    }
    func start() {
        guard runner==nil else { return }
        runner=Task { [weak self] in
            while !Task.isCancelled {
                let start=CACurrentMediaTime()
                if let self {await self.update()} else{return}
                let remaining=max(0.001,1.0/30.0-(CACurrentMediaTime()-start))
                try? await Task.sleep(nanoseconds:UInt64(remaining*1_000_000_000))
            }
        }
    }
    deinit {runner?.cancel()}
    private func cacheMeshes(_ value:[NativeMesh],key:String) {
        if let old=models.removeValue(forKey:key){modelBytes-=old.reduce(0){$0+$1.byteCount}}
        modelOrder.removeAll{$0==key};modelOrder.append(key);models[key]=value;modelBytes+=value.reduce(0){$0+$1.byteCount}
        while (modelBytes>64*1024*1024 || modelOrder.count>512),modelOrder.count>1 {let key=modelOrder.removeFirst();modelBytes-=models.removeValue(forKey:key)?.reduce(0){$0+$1.byteCount} ?? 0}
    }
    private func cacheSequence(_ value:NativeSequence) {
        if let old=sequences.removeValue(forKey:value.id){sequenceBytes-=old.byteCount}
        sequenceOrder.removeAll{$0==value.id};sequenceOrder.append(value.id);sequences[value.id]=value;sequenceBytes+=value.byteCount
        while (sequenceBytes>16*1024*1024 || sequenceOrder.count>128),sequenceOrder.count>1 {sequenceBytes-=sequences.removeValue(forKey:sequenceOrder.removeFirst())?.byteCount ?? 0}
    }
    func reset() {
        effects.reset();deaths.reset();combatFeedback.reset();stateCache.reset();Task {await assets.clearTransient()}
        epoch += 1; chunkTasks.values.forEach{$0.cancel()}; chunkTasks=[:]; chunks=[:];terrainSurfaces=[:]; statics=[:]; models=[:];modelOrder=[];modelBytes=0;sequences=[:];sequenceOrder=[];sequenceBytes=0; motion=[:]; targets=[]; animationStart=[:]; lastTick=0; lastCenter = .zero; pointMarker=nil
        exchange.write(RenderSnapshot()); chunkCount=0
    }
    private func number(_ obj:JSONObject,_ key:String,_ fallback:Float=0)->Float { (obj[key] as? NSNumber)?.floatValue ?? fallback }
    private func worldPosition(_ actor:JSONObject,scenery:Bool)->SIMD3<Float> {
        NativeSceneStateCache.Actor.worldPosition(actor,scenery:scenery)
    }
    private func actorMeshes(_ actor:JSONObject,scenery:Bool,kind:String="loc",appearanceKey:String?=nil) async throws -> [NativeMesh] {
        let lighting = scenery ? NativeComposition.sceneryLighting(actor:actor) : NativeComposition.actorLighting(actor:actor,kind:kind)
        let appearance = appearanceKey ?? NativeSceneStateCache.Actor.signature(actor)
        let key = "\(kind):\(lighting.ambient):\(lighting.contrast):\(appearance)"
        if let meshes=models[key] { return meshes }
        let parts=actor["parts"] as? [JSONObject] ?? [actor]
        var meshes=try await NativeComposition.meshes(parts:parts,store:assets,lighting:lighting)
        if scenery { meshes=NativeComposition.applyScenery(meshes:meshes,actor:actor) }
        cacheMeshes(meshes,key:key)
        return meshes
    }
    private func loadTextures(_ meshes:[NativeMesh]) {
        for m in meshes where m.textureID>=0 && textures[m.textureID]==nil && !textureLoading.contains(m.textureID) {
            let id=m.textureID; textureLoading.insert(id)
            Task { defer{textureLoading.remove(id)}; if let data=try? await assets.texture(id) { textures[id]=data } }
        }
    }
    private func batch(_ meshes:[NativeMesh])->[RenderNode] {
        var groups:[Int:NativeMesh]=[:]
        for m in meshes {
            var combined=groups.removeValue(forKey:m.textureID) ?? NativeMesh(vertices:[],indices:[],textureID:m.textureID)
            let base=UInt32(combined.vertices.count)
            combined.vertices.append(contentsOf:m.vertices); combined.indices.append(contentsOf:m.indices.map{$0+base}); groups[m.textureID]=combined
        }
        return groups.keys.sorted().compactMap{groups[$0]}.map{RenderNode(geometry:RenderGeometry($0))}
    }
    private func transformed(_ meshes:[NativeMesh],by transform:simd_float4x4)->[NativeMesh] {
        meshes.map{ source in var mesh=source; mesh.vertices=source.vertices.map{v in var result=v; result.position=scPoint(transform,v.position); return result}; return mesh }
    }
    private func stream(_ player:JSONObject,level:Int) {
        let cx=Int(floor(Double(number(player,"x"))/16))*16,cz=Int(floor(Double(number(player,"z"))/16))*16
        var wanted:[(String,Int,Int,Int,Int)]=[]
        for l in 0...max(0,min(3,level)) { for dx in -2...2 { for dz in -2...2 {
            let x=cx+dx*16,z=cz+dz*16; wanted.append(("\(l):\(x):\(z)",x,z,l,dx*dx+dz*dz+(level-l)*20))
        } } }
        wanted.sort{$0.4<$1.4}; let keys=Set(wanted.map{$0.0})
        chunks=chunks.filter{keys.contains($0.key)};terrainSurfaces=terrainSurfaces.filter{keys.contains($0.key)}
        for (key,task) in chunkTasks where !keys.contains(key) { task.cancel(); chunkTasks.removeValue(forKey:key) }
        let generation=epoch
        for (key,x,z,l,_) in wanted where chunks[key]==nil && chunkTasks[key]==nil {
            if chunkTasks.count>=2 { break }
            chunkTasks[key]=Task {
                defer { if generation==epoch {chunkTasks.removeValue(forKey:key)} }
                do {
                    let terrain=try await assets.terrain(x:x,z:z,level:l)
                    var meshes=terrain.meshes
                    for loc in terrain.locs {
                        if Task.isCancelled || generation != epoch { return }
                        guard let parts=try? await actorMeshes(loc,scenery:true) else { continue }
                        meshes.append(contentsOf:transformed(parts,by:scTranslation(worldPosition(loc,scenery:true))))
                    }
                    guard !Task.isCancelled,generation==epoch else { return }
                    loadTextures(meshes);terrainSurfaces[key]=terrain.meshes; chunks[key]=batch(meshes); chunkCount=chunks.count
                } catch { if !Task.isCancelled { status="Loading region: \(error.localizedDescription)" } }
            }
        }
    }
    private func groundHeight(_ p:SIMD3<Float>,level:Int)->Float {
        let x=Int(floor(p.x/16))*16,z=Int(floor(p.z/16))*16,key="\(level):\(x):\(z)"
        var height=p.y,closest=Float.greatestFiniteMagnitude
        for mesh in terrainSurfaces[key] ?? [] {for i in stride(from:0,to:max(0,mesh.indices.count-2),by:3) {
            if let t=scRayTriangle(p+SIMD3(0,1,0),SIMD3(0,-1,0),mesh.vertices[Int(mesh.indices[i])].position,mesh.vertices[Int(mesh.indices[i+1])].position,mesh.vertices[Int(mesh.indices[i+2])].position) {
                let y=p.y+1-t,delta=abs(y-p.y);if delta<closest {height=y;closest=delta}
            }
        }}
        return height
    }
    private func update() async {
        guard session.connected,!session.state.object("player").isEmpty else {
            if wasConnected { reset() }; wasConnected=false
            var empty=RenderSnapshot();empty.tableQuarterTurns=tableQuarterTurns;empty.board=placement.snapshot.originFromTable;empty.boundary=placement.snapshot.renderBoundary;empty.placementNodes=PlacementVisualization.nodes(for:placement);exchange.write(empty);return
        }
        let currentIdentity=session.username+session.endpoint+String(session.sessionEpoch)
        if currentIdentity != identity { reset(); identity=currentIdentity }
        wasConnected=true
        let generation=epoch, state=session.state,tick=state.int("tick"),now=CACurrentMediaTime()
        stateCache.refresh(state:state,revision:session.revision)
        let player=stateCache.player
        if lastTick==0 || tick<lastTick || tick-lastTick>8 { originTick=tick; originTime=now }
        lastTick=tick
        let renderTick=Double(originTick)+(now-originTime)/0.6-1.3
        stream(player,level:state.int("level"))
        var nodes=chunks.keys.sorted().flatMap{chunks[$0] ?? []}, nextTargets:[PickTarget]=[],alive:Set<String>=[]
        var entries=stateCache.groups
        // Death expiry still advances every animation update, independently of state revision.
        if let npcGroup=entries.firstIndex(where:{$0.name=="npcs"}) {
            entries[npcGroup].actors += stateCache.retainedDeaths(deaths.update(state:state,now:now))
        }
        let playerPosition=worldPosition(player,scenery:false)
        for entry in entries {
            let group=entry.name,kind=entry.kind,scenery=entry.scenery
            for cachedActor in entry.actors {
                let actor=cachedActor.source,position=cachedActor.position
                if simd_distance(SIMD2(position.x,position.z),SIMD2(playerPosition.x,playerPosition.z))>max(34,Float(tilesAcross)*0.9) {continue}
                let key=cachedActor.key,appearanceKey=cachedActor.signature
                alive.insert(key)
                do {
                    var meshes=try await actorMeshes(actor,scenery:scenery,kind:kind,appearanceKey:appearanceKey)
                    guard generation==epoch,session.connected else{return}
                    var pose=position,rotation:Float=0
                    if !scenery && kind != "obj" {
                        var track=motion[key] ?? ActorMotion(); track.observe(position,tick:tick); motion[key]=track
                        pose=track.position(at:renderTick)
                        if group=="self" { lastCenter=pose }
                        if actor.bool("hasFacing") { let d=SIMD2(number(actor,"faceX")-pose.x,number(actor,"faceZ")-pose.z); if simd_length(d)>0.01 {rotation=atan2(-d.x,-d.y)} }
                        else if track.moving { let d=track.direction; rotation=atan2(-d.x,-d.z) }
                        let action=actor.int("anim",default:-1)
                        let running=track.moving && state.bool("running") && actor.int("run",-1)>=0
                        let idleID=actor.int(track.moving ? (running ? "run":"walk"):"ready",default:-1)
                        for requested in Set([action,idleID]) where requested>=0 && sequences[requested]==nil && !sequenceLoading.contains(requested) {
                            sequenceLoading.insert(requested)
                            Task {defer {sequenceLoading.remove(requested)};if let sequence=try? await assets.sequence(requested),generation==epoch{cacheSequence(sequence)}}
                        }
                        var selectedSequence:NativeSequence?
                        var selectedStart=now
                        var playingAction=false
                        if action>=0 {
                            let event=actor.int("animEvent",actor.int("animTick"))
                            // Negative stamp is pending: preserve animDelay, but never consume cold sequence playback.
                            let stamp=(action+1)*1_000_000_000+max(0,event)%1_000_000_000
                            let pendingStamp = -stamp-1
                            if animationStart[key]?.0 != stamp && animationStart[key]?.0 != pendingStamp {
                                animationStart[key]=(pendingStamp,now+Double(max(0,actor.int("animDelay")))/50)
                            }
                            if let sequence=sequences[action] {
                                if animationStart[key]?.0==pendingStamp {animationStart[key]=(stamp,max(now,animationStart[key]?.1 ?? now))}
                                let started=animationStart[key]?.1 ?? now,elapsed=now-started
                                if elapsed>=0 && (actor.bool("animDeath") || elapsed<sequence.actionDuration) {
                                    selectedSequence=sequence;selectedStart=started;playingAction=true
                                    if (sequence.replaceheldleft ?? -1)>=0 || (sequence.replaceheldright ?? -1)>=0 {
                                        let heldKey="held:\(kind):\(appearanceKey):\(sequence.id):\(actor.int("gender"))"
                                        if let cached=models[heldKey] {meshes=cached}
                                        else {
                                            let source=actor["parts"] as? [JSONObject] ?? [actor]
                                            let encoded=try JSONSerialization.data(withJSONObject:source)
                                            let original=try JSONDecoder().decode([NativeAssetPart].self,from:encoded)
                                            let parts=NativeAnimator.replacementParts(original,sequence:sequence,gender:actor.int("gender"))
                                            let composed=try await NativeComposition.meshes(parts:parts,store:assets,lighting:NativeComposition.actorLighting(actor:actor,kind:kind))
                                            guard generation==epoch,session.connected else{return}
                                            cacheMeshes(composed,key:heldKey);meshes=composed
                                        }
                                    }
                                }
                            }
                        }
                        if selectedSequence==nil,let sequence=sequences[idleID] {
                            let idleKey=key+":motion"
                            if animationStart[idleKey]?.0 != idleID {animationStart[idleKey]=(idleID,now)}
                            selectedSequence=sequence;selectedStart=animationStart[idleKey]?.1 ?? now
                        }
                        if let sequence=selectedSequence {meshes=NativeAnimator.pose(meshes:meshes,sequence:sequence,time:max(0,now-selectedStart),loop:!playingAction)}
                    }
                    if kind == "obj" {let bottom=meshes.flatMap{$0.vertices}.map{$0.position.y}.min() ?? 0;pose.y=groundHeight(pose,level:state.int("level"))-min(0,bottom)+0.02}
                    let actorScale = scenery ? SIMD3<Float>(repeating:1):SIMD3(number(actor,"scaleX",1),number(actor,"scaleY",1),number(actor,"scaleZ",number(actor,"scaleX",1)))
                    let transform=scTranslation(pose)*scYaw(rotation)*scScale(actorScale)
                    if scenery {
                        let skey=key+appearanceKey
                        if statics[skey]==nil { statics[skey]=meshes.map{RenderNode(geometry:RenderGeometry($0),transform:transform)} }
                        nodes.append(contentsOf:statics[skey] ?? [])
                    } else { nodes.append(contentsOf:meshes.map{RenderNode(geometry:RenderGeometry($0),transform:transform)}) }
                    if session.selectedTarget?.string("key")==GameContract.identity(kind:kind,actor:actor) || hoveredIdentity==GameContract.identity(kind:kind,actor:actor) {
                        nodes.append(RenderNode(geometry:RenderGeometry(Self.marker(radius:max(0.5,number(actor,"size",1)*0.6),color:SIMD4(0.25,1,0.8,0.9))),transform:scTranslation(pose+SIMD3(0,0.025,0))))
                    }
                    loadTextures(meshes)
                    if group != "self" && group != "lower" && !actor.bool("nativeVisualOnly") {nextTargets.append(PickTarget(kind:kind,actor:actor,meshes:meshes,transform:transform))}

                } catch { status=error.localizedDescription }
            }
        }
        motion=motion.filter{alive.contains($0.key)}
        animationStart=animationStart.filter{alive.contains($0.key) || ($0.key.hasSuffix(":motion") && alive.contains(String($0.key.dropLast(7))))}
        if statics.count>512 || statics.values.reduce(0,{$0+$1.reduce(0,{$0+$1.geometry.mesh.byteCount})})>32*1024*1024 {statics=[:]}
        targets=nextTargets; modelCount=models.count
        let feedback=combatFeedback.update(state:state,now:now);nodes+=feedback.nodes
        if let marker=pointMarker,now-marker.1<1 {nodes.append(RenderNode(geometry:RenderGeometry(Self.marker(radius:0.3,color:SIMD4(0.5,1,0.75,1))),transform:scTranslation(marker.0+SIMD3(0,0.04,0))))}
        let effectNodes=await effects.update(state:state,now:now);nodes+=effectNodes;loadTextures(effectNodes.map{$0.geometry.mesh})
        guard generation==epoch else{return}
        let table=placement.snapshot
        var snapshot=RenderSnapshot(); snapshot.nodes=nodes; snapshot.textures=textures.merging(feedback.textures){_,new in new}; snapshot.tick=tick
        snapshot.center=lastCenter == .zero ? playerPosition:lastCenter
        snapshot.scale=Float(table.size.x)/Float(tilesAcross)
        snapshot.tableQuarterTurns=tableQuarterTurns
        snapshot.board=table.originFromTable; snapshot.boundary=table.renderBoundary
        snapshot.placementNodes=PlacementVisualization.nodes(for: placement)
        snapshot.visible=table.isConfirmed && (table.isVirtual || table.trackingAvailable);snapshot.virtual=table.isVirtual
        exchange.write(snapshot);RenderMetrics.shared.sceneSnapshot(CACurrentMediaTime())
        triangleCount=nodes.reduce(0){$0+$1.geometry.mesh.indices.count/3}
        if chunks.count>0 {let ready="World ready · Floor \(state.int("level"))";if status != ready {status=ready}}
        frameMilliseconds=(CACurrentMediaTime()-now)*1000; lastUpdate=now
    }
    static func marker(radius:Float,color:SIMD4<Float>)->NativeMesh {
        var v:[NativeVertex]=[],indices:[UInt32]=[]
        for i in 0..<24 { let angle=Float(i)*2*Float.pi/24; for r in [radius,radius*0.72] {v.append(NativeVertex(position:SIMD3(sin(angle)*r,0,cos(angle)*r),color:color))} }
        for i in 0..<24 {let a=UInt32(i*2),b=UInt32((i*2+2)%48); indices += [a,a+1,b,a+1,b+1,b]}
        return NativeMesh(vertices:v,indices:indices)
    }
    // These are the terrain surfaces and current interactive actors, without
    // animation effects or background scenery. The volume cooks only terrain.
    var volumeTerrainChunks: [(key: String, meshes: [NativeMesh])] {
        terrainSurfaces.map { (key: $0.key, meshes: $0.value) }
    }
    var volumeTargets: [PickTarget] { targets }
    var volumeInputEpoch: Int { epoch }

    func setVolumeInputStatus(_ value: String) {
        if volumeInputStatus != value { volumeInputStatus = value }
    }

    /// A system-confirmed surface tap needs no camera or hand-derived ray.
    /// Resolve actor identities against the current frame before sending actions.
    func selectVolumePoint(_ boardPoint: SIMD3<Float>, targetID: String?, terrain: Bool) {
        volumeTapCount += 1
        guard boardPoint.x.isFinite, boardPoint.y.isFinite, boardPoint.z.isFinite else { return }
        let snapshot = exchange.read()
        guard session.connected, snapshot.scale.isFinite, snapshot.scale > 0,
              scInside(SIMD2(boardPoint.x, boardPoint.z), snapshot.boundary) else { return }
        if let targetID {
            guard let target = targets.first(where: { GameContract.identity(kind: $0.kind, actor: $0.actor) == targetID }) else {
                volumeLastSelection = "That target has moved"; return
            }
            selectedName = target.actor.string("name")
            volumeLastSelection = "Actions opened"
            session.showTarget(kind: target.kind, actor: target.actor)
        } else if terrain {
            let point = snapshot.center + SIMD3(boardPoint.x, boardPoint.y, -boardPoint.z) / snapshot.scale
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return }
            session.send(["kind": "move", "x": Int(floor(point.x)), "z": Int(floor(point.z)), "run": session.state.bool("running")])
            pointMarker = (point, CACurrentMediaTime()); selectedName = "Walk here"
            volumeLastSelection = "Walking"
        }
    }

    func pick(origin:SIMD3<Float>,direction:SIMD3<Float>,preview:Bool=false,menu:Bool=false,highlightOnly:Bool=false) {
        if highlightOnly {let now=CACurrentMediaTime();guard now-lastHover>0.1 else{return};lastHover=now}
        if !highlightOnly && !preview && placement.handleSelectionRay(origin:origin,direction:direction) {return}
        guard session.connected else{return}
        let snapshot=exchange.read(),board=preview ? matrix_identity_float4x4:snapshot.board
        let worldFromGame=board*snapshot.gameToBoard
        let o=scPoint(worldFromGame.inverse,origin),d=scDirection(worldFromGame.inverse,direction)
        var closest:Float=Float.greatestFiniteMagnitude,selected:PickTarget?,point:SIMD3<Float>?
        for target in targets {
            let localO=scPoint(target.transform.inverse,o),localD=scDirection(target.transform.inverse,d)
            for mesh in target.meshes { for i in stride(from:0,to:mesh.indices.count-2,by:3) {
                if let t=scRayTriangle(localO,localD,mesh.vertices[Int(mesh.indices[i])].position,mesh.vertices[Int(mesh.indices[i+1])].position,mesh.vertices[Int(mesh.indices[i+2])].position) {
                    let p=scPoint(target.transform,localO+localD*t),distance=simd_distance(o,p)
                    guard distance<closest else{continue}
                    let local=scPoint(snapshot.gameToBoard,p)
                    if scInside(SIMD2(local.x,local.z),snapshot.boundary) {closest=distance; selected=target;point=p}
                }
            } }
        }
        for node in chunks.values.flatMap({$0}) {let mesh=node.geometry.mesh
            for i in stride(from:0,to:max(0,mesh.indices.count-2),by:3) {
                if let t=scRayTriangle(o,d,mesh.vertices[Int(mesh.indices[i])].position,mesh.vertices[Int(mesh.indices[i+1])].position,mesh.vertices[Int(mesh.indices[i+2])].position),t<closest {
                    let p=o+d*t,local=scPoint(snapshot.gameToBoard,p)
                    if scInside(SIMD2(local.x,local.z),snapshot.boundary) {closest=t;point=p;selected=nil}
                }
            }
        }
        if highlightOnly {hoveredIdentity=selected.map{GameContract.identity(kind:$0.kind,actor:$0.actor)} ?? "";selectedName=selected?.actor.string("name") ?? "";return}
        if let target=selected {
            selectedName=target.actor.string("name"); session.showTarget(kind:target.kind,actor:target.actor)
            if !menu {session.target(kind:target.kind,actor:target.actor,op:(target.actor.strings("ops").firstIndex(where:{!$0.isEmpty}) ?? 0)+1)}
            return
        }
        if let p=point {
            let local=scPoint(snapshot.gameToBoard,p)
            guard scInside(SIMD2(local.x,local.z),snapshot.boundary) else{return}
            session.send(["kind":"move","x":Int(floor(p.x)),"z":Int(floor(p.z)),"run":session.state.bool("running")]); pointMarker=(p,CACurrentMediaTime());selectedName="Walk here"
        }
    }
}

#endif // !SCENE_CACHE_CHECKS
