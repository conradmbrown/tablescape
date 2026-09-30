import Foundation

@MainActor enum NativePlaytest {
    static func run(model: TableScapeModel) async {
        let session = model.session
        var checks: [JSONObject] = []
        func save() {
            let report: JSONObject = ["date": ISO8601DateFormatter().string(from: Date()), "checks": checks, "tick": session.state.int("tick"), "state": session.state,
                                      "render": ["chunks": model.scene.chunkCount, "models": model.scene.modelCount, "triangles": model.scene.triangleCount],
                                      "renderTiming": RenderMetrics.shared.snapshot(), "network": session.networkMetricsSnapshot()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? data.write(to: directory.appendingPathComponent("playtest.json"), options: .atomic)
            }
        }
        func record(_ name: String, _ pass: Bool, _ detail: String = "") {
            checks.append(["name": name, "pass": pass, "detail": detail])
            print("TABLESCAPE_TEST \(pass ? "PASS" : "FAIL") \(name) \(detail)"); save()
        }
        func wait(_ timeout: Double, _ predicate: () -> Bool) async -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while Date() < end { if predicate() { return true }; try? await Task.sleep(nanoseconds: 200_000_000) }
            return predicate()
        }
        func dialogueSignature() -> String {
            let root = session.state.int("chatRoot", -1)
            return String(root) + session.state.objects("ui").filter { $0.int("root") == root }.map { $0.string("text") + $0.string("option") }.joined(separator: "|")
        }
        session.username = "unityv" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(6)
        session.connect()
        let connected = await wait(25) { session.connected && !session.state.object("player").isEmpty }
        record("live native session", connected)
        guard connected else { record("test completion", false, session.status); return }
        record("server revision", session.state.int("revision") == 274)
        let loaded = await wait(60) { model.scene.chunkCount >= 9 && model.scene.modelCount > 0 && model.scene.triangleCount > 1000 }
        record("real region and cache meshes", loaded)
        let original = session.player, x = original.int("x"), z = original.int("z")
        session.move(x: x - 2, z: z)
        let moved = await wait(12) { session.player.int("x") != x || session.player.int("z") != z }
        record("server confirmed walking", moved)
        for tab in [3, 4, 1, 6, 5, 2, 0, 11, 13] {
            session.selectTab(tab)
            let shown = await wait(4) { session.state.int("activeTab") == tab }
            record("tab \(tab)", shown)
        }
        session.selectTab(3)
        _ = await wait(4) { session.activeTab == 3 }
        if let item = session.state.objects("inventory").first(where: { $0.strings("ops").contains("Drop") && $0.int("count", 1) == 1 }),
           let drop = item.strings("ops").firstIndex(of: "Drop") {
            let identity = GameContract.itemIdentity(item), id = item.int("id")
            session.itemAction(item, kind: "inventory", op: drop + 1)
            let dropped = await wait(10) {
                !session.state.objects("inventory").contains { GameContract.itemIdentity($0) == identity }
                    && session.state.objects("objects").contains { $0.int("id") == id }
            }
            record("inventory drop", dropped)
            if dropped, let ground = session.state.objects("objects").first(where: { $0.int("id") == id }),
               let take = ground.strings("ops").firstIndex(where: { $0.lowercased() == "take" }) {
                session.target(kind: "obj", actor: ground, op: take + 1)
                let picked = await wait(15) { session.state.objects("inventory").contains { $0.int("id") == id } }
                record("ground item pickup", picked)
            } else { record("ground item pickup", false, "Dropped item or its advertised Take action was unavailable") }
        } else { record("inventory drop", false, "No single held item advertised Drop"); record("ground item pickup", false, "Drop prerequisite failed") }
        if let npc = session.state.objects("npcs").first(where: { $0.string("name") == "Hans" }),
           let talk = npc.strings("ops").firstIndex(where: { $0.lowercased().contains("talk") }) {
            session.target(kind: "npc", actor: npc, op: talk + 1)
            let dialogue = await wait(45) { session.state.int("chatRoot", -1) >= 0 }
            record("native dialogue", dialogue)
            if dialogue, let widget = session.state.objects("ui").first(where: { $0.int("root") == session.state.int("chatRoot") && $0.int("button") == 6 }) {
                let before = dialogueSignature(), dispatched = session.actionCount
                session.activateWidget(widget)
                let advanced = await wait(12) { session.actionCount > dispatched && dialogueSignature() != before }
                record("dialogue advanced on server", advanced)
            } else { record("dialogue advanced on server", false, "No current Continue widget") }
        } else { record("native dialogue", false, "Hans or his advertised Talk action was unavailable"); record("dialogue advanced on server", false, "Dialogue prerequisite failed") }
        session.send(["kind": "close"])
        let closed = await wait(8) { session.state.int("chatRoot", -1) < 0 && session.state.int("mainRoot", -1) < 0 }
        record("dialogue close", closed)
        let name = session.username
        session.disconnect()
        _ = await wait(5) { !session.connected && session.state.isEmpty }
        session.connect()
        let rejoined = await wait(25) { session.connected && session.player.string("name").lowercased() == name }
        record("disconnect and reconnect", rejoined)
        save()
        print("TABLESCAPE_TEST_FINISHED \(checks.filter { !$0.bool("pass") }.count) failures")
    }
}
