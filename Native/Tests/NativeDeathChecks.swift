import Foundation
@main struct Checks {
    @MainActor static func main() async throws {
        let source=URL(fileURLWithPath:CommandLine.arguments[1]),root=source.appendingPathComponent("Native/Tests/Fixtures")
        let seqData=try Data(contentsOf:root.appendingPathComponent("death-sequence.json"))
        let sequence=try JSONDecoder().decode(NativeSequence.self,from:seqData)
        var npc:JSONObject=["id":101,"hp":10,"maxHp":10,"models":[],"deathAnim":sequence.id]
        let store=NativeAssetStore(fetch:{_ in seqData},packURL:source.appendingPathComponent("Native/TableScape/Resources/AssetPack"))
        let retained=NativeDeathRetention(store:store)
        let living:JSONObject=["tick":100,"level":0,"npcs":[npc]]
        guard retained.update(state:living,now:10).isEmpty else {fatalError("living ghost")}
        guard retained.update(state:["tick":101,"level":0,"npcs":[]],now:10.6).isEmpty else {fatalError("invented death leaving range")}
        npc["animDeath"]=true;npc["anim"]=sequence.id;npc["animEvent"]=777;npc["hp"]=0
        let liveDeath:JSONObject=["tick":102,"level":0,"npcs":[npc]]
        guard retained.update(state:liveDeath,now:11.2).isEmpty else {fatalError("duplicated live NPC")}
        for _ in 0..<50 {await Task.yield()}
        let departed:JSONObject=["tick":103,"level":0,"npcs":[],"npcDeaths":[npc]]
        let held=retained.update(state:departed,now:11.3)
        guard held.count==1,held[0].bool("nativeVisualOnly"),held[0].strings("ops").isEmpty else {fatalError("missing/nonvisual death")}
        guard retained.update(state:departed,now:11.4).count==1 else {fatalError("duplicate event")}
        guard retained.update(state:departed,now:25).isEmpty else {fatalError("death never cleaned")}
        guard retained.update(state:departed,now:26).isEmpty else {fatalError("death replayed")}
        retained.reset()
        guard retained.update(state:departed,now:30).count==1 else {fatalError("reset failed")}
        var respawn=npc;respawn["animDeath"]=false;respawn["hp"]=10;respawn["anim"] = -1
        guard retained.update(state:["tick":104,"level":0,"npcs":[respawn],"npcDeaths":[npc]],now:30.2).isEmpty else {fatalError("respawn duplicate")}
        print("PASS original death sequence \(sequence.id): no invented death on range exit; no duplicate live actor; visual-only departed actor; dedup; terminal cleanup; reset; respawn replacement")
    }
}
