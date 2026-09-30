import Foundation
import simd

/// Original revision-274 spot animations and projectiles. The server owns event identity and timing.
@MainActor final class NativeEffects {
    private struct Effect: Sendable {
        var id: Int
        var kind: String
        var model: Int
        var sequence: Int
        var inlineSequence: NativeSequence?
        var tick: Int
        var target: Int
        var position: SIMD3<Float>
        var destination: SIMD3<Float>
        var destinationHeight: Float
        var height: Float
        var delay: Double
        var duration: Double
        var scale: SIMD3<Float>
        var angle: Float
        var lightAmbient: Int
        var lightContrast: Int
        var peak: Int
        var arc: Float
        var recolors: [Int:Int]
        var recolorPairs: [SIMD2<Int>]
        var anchor: String?

        init?(_ raw: JSONObject, anchor: String?) {
            id=raw.int("event",-1); model=raw.int("model",-1); kind=raw.string("kind")
            guard id>=0, (0...65535).contains(model), ["ground","attached","projectile"].contains(kind) else { return nil }
            self.anchor=anchor
            sequence=raw.int("sequence",-1); tick=raw.int("tick"); target=raw.int("target")
            func value(_ key:String,_ fallback:Double=0)->Float { Float(raw.double(key,fallback)) }
            position=SIMD3(value("x"),value("y"),value("z"))
            destination=SIMD3(value("dstX"),value("dstY"),value("dstZ"))
            destinationHeight=value("dstHeight"); height=value("height")
            delay=max(0,min(30,raw.double("delay"))); duration=max(0.02,min(60,raw.double("duration",0.6)))
            let horizontal=value("scaleH",1), vertical=value("scaleV",1)
            scale=SIMD3(horizontal,vertical,horizontal); angle=value("angle") * .pi/180
            let definitionLighting=NativeDefinitionLighting.effect(type:raw.int("type",-1))
            lightAmbient=raw.int("lightAmbient",64+definitionLighting.x)
            lightContrast=raw.int("lightContrast",850+definitionLighting.y)
            peak=raw.int("peak"); arc=value("arc")
            recolorPairs=zip(raw.ints("recolS"),raw.ints("recolD")).map {SIMD2($0.0,$0.1)}
            recolors=[:]; for (from,to) in zip(raw.ints("recolS"),raw.ints("recolD")) { recolors[from]=to }
            let inline=raw.object("sequenceData")
            if !inline.isEmpty, let data=try? JSONSerialization.data(withJSONObject:inline) {
                inlineSequence=try? JSONDecoder().decode(NativeSequence.self,from:data)
            }
            if kind != "projectile", let frames=inlineSequence?.frames, !frames.isEmpty {
                duration=Double(frames.reduce(0) { $0+max(1,$1.delay)+1 })/50
            }
            guard position.x.isFinite,position.y.isFinite,position.z.isFinite,destination.x.isFinite,destination.y.isFinite,destination.z.isFinite,
                  height.isFinite,destinationHeight.isFinite,scale.x.isFinite,scale.y.isFinite,angle.isFinite,arc.isFinite,delay.isFinite,duration.isFinite else { return nil }
        }
        var geometryKey:String { "\(model):"+recolorPairs.map { "\($0.x)=\($0.y)" }.joined(separator:",") }
    }
    private struct Pending { var effect:Effect; var born:Double }
    private struct Live {
        var effect:Effect
        var meshes:[NativeMesh]
        var sequence:NativeSequence?
        var born:Double
        var position:SIMD3<Float>
        var destination:SIMD3<Float>
        var velocity=SIMD3<Float>.zero
        var elapsed:Double=0
        var launched=false
    }
    private struct Motion {
        var samples:[(Int,SIMD3<Float>)]=[]
        mutating func observe(_ point:SIMD3<Float>,tick:Int) {
            if let last=samples.last, tick<last.0 || tick-last.0>8 || simd_distance(last.1,point)>8 { samples=[] }
            if samples.last?.0 != tick { samples.append((tick,point)); if samples.count>32 {samples.removeFirst()} }
        }
        func position(at tick:Double)->SIMD3<Float> {
            guard let first=samples.first else {return .zero}
            if tick<=Double(first.0) {return first.1}
            for i in 1..<samples.count where tick<Double(samples[i].0) {
                let a=samples[i-1],b=samples[i],t=Float((tick-Double(a.0))/Double(max(1,b.0-a.0)))
                return simd_mix(a.1,b.1,SIMD3(repeating:t))
            }
            return samples.last!.1
        }
    }

    private let store:NativeAssetStore
    private var live:[Int:Live]=[:]
    private var pending:[Int:Pending]=[:]
    private var loading:[Int:Task<Void,Never>]=[:]
    private var seen=Set<Int>()
    private var history:[Int]=[]
    private var geometries:[String:[NativeMesh]]=[:]
    private var geometryOrder:[String]=[]
    private var geometryBytes=0
    private var motion:[String:Motion]=[:]
    private var generation=0
    private var currentLevel:Int?
    private var lastTick=0
    private var originTick=0
    private var originTime=0.0
    private var lastNow=0.0
    private let maximumLive=64
    private let maximumNodes=256
    private(set) var spawnedCount=0
    private(set) var projectileCount=0
    private(set) var attachedCount=0
    private(set) var sampledFrames=0
    private(set) var lastError:String?
    var activeCount:Int {live.count}

