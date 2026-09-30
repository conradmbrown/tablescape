import Foundation

/// Retains only server-declared NPC deaths long enough to show the original terminal pose.
/// Departed actors are visual-only; leaving range by itself never creates a death.
@MainActor final class NativeDeathRetention {
    private struct Death {
        var actor:JSONObject
        var firstSeen:Double
        var expires:Double
        var sequence:Int
        var delay:Double
    }
    private let store:NativeAssetStore
    private var deaths:[Int:Death]=[:]
    private var seen=Set<Int>()
    private var seenOrder:[Int]=[]
    private var requests:[Int:Task<Void,Never>]=[:]
    private var generation=0
    private var level:Int?
    private var lastTick=0
    private var lastNow=0.0
    private(set) var completedCount=0
    var retainedCount:Int {deaths.count}
    init(store:NativeAssetStore) {self.store=store}

    func reset() {
        generation += 1;requests.values.forEach {$0.cancel()};requests=[:];deaths=[:];seen=[];seenOrder=[];level=nil;lastTick=0;lastNow=0
    }

    func update(state:JSONObject,now:Double)->[JSONObject] {
        let currentLevel=state.int("level"),tick=state.int("tick")
        if level != nil && (level != currentLevel || tick<lastTick) {reset()}
        level=currentLevel;lastTick=tick;lastNow=now
        let npcs=state.objects("npcs"),liveIDs=Set(npcs.map {$0.int("id")})
        let livingIDs=Set(npcs.filter {$0.int("hp")>0 && !$0.bool("animDeath")}.map {$0.int("id")})
        for event in deaths.keys where livingIDs.contains(deaths[event]!.actor.int("id")) {deaths[event]=nil;requests.removeValue(forKey:event)?.cancel()}
        for actor in npcs+state.objects("npcDeaths") where actor.bool("animDeath") && actor.int("anim",-1)>=0 {
            let event=actor.int("animEvent")
            guard event>0 else {continue}
            if var old=deaths[event] {old.actor=actor;deaths[event]=old;continue}
            guard !seen.contains(event) else {continue}
            seen.insert(event);seenOrder.append(event)
            while seenOrder.count>1024 {seen.remove(seenOrder.removeFirst())}
            guard deaths.count<64,!livingIDs.contains(actor.int("id")) else {continue}
            let delay=Double(max(0,actor.int("animDelay")))/50
            deaths[event]=Death(actor:actor,firstSeen:now,expires:now+10,sequence:actor.int("anim"),delay:delay)
            let epoch=generation,id=actor.int("anim")
            requests[event]=Task { [weak self] in
                guard let self else {return}
                defer {if generation==epoch {requests[event]=nil}}
                guard let sequence=try? await store.sequence(id),generation==epoch,!Task.isCancelled,var death=deaths[event],!sequence.frames.isEmpty else {return}
                // Death cache sequences often hold the final pose for thousands of cycles.
                // Retire after that pose is displayed, not after its artificial long hold.
                let toTerminal=Double(sequence.frames.dropLast().reduce(0) {$0+max(1,$1.delay)}+1)/50
                let starts=max(death.firstSeen+death.delay,lastNow)
                death.expires=min(death.firstSeen+10,starts+toTerminal+0.2)
                deaths[event]=death
            }
        }
        for event in deaths.keys where now>=deaths[event]!.expires {deaths[event]=nil;requests.removeValue(forKey:event)?.cancel();completedCount += 1}
        var output:[JSONObject]=[],emitted=Set<Int>()
        for event in deaths.keys.sorted(by:>) {
            guard let death=deaths[event] else {continue}
            let id=death.actor.int("id")
            guard !liveIDs.contains(id),emitted.insert(id).inserted else {continue}
            var actor=death.actor
            actor["nativeVisualOnly"]=true;actor["ops"]=[String]();actor["hits"]=[JSONObject]();actor["hp"]=0
            output.append(actor)
        }
        return output
    }
}
