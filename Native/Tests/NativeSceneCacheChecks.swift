import Foundation
import simd

@main enum NativeSceneCacheChecks {
    static func originalSignature(_ actor:JSONObject)->String {
        let fields=["models","parts","recolS","recolD","scaleX","scaleY","scaleZ","angle","shape","hillHeights","width","length","lightAmbient","lightContrast"]
        return (try? JSONSerialization.data(withJSONObject:actor.filter{fields.contains($0.key)},options:.sortedKeys).base64EncodedString()) ?? ""
    }
    static func fixture(_ id:Int)->JSONObject {
        ["id":id,"key":"loc:\(id)","x":3220+id%20,"z":3210+id/20,"y":0.25,"width":2,"length":3,"angle":id%4,"offsetX":0.125,"offsetY":0.5,"offsetZ":0.25,"models":[1003+id%3],"recolS":[100,200],"recolD":[300,400],"scaleX":1,"scaleY":1,"scaleZ":1,"lightAmbient":id%10,"lightContrast":768,"parts":[["models":[1003+id%3],"recolS":[100],"recolD":[300]]]]
    }
    static func main() throws {
        let cache=NativeSceneStateCache()
        let first=fixture(1)
        let state:JSONObject=["player":["id":1,"x":3222,"z":3218],"locs":[first],"players":[first],"npcs":[first],"objects":[first]]
        cache.refresh(state:state,revision:1)
        precondition(cache.groups.count==6 && cache.player.int("x")==3222)
        let loc=cache.groups.first{$0.name=="locs"}!.actors[0]
        let npc=cache.groups.first{$0.name=="npcs"}!.actors[0]
        precondition(loc !== npc && loc.key != npc.key)
        precondition(loc.signature==originalSignature(first))
        precondition(simd_distance(loc.position,SIMD3(3222.625,-0.25,3211.25))<0.0001)
        let captured=cache.groups
        var changed=first;changed["models"]=[3000];changed["x"]=3240
        let next:JSONObject=["player":["id":1,"x":3240,"z":3218],"locs":[changed]]
        cache.refresh(state:next,revision:1)
        precondition(cache.groups.first{$0.name=="locs"}!.actors[0] === loc)
        cache.refresh(state:next,revision:2)
        let replacement=cache.groups.first{$0.name=="locs"}!.actors[0]
        precondition(replacement !== loc && replacement.signature != loc.signature)
        precondition(replacement.signature==originalSignature(changed))
        precondition(captured.first{$0.name=="locs"}!.actors[0].source.int("x")==3221)
        precondition(replacement.source.int("x")==3240)
        var death=first;death["nativeVisualOnly"]=true;death["animEvent"]=50;death["models"]=[999]
        let retained=cache.retainedDeaths([death])[0]
        precondition(retained !== npc && retained.key==npc.key)
        precondition(retained.signature==originalSignature(death) && retained.signature != npc.signature)
        precondition(cache.retainedDeaths([death])[0] === retained)
        precondition(cache.retainedDeaths([]).isEmpty)
        precondition(cache.retainedDeaths([death])[0] !== retained)
        cache.refresh(state:next,revision:3)
        precondition(cache.retainedDeaths([death])[0] !== retained)
        for id in 0..<100 {let source=fixture(id),actor=NativeSceneStateCache.Actor(source,group:"locs",scenery:true);precondition(actor.signature==originalSignature(source))}
        cache.reset();precondition(cache.revision==nil && cache.groups.isEmpty && cache.player.isEmpty)
        print("PASS scene state cache: signature parity, same-revision reuse, next-revision appearance/position invalidation, captured-state isolation, actor-group identity, retained-death isolation/expiry/reset")
        let sources=(0..<100).map{fixture($0)}
        let bulk:JSONObject=["player":["id":1,"x":3222,"z":3218],"locs":sources]
        var legacyTotal=0,cachedTotal=0
        let before=ProcessInfo.processInfo.systemUptime
        for _ in 0..<90 {for actor in sources {legacyTotal += originalSignature(actor).count;legacyTotal += originalSignature(actor).count}}
        let legacy=ProcessInfo.processInfo.systemUptime-before
        let optimized=NativeSceneStateCache(),start=ProcessInfo.processInfo.systemUptime
        for frame in 0..<90 {optimized.refresh(state:bulk,revision:frame/3);for actor in optimized.groups.first(where:{$0.name=="locs"})!.actors {cachedTotal += actor.signature.count;cachedTotal += actor.signature.count}}
        let elapsed=ProcessInfo.processInfo.systemUptime-start
        precondition(legacyTotal==cachedTotal)
        print(String(format:"BENCH synthetic 100-actor appearance work / 90 updates / new state every 3 updates: original %.2f ms, cached %.2f ms, %.2fx; not app FPS",legacy*1000,elapsed*1000,legacy/elapsed))
    }
}