    init(store:NativeAssetStore) {self.store=store}

    func reset() {
        generation += 1; loading.values.forEach {$0.cancel()}; loading=[:]; live=[:]; pending=[:]; seen=[]; history=[]
        motion=[:]; currentLevel=nil; lastTick=0; originTick=0; originTime=0; lastNow=0; lastError=nil
        // Retain the bounded, immutable original model cache across session changes.
    }

    func update(state:JSONObject,now:Double) async -> [RenderNode] {
        guard now.isFinite else {return []}
        let tick=state.int("tick"),level=state.int("level")
        if currentLevel != nil && (currentLevel != level || tick<lastTick) {reset()}
        currentLevel=level; lastNow=now
        if lastTick==0 || tick-lastTick>8 {originTick=tick;originTime=now}
        lastTick=tick
        let renderTick=Double(originTick)+(now-originTime)/0.6-1.3
        var anchors:[String:SIMD3<Float>]=[:]
        var entries:[(String,JSONObject)]=[]
        let player=state.object("player")
        if !player.isEmpty {entries.append(("player:\(player.int("id"))",player))}
        entries += state.objects("players").map {("player:\($0.int("id"))",$0)}
        entries += state.objects("npcs").map {("npc:\($0.int("id"))",$0)}
        for (key,actor) in entries {
            let size=Float(max(1,actor.double("size",1)))
            let point=SIMD3(Float(actor.double("x"))+size/2+Float(actor.double("offsetX")),Float(actor.double("y"))-Float(actor.double("offsetY")),Float(actor.double("z"))+size/2+Float(actor.double("offsetZ")))
            var track=motion[key] ?? Motion(); track.observe(point,tick:tick); motion[key]=track
            anchors[key]=track.position(at:renderTick)
            for raw in actor.objects("effects") {enqueue(raw,anchor:key,tick:tick,now:now)}
        }
        motion=motion.filter {anchors[$0.key] != nil}
        for raw in state.objects("effects") {enqueue(raw,anchor:nil,tick:tick,now:now)}
        for id in pending.keys.sorted() where loading.count<4 {
            guard live.count+loading.count<maximumLive,let job=pending.removeValue(forKey:id) else {break}
            if now-job.born>job.effect.duration {continue}
            load(job)
        }
        var nodes:[RenderNode]=[]
        for id in live.keys.sorted() {
            guard var effect=live[id] else {continue}
            let age=max(-30,now-effect.born)
            if age>effect.effect.duration || (effect.effect.anchor != nil && anchors[effect.effect.anchor!]==nil) {live[id]=nil;continue}
            if age<0 {continue}
            var position=effect.position,rotation=matrix_identity_float4x4
            // The original client lights effects after posing and local resize.
            // Ground effects include their local yaw; projectile heading remains
            // a world transform, while its pitch contributes to the normals.
            var lightingRotation = simd_float3x3(simd_quatf(angle: effect.effect.kind == "ground" ? effect.effect.angle : 0, axis: SIMD3(0,1,0)))
            if let anchor=effect.effect.anchor,let point=anchors[anchor] {
                position=point+SIMD3(0,effect.effect.height,0)
            } else if effect.effect.kind=="projectile" {
                let target=effect.effect.target
                let key=target>0 ? "npc:\(target-1)" : "player:\(-target-1)"
                if target != 0,let point=anchors[key] {effect.destination=point+SIMD3(0,effect.effect.destinationHeight,0)}
                advance(&effect,age:age)
                position=effect.position
                if simd_length_squared(effect.velocity)>0.00001 {
                    rotation=projectileRotation(effect.velocity)
                    let pitch=atan2(effect.velocity.y,simd_length(SIMD2(effect.velocity.x,effect.velocity.z)))
                    lightingRotation=simd_float3x3(simd_quatf(angle:pitch,axis:SIMD3(1,0,0)))
                }
            }
            var meshes=effect.meshes
            if let sequence=effect.sequence,!sequence.frames.isEmpty {
                meshes=sample(meshes:meshes,sequence:sequence,age:age,loop:effect.effect.kind=="projectile")
                sampledFrames += 1
            }
            let lighting=NativeLighting(ambient:effect.effect.lightAmbient,contrast:effect.effect.lightContrast,
                direction:SIMD3(-30,-50,-30),transform:lightingRotation * simd_float3x3(diagonal:effect.effect.scale))
            meshes=NativeModelLighting.shade(meshes:meshes,lighting:lighting)
            let transform=scTranslation(position)*rotation*scYaw(effect.effect.angle)*scScale(effect.effect.scale)
            for mesh in meshes where nodes.count<maximumNodes {nodes.append(RenderNode(geometry:RenderGeometry(mesh),transform:transform))}
            live[id]=effect
        }
        return nodes
    }

    private func enqueue(_ raw:JSONObject,anchor:String?,tick:Int,now:Double) {
        let id=raw.int("event",-1)
        guard id>=0,!seen.contains(id),let effect=Effect(raw,anchor:anchor) else {return}
        seen.insert(id);history.append(id)
        while history.count>4096 {seen.remove(history.removeFirst())}
        let age=Double(tick-effect.tick)*0.6-effect.delay
        guard age<=effect.duration,pending.count+loading.count+live.count<maximumLive else {return}
        pending[id]=Pending(effect:effect,born:now-age)
    }

    private func load(_ job:Pending) {
        let epoch=generation,id=job.effect.id,key=job.effect.geometryKey
        loading[id]=Task { [weak self] in
            guard let self else {return}
            defer {if generation==epoch {loading[id]=nil}}
            do {
                let meshes:[NativeMesh]
                if let cached=geometries[key] {meshes=cached;touch(key)}
                else {
                    let model=try await store.model(job.effect.model)
                    meshes=model.mesh(recolorPairs:job.effect.recolorPairs,lit:false)
                    guard generation==epoch,!Task.isCancelled else {return}
                    geometries[key]=meshes;geometryBytes += meshes.reduce(0) {$0+$1.byteCount};touch(key)
                    while (geometryBytes>16*1024*1024 || geometryOrder.count>128),geometryOrder.count>1 {
                        let old=geometryOrder.removeFirst();geometryBytes -= geometries.removeValue(forKey:old)?.reduce(0) {$0+$1.byteCount} ?? 0
                    }
                }
                var sequence=job.effect.inlineSequence
                if sequence==nil,job.effect.sequence>=0 {sequence=try? await store.sequence(job.effect.sequence)}
                guard generation==epoch,!Task.isCancelled,lastNow-job.born<=job.effect.duration else {return}
                var definition=job.effect
                if definition.kind != "projectile",let sequence,!sequence.frames.isEmpty {definition.duration=Double(sequence.frames.reduce(0) {$0+max(1,$1.delay)+1})/50}
                live[id]=Live(effect:definition,meshes:meshes,sequence:sequence,born:job.born,position:definition.position,destination:definition.destination)
                spawnedCount += 1;if definition.kind=="projectile" {projectileCount += 1};if definition.kind=="attached" {attachedCount += 1}
            } catch {if generation==epoch,!Task.isCancelled {lastError=error.localizedDescription}}
        }
    }

    private func touch(_ key:String) {geometryOrder.removeAll {$0==key};geometryOrder.append(key)}

    /// Matching original 50 Hz effect-frame timing: secondary sequences include the extra cycle.
    private func sample(meshes:[NativeMesh],sequence:NativeSequence,age:Double,loop:Bool)->[NativeMesh] {
        let total=sequence.frames.reduce(0) {$0+max(1,$1.delay)+1}
        guard total>0 else {return meshes}
        var cycle=max(0,Int(age*50))
        cycle=loop ? cycle%total : min(cycle,total-1)
        var index=0
        while index<sequence.frames.count-1,cycle>=max(1,sequence.frames[index].delay)+1 {cycle -= max(1,sequence.frames[index].delay)+1;index += 1}
        return NativeAnimator.apply(meshes:meshes,frame:sequence.frames[index])
    }

    /// Same launch offset, slope and continuously retargeted vertical acceleration as Unity/Lost City.
    private func advance(_ live:inout Live,age:Double) {
        if !live.launched {
            var horizontal=live.destination-live.position;horizontal.y=0
            if simd_length_squared(horizontal)>0.0001 {live.position += simd_normalize(horizontal)*live.effect.arc}
            let remaining=Float(max(0.02,live.effect.duration))
            live.velocity=(live.destination-live.position)/remaining
            let initial=simd_length(SIMD2(live.velocity.x,live.velocity.z))*tan(Float(live.effect.peak) * .pi/128)
            live.velocity.y=initial.isFinite ? initial : 0;live.launched=true
        }
        let dt=Float(max(0,age-live.elapsed)),remaining=Float(max(0.02,live.effect.duration-live.elapsed))
        live.velocity.x=(live.destination.x-live.position.x)/remaining
        live.velocity.z=(live.destination.z-live.position.z)/remaining
        let acceleration=2*(live.destination.y-live.position.y-live.velocity.y*remaining)/(remaining*remaining)
        live.position += live.velocity*dt+SIMD3(0,acceleration*0.5*dt*dt,0)
        live.velocity.y += acceleration*dt;live.elapsed=age
    }

    private func projectileRotation(_ velocity:SIMD3<Float>)->simd_float4x4 {
        let z = -simd_normalize(velocity)
        let up=abs(z.y)>0.99 ? SIMD3<Float>(0,0,1):SIMD3<Float>(0,1,0)
        let x=simd_normalize(simd_cross(up,z)),y=simd_cross(z,x)
        return simd_float4x4(SIMD4(x,0),SIMD4(y,0),SIMD4(z,0),SIMD4(0,0,0,1))
    }
}
