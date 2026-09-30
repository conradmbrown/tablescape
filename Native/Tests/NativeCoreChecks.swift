import Foundation

enum CheckFailure: Error { case failed(String) }

@MainActor final class CoreChecks {
    let game = GameSession()
    let mode: String
    var checks: [JSONObject] = []
    var peers: [GameSession] = []
    var transitions: [JSONObject] = []
    init(_ mode: String) {
        self.mode = mode
        game.audioEnabled = false
        let fixture = mode == "fault" || mode.hasPrefix("persistence_")
        game.endpoint = ProcessInfo.processInfo.environment[fixture ? "SCAPE_FAULT_ENDPOINT" : "SCAPE_GATEWAY"] ?? (fixture ? "http://127.0.0.1:18892" : "http://127.0.0.1:18890")
        game.username = mode.hasPrefix("persistence_") ? (ProcessInfo.processInfo.environment["SCAPE_QA_NAME"] ?? name()) : name()
    }
    func name() -> String { "unityn" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(6) }
    func require(_ pass: Bool, _ name: String, _ detail: String = "") throws {
        checks.append(["name": name, "pass": pass, "detail": detail])
        print("\(pass ? "PASS" : "FAIL") \(name) \(detail)"); fflush(stdout)
        save()
        if !pass { throw CheckFailure.failed(name) }
    }
    func wait(_ name: String, seconds: Double = 25, _ predicate: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if predicate() { try require(true, name); return }; try await Task.sleep(nanoseconds: 100_000_000) }
        try require(predicate(), name, "\(game.status); position \(game.player.int("x")),\(game.player.int("z")); \(game.state.strings("messages").suffix(4))")
    }
    func save() {
        guard let directory = ProcessInfo.processInfo.environment["SCAPE_CORE_ARTIFACTS"] else { return }
        let value: JSONObject = ["mode": mode, "date": ISO8601DateFormatter().string(from: Date()), "username": game.username, "checks": checks,
                                 "actions": game.actionCount, "states": game.stateCount, "state": game.state, "transitions": transitions, "lastAction": game.lastAction ?? [:], "network": game.networkMetricsSnapshot(),
                                 "peers": peers.map { ["username": $0.username, "actions": $0.actionCount, "state": $0.state] as JSONObject }]
        if let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
            try? bytes.write(to: URL(fileURLWithPath: directory).appendingPathComponent(mode + ".json"), options: .atomic)
        }
    }
    func start() async throws { game.connect(); try await wait("live native login") { self.game.connected } }
    func finish() async {
        save(); game.disconnect(); peers.forEach { $0.disconnect() }
        try? await Task.sleep(nanoseconds: 900_000_000)
        try? NativeSessionCredential.removeRecord(endpoint: game.endpoint, username: game.username)
        for peer in peers { try? NativeSessionCredential.removeRecord(endpoint: peer.endpoint, username: peer.username) }
    }
    func held(_ name: String, in session: GameSession? = nil) -> [JSONObject] {
        let session = session ?? game, roots = session.state.ints("tabs")
        let inventoryRoot = roots.count > 3 ? roots[3] : -2
        return session.state.objects("inventory").filter { $0.int("root", -1) == inventoryRoot && $0.string("name").lowercased() == name.lowercased() }
    }
    func count(_ name: String, in session: GameSession? = nil) -> Int { held(name, in: session).reduce(0) { $0 + $1.int("count", 1) } }
    func op(_ actor: JSONObject, containing text: String) -> Int? { actor.strings("ops").firstIndex { $0.lowercased().contains(text.lowercased()) }.map { $0 + 1 } }
    func itemButton(_ item: JSONObject, named text: String) -> Int? {
        item.strings("buttons").firstIndex { $0.lowercased().replacingOccurrences(of: "-", with: " ") == text.lowercased().replacingOccurrences(of: "-", with: " ") }.map { $0 + 1 }
    }
    func close() async throws { game.send(["kind": "close"]); try await wait("interfaces closed") { self.game.state.int("chatRoot", -1) < 0 && self.game.state.int("mainRoot", -1) < 0 } }
    func move(_ x: Int, _ z: Int, seconds: Double = 75) async throws {
        game.runEnabled = true; game.move(x: x, z: z)
        try await wait("walk to \(x),\(z)", seconds: seconds) { abs(self.game.player.int("x") - x) + abs(self.game.player.int("z") - z) < 3 }
    }
    func signature(_ value: Any) -> String { ((try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()).base64EncodedString() }

    func live() async throws {
        let sparse: JSONObject = ["ops": [NSNull(), "null", "Follow", "Trade with", "null"]]
        try require(sparse.strings("ops") == ["", "", "Follow", "Trade with", ""], "sparse player operations retain protocol indexes")
        try await start()
        try require(game.state.int("revision") == 274, "revision 274")
        let x = game.player.int("x"), z = game.player.int("z")
        game.move(x: x + 1, z: z)
        try await wait("server movement") { self.game.player.int("x") != x || self.game.player.int("z") != z }
        if let item = game.state.objects("inventory").first(where: { $0.strings("ops").contains(where: { ["Wield", "Wear"].contains($0) }) }),
           let wield = item.strings("ops").firstIndex(where: { ["Wield", "Wear"].contains($0) }) {
            let parts = signature(game.player.objects("parts")), originalComponent = item.int("component")
            game.itemAction(item, kind: "inventory", op: wield + 1)
            try await wait("equip original item and change appearance") { self.signature(self.game.player.objects("parts")) != parts && !self.game.state.objects("inventory").contains { $0.int("id") == item.int("id") && $0.int("component") == originalComponent } }
            game.selectTab(4); try await wait("equipment tab") { self.game.activeTab == 4 }
            guard let equipped = game.state.objects("inventory").first(where: { $0.int("id") == item.int("id") && self.itemButton($0, named: "Remove") != nil }), let remove = itemButton(equipped, named: "Remove") else { try require(false, "equipment Remove available"); return }
            game.itemAction(equipped, kind: "invbutton", op: remove)
            try await wait("equipment removal") { self.game.state.objects("inventory").contains { $0.int("id") == item.int("id") && $0.int("component") == originalComponent } }
        } else { try require(false, "fresh equipment available") }
        game.selectTab(3); try await wait("inventory tab") { self.game.activeTab == 3 }
        guard let hans = game.state.objects("npcs").first(where: { $0.string("name") == "Hans" }), let talk = op(hans, containing: "talk") else { try require(false, "Hans Talk available"); return }
        game.target(kind: "npc", actor: hans, op: talk)
        try await wait("Hans dialogue", seconds: 45) { self.game.state.int("chatRoot", -1) >= 0 }
        guard let button = game.state.objects("ui").first(where: { $0.int("root") == game.state.int("chatRoot") && $0.int("button") == 6 }) else { try require(false, "Continue available"); return }
        let oldRoot = game.state.int("chatRoot"), oldWidgets = signature(game.state.objects("ui").filter { $0.int("root") == oldRoot })
        game.activateWidget(button)
        try await wait("dialogue Continue changes server interface") { self.game.state.int("chatRoot") != oldRoot || self.signature(self.game.state.objects("ui").filter { $0.int("root") == oldRoot }) != oldWidgets }
        try await close()
        guard let item = game.state.objects("inventory").first(where: { $0.strings("ops").contains("Drop") && $0.int("count", 1) == 1 }), let drop = item.strings("ops").firstIndex(of: "Drop") else { try require(false, "single droppable inventory item"); return }
        let id = item.int("id"), identity = GameContract.itemIdentity(item)
        game.itemAction(item, kind: "inventory", op: drop + 1)
        try await wait("drop removes held item and creates ground item") { !self.game.state.objects("inventory").contains { GameContract.itemIdentity($0) == identity } && self.game.state.objects("objects").contains { $0.int("id") == id } }
        guard let ground = game.state.objects("objects").first(where: { $0.int("id") == id }), let take = op(ground, containing: "take") else { try require(false, "ground Take available"); return }
        game.target(kind: "obj", actor: ground, op: take)
        try await wait("pickup restores held item") { self.game.state.objects("inventory").contains { $0.int("id") == id } }
        for tab in game.availableTabs {
            game.selectTab(tab); try await wait("tab \(tab)", seconds: 5) { self.game.activeTab == tab }
        }
    }

    func recipe() async throws {
        try await start()
        let woodBefore = game.state.ints("experience")[8], fireBefore = game.state.ints("experience")[11]
        guard let tree = game.nearbyTargets.first(where: { $0.string("kind") == "loc" && $0.object("actor").string("name") == "Tree" && self.op($0.object("actor"), containing: "chop") != nil })?.object("actor"), let chop = op(tree, containing: "chop") else { try require(false, "ordinary Tree available"); return }
        game.target(kind: "loc", actor: tree, op: chop)
        try await wait("woodcutting produces Logs and XP", seconds: 90) { self.game.state.ints("experience")[8] > woodBefore && self.count("Logs") > 0 }
        guard let logs = held("Logs").first, let tinderbox = held("Tinderbox").first else { try require(false, "recipe prerequisites earned and present"); return }
        game.selectItem(tinderbox); game.itemTarget(logs)
        try await wait("tinderbox on Logs produces Firemaking XP", seconds: 60) { self.game.state.ints("experience")[11] > fireBefore }
        try require(true, "original recipe XP", "Woodcutting +\((game.state.ints("experience")[8] - woodBefore) / 10), Firemaking +\((game.state.ints("experience")[11] - fireBefore) / 10)")
    }

    func magic() async throws {
        try await start()
        try await move(3250, 3226, seconds: 45)
        game.selectTab(6); try await wait("magic tab") { self.game.activeTab == 6 }
        guard let spell = game.state.objects("ui").first(where: { $0.int("button") == 2 && $0.string("action").lowercased().contains("wind strike") }) else { try require(false, "Wind Strike available"); return }
        let targets = game.nearbyTargets.filter { $0.string("kind") == "npc" && $0.object("actor").string("name") == "Goblin" && $0.object("actor").int("x") >= 3246 && $0.object("actor").int("z") >= 3217 && $0.object("actor").int("hp") > 0 }
        guard let target = targets.first?.object("actor") else { try require(false, "outdoor combat target available"); return }
        let xp = game.state.ints("experience")[6], runes = count("Mind rune")
        try require(runes > 0, "tutorial starting runes present")
        game.activateWidget(spell); game.target(kind: "npc", actor: target)
        try await wait("Wind Strike grants Magic XP and consumes rune", seconds: 40) { self.game.state.ints("experience")[6] > xp && self.count("Mind rune") < runes }
        try require(true, "native spell result", "Magic XP +\((game.state.ints("experience")[6] - xp) / 10), mind runes consumed \(runes - count("Mind rune"))")
        game.move(x: game.player.int("x") + 4, z: game.player.int("z") + 4)
        try await Task.sleep(nanoseconds: 1_500_000_000)
    }

    func commerce() async throws {
        try await start(); try await move(3216, 3244, seconds: 45)
        guard let merchant = game.state.objects("npcs").first(where: { $0.string("name") == "Shop keeper" }), let trade = op(merchant, containing: "trade") else { try require(false, "Shop keeper Trade available"); return }
        game.target(kind: "npc", actor: merchant, op: trade)
        try await wait("general store opens", seconds: 40) { self.game.state.objects("inventory").contains { self.itemButton($0, named: "Buy 1") != nil } }
        let coinsBefore = count("Coins")
        guard let sale = game.state.objects("inventory").first(where: { ["Bronze dagger", "Bronze sword", "Shortbow"].contains($0.string("name")) && self.itemButton($0, named: "Sell 1") != nil }), let sell = itemButton(sale, named: "Sell 1") else { try require(false, "starting item can be sold"); return }
        let heldBefore = count(sale.string("name"))
        game.itemAction(sale, kind: "invbutton", op: sell)
        try await wait("sale removes item and pays coins") { self.count("Coins") > coinsBefore && self.count(sale.string("name")) < heldBefore }
        let potBefore = count("Pot"), purchaseCoins = count("Coins")
        guard let pot = game.state.objects("inventory").first(where: { $0.string("name") == "Pot" && self.itemButton($0, named: "Buy 1") != nil }), let buy = itemButton(pot, named: "Buy 1") else { try require(false, "Pot Buy available"); return }
        game.itemAction(pot, kind: "invbutton", op: buy)
        try await wait("purchase grants Pot and spends coins") { self.count("Pot") > potBefore && self.count("Coins") < purchaseCoins }
        try await close()
        for (x, z) in [(3150, 3235), (3100, 3248), (3093, 3244)] { try await move(x, z) }
        guard let booth = game.state.objects("locs").first(where: { $0.int("id") == 2213 && $0.int("z") == 3243 }),
              let bank = op(booth, containing: "quickly") ?? op(booth, containing: "bank") else { try require(false, "Draynor bank booth quick action available"); return }
        game.target(kind: "loc", actor: booth, op: bank)
        try await wait("bank opens", seconds: 40) { self.game.state.objects("inventory").contains { self.itemButton($0, named: "Deposit 1") != nil } }
        guard let deposit = game.state.objects("inventory").first(where: { $0.string("name") == "Pot" && self.itemButton($0, named: "Deposit 1") != nil }), let depositOp = itemButton(deposit, named: "Deposit 1") else { try require(false, "owned Pot Deposit available"); return }
        let heldPots = count("Pot")
        game.itemAction(deposit, kind: "invbutton", op: depositOp)
        try await wait("bank deposit moves owned Pot") { self.count("Pot") < heldPots && self.game.state.objects("inventory").contains { $0.string("name") == "Pot" && self.itemButton($0, named: "Withdraw 1") != nil } }
        guard let withdraw = game.state.objects("inventory").first(where: { $0.string("name") == "Pot" && self.itemButton($0, named: "Withdraw X") != nil }), let withdrawOp = itemButton(withdraw, named: "Withdraw X") else { try require(false, "Withdraw X available"); return }
        game.itemAction(withdraw, kind: "invbutton", op: withdrawOp)
        try await wait("Withdraw X opens amount entry") { self.game.state.bool("countDialog") }
        game.send(["kind": "count", "id": 1])
        try await wait("amount entry restores held Pot") { !self.game.state.bool("countDialog") && self.count("Pot") == heldPots }
        try await close()
    }
    func melee() async throws {
        try await start(); try await move(3250, 3226, seconds: 45)
        guard let weapon = held("Bronze sword").first, let wield = op(weapon, containing: "wield") else { try require(false, "starting melee weapon available"); return }
        let appearance = signature(game.player.objects("parts"))
        game.itemAction(weapon, kind: "inventory", op: wield)
        try await wait("melee weapon equipped") { self.signature(self.game.player.objects("parts")) != appearance }
        guard let target = game.nearbyTargets.first(where: { $0.string("kind") == "npc" && $0.object("actor").string("name") == "Goblin" && $0.object("actor").int("x") >= 3246 && $0.object("actor").int("z") >= 3217 && $0.object("actor").int("hp") > 0 })?.object("actor"), let attack = op(target, containing: "attack") else { try require(false, "outdoor melee target available"); return }
        let id = target.int("id"), hp = target.int("hp"), experience = game.state.ints("experience"), before = experience[0] + experience[1] + experience[2]
        game.target(kind: "npc", actor: target, op: attack)
        try await wait("melee damages NPC and grants combat XP", seconds: 75) {
            let xp = self.game.state.ints("experience")
            let damaged = self.game.state.objects("npcs").contains { $0.int("id") == id && $0.int("hp") < hp }
                || self.game.state.objects("npcDeaths").contains { $0.int("id") == id && $0.int("hp") == 0 }
            return xp.count > 2 && xp[0] + xp[1] + xp[2] > before && damaged
        }
        let xp = game.state.ints("experience")
        try require(true, "native melee result", "Combat XP +\((xp[0] + xp[1] + xp[2] - before) / 10)")
        game.runEnabled = true; game.move(x: game.player.int("x") + 5, z: game.player.int("z") + 5)
        try await Task.sleep(nanoseconds: 1_500_000_000)
    }

    func persistenceSeed() async throws {
        try await start()
        game.move(x: 3231, z: 3227)
        try await wait("fixture character moves before process exit") { self.game.player.int("x") == 3231 && self.game.player.int("z") == 3227 }
        let saved = NativeSessionCredential.read(endpoint: game.endpoint, username: game.username)
        try require(saved?.token == game.token && saved?.token != nil && saved?.previouslyConnected == true, "session bearer saved only in scoped Keychain")
        try require(NativeSessionCredential.read(endpoint: game.endpoint + "/other", username: game.username) == nil
                    && NativeSessionCredential.read(endpoint: game.endpoint, username: game.username + "other") == nil, "session credential isolated by origin path and character")
        let settings = GameSession()
        try require(settings.endpoint == game.endpoint && settings.username == game.username, "nonsecret connection settings restored")
        // Main deliberately exits this process without disconnecting, matching force quit.
    }
    func persistenceResume() async throws {
        let restoredSettings = GameSession()
        try require(restoredSettings.endpoint == game.endpoint && restoredSettings.username == game.username, "connection preferences survive process exit")
        let saved = NativeSessionCredential.read(endpoint: game.endpoint, username: game.username)
        let before = try await stats().objects("logins").count
        try require(saved?.token != nil, "separate process reads its Keychain bearer")
        try await start()
        let resumedStats = try await stats()
        try require(game.token == saved?.token && resumedStats.objects("logins").count == before, "fresh process resumes with GET and no duplicate login")
        try require(game.player.int("x") == 3231 && game.player.int("z") == 3227, "fresh process preserves character position")
    }
    func persistenceExpired() async throws {
        let old = NativeSessionCredential.read(endpoint: game.endpoint, username: game.username)?.token
        try require(old != nil, "third process retains scoped recovery record")
        try await control("expire_all")
        let before = try await stats().objects("logins").count
        try await start()
        let logins = try await stats().objects("logins")
        try require(game.token != old && logins.count == before + 1 && logins.last?.bool("startLumbridge", true) == false,
                    "expired stored bearer falls back without Lumbridge reset")
        try require(game.player.int("x") == 3231 && game.player.int("z") == 3227, "expired-session recovery preserves saved location")
        let otherEndpoint = game.endpoint + "/isolated-qa-scope"
        try NativeSessionCredential.save(.init(token: "isolated-fixture-only", previouslyConnected: true), endpoint: otherEndpoint, username: game.username)
        defer { try? NativeSessionCredential.removeRecord(endpoint: otherEndpoint, username: game.username) }
        game.disconnect(); try await Task.sleep(nanoseconds: 400_000_000)
        let cleared = NativeSessionCredential.read(endpoint: game.endpoint, username: game.username)
        let logoutStats = try await stats()
        try require(cleared?.token == nil && cleared?.previouslyConnected == true && logoutStats.object("sessions").isEmpty,
                    "explicit Disconnect deletes remote session and clears bearer")
        try require(NativeSessionCredential.read(endpoint: otherEndpoint, username: game.username)?.token == "isolated-fixture-only",
                    "logout preserves other scoped credentials")
    }

    func reorder() async throws {
        try await start()
        game.selectTab(3); try await wait("inventory tab for rearranging") { self.game.activeTab == 3 }
        let inventory = game.state.objects("inventory").filter { self.game.canReorderInventory($0) }.sorted { $0.int("slot") < $1.int("slot") }
        guard inventory.count >= 2, let source = inventory.first, let destination = inventory.dropFirst().first,
              let empty = (0..<28).reversed().first(where: { slot in !inventory.contains { $0.int("slot") == slot } }) else {
            try require(false, "carried items and empty inventory slot available"); return
        }
        let originalCounts = signature(heldInventoryCounts()), originalSlots = inventory.map(GameContract.itemIdentity)
        let payload = game.inventoryDragPayload(source), sourceSlot = source.int("slot"), destinationSlot = destination.int("slot")
        try require(!game.dropInventory("tablescape:foreign:0:3214:0:1351", to: empty, expectedDestination: nil), "foreign drag payload rejected")
        try require(!game.reorderInventory(source, to: 28, expectedDestination: nil), "out-of-range slot rejected")
        try require(!game.reorderInventory(source, to: destinationSlot, expectedDestination: nil), "changed destination rejected")
        game.beginInventoryMove(source)
        try require(game.inventoryMoveSource != nil && game.completeInventoryMove(to: empty, expectedDestination: nil), "accessible Move queues original slot action")
        try await wait("empty-slot move confirmed by original server") {
            !self.game.rearrangingInventory
                && self.game.state.objects("inventory").contains { $0.int("component") == source.int("component") && $0.int("id") == source.int("id") && $0.int("slot") == empty }
                && !self.game.state.objects("inventory").contains { $0.int("component") == source.int("component") && $0.int("slot") == sourceSlot }
        }
        try require(!game.dropInventory(payload, to: destinationSlot, expectedDestination: destination), "drag from stale source slot rejected")
        guard let moved = game.state.objects("inventory").first(where: { $0.int("component") == source.int("component") && $0.int("slot") == empty }) else { try require(false, "moved item readback"); return }
        try require(game.dropInventory(game.inventoryDragPayload(moved), to: destinationSlot, expectedDestination: destination), "native drag drop queues occupied-slot swap")
        try require(!game.reorderInventory(moved, to: sourceSlot, expectedDestination: nil), "duplicate reorder waits for server state")
        try await wait("occupied slots swap without shifting other items") {
            let current = self.game.state.objects("inventory").filter { $0.int("component") == source.int("component") }
            return !self.game.rearrangingInventory
                && current.contains { $0.int("slot") == destinationSlot && $0.int("id") == source.int("id") }
                && current.contains { $0.int("slot") == empty && $0.int("id") == destination.int("id") }
                && inventory.dropFirst(2).allSatisfy { old in current.contains { GameContract.itemIdentity($0) == GameContract.itemIdentity(old) } }
        }
        try require(signature(heldInventoryCounts()) == originalCounts, "rearranging conserves exact item quantities")
        guard let swappedSource = game.state.objects("inventory").first(where: { $0.int("component") == source.int("component") && $0.int("slot") == destinationSlot }) else { try require(false, "swapped source readback"); return }
        game.reorderInventory(swappedSource, to: sourceSlot, expectedDestination: nil)
        try await wait("restore source to original slot") { !self.game.rearrangingInventory && self.game.state.objects("inventory").contains { GameContract.itemIdentity($0) == GameContract.itemIdentity(source) } }
        guard let swappedDestination = game.state.objects("inventory").first(where: { $0.int("component") == destination.int("component") && $0.int("slot") == empty }) else { try require(false, "swapped destination readback"); return }
        game.reorderInventory(swappedDestination, to: destinationSlot, expectedDestination: nil)
        try await wait("restore exact original inventory layout") {
            !self.game.rearrangingInventory && self.game.state.objects("inventory").filter { $0.int("component") == source.int("component") }
                .sorted { $0.int("slot") < $1.int("slot") }.map(GameContract.itemIdentity) == originalSlots
        }
    }

    func transitionSnapshot(_ stage: String) {
        transitions.append(["stage": stage, "tick": game.state.int("tick"), "level": game.state.int("level"),
                            "x": game.player.int("x"), "z": game.player.int("z"), "regionX": game.state.int("regionX"),
                            "regionZ": game.state.int("regionZ"), "backgroundLocs": game.state.objects("backgroundLocs").count])
        save()
    }
    func transition() async throws {
        try await start()
        let originalFloor = game.state.int("level"), originalRegionX = game.state.int("regionX"), originalRegionZ = game.state.int("regionZ")
        try require(originalFloor == 0, "fresh character starts on the ground floor")
        transitionSnapshot("ground before climbing")
        try await move(3225, 3223, seconds: 35)
        if let door = game.state.objects("locs").first(where: { $0.int("x") == 3226 && $0.int("z") == 3223 && self.op($0, containing: "open") != nil }),
           let open = op(door, containing: "open") {
            let originalID = door.int("id")
            game.target(kind: "loc", actor: door, op: open)
            try await wait("tower door opens through its advertised operation", seconds: 25) {
                !self.game.state.objects("locs").contains { $0.int("x") == 3226 && $0.int("z") == 3223 && $0.int("id") == originalID }
            }
        } else {
            try require(game.state.objects("locs").contains { $0.int("x") == 3227 && $0.int("z") == 3223 && self.op($0, containing: "close") != nil }, "tower entry door is already open")
        }
        guard let ladder = game.state.objects("locs").first(where: { $0.int("x") == 3229 && $0.int("z") == 3224 && self.op($0, containing: "climb-up") != nil }),
              let up = op(ladder, containing: "climb-up") else { try require(false, "Lumbridge tower advertises Climb-up"); return }
        game.target(kind: "loc", actor: ladder, op: up)
        try await wait("original ladder moves player upstairs", seconds: 35) { self.game.state.int("level") == originalFloor + 1 }
        transitionSnapshot("upstairs")
        try require(!game.state.objects("backgroundLocs").isEmpty, "upper floor state retains lower-floor scenery")
        let upstairsX = game.player.int("x"), upstairsZ = game.player.int("z"), upstairsLevel = game.state.int("level")
        let inventoryBefore = signature(heldInventoryCounts()), epoch = game.sessionEpoch
        guard let ownedToken = game.token else { try require(false, "owned session available for expiry check"); return }
        // End only this test character's session through the public logout route. The native
        // polling loop must observe 401 and use its real startLumbridge:false recovery path.
        var request = URLRequest(url: URL(string: game.endpoint + "/v1/session")!)
        request.httpMethod = "DELETE"; request.setValue("Bearer " + ownedToken, forHTTPHeaderField: "Authorization")
        if let key = NativeBridgeCredential.read(endpoint: game.endpoint) { request.setValue(key, forHTTPHeaderField: "X-TableScape-Bridge-Key") }
        let (_, response) = try await URLSession.shared.data(for: request)
        try require((response as? HTTPURLResponse)?.statusCode == 200, "expire only this QA session through ordinary logout")
        try await wait("native session recovery reconnects upstairs", seconds: 30) {
            self.game.sessionEpoch > epoch && self.game.connected && self.game.token != ownedToken
                && self.game.state.int("level") == upstairsLevel
                && self.game.player.int("x") == upstairsX && self.game.player.int("z") == upstairsZ
        }
        try require(signature(heldInventoryCounts()) == inventoryBefore, "recovery preserves held inventory")
        transitionSnapshot("reconnected upstairs without Lumbridge reset")
        guard let downLadder = game.state.objects("locs").first(where: { $0.int("x") == 3229 && $0.int("z") == 3224 && self.op($0, containing: "climb-down") != nil }),
              let down = op(downLadder, containing: "climb-down") else { try require(false, "upper-floor ladder advertises Climb-down"); return }
        game.target(kind: "loc", actor: downLadder, op: down)
        try await wait("original ladder returns player to the ground floor", seconds: 25) { self.game.state.int("level") == originalFloor }
        transitionSnapshot("ground after climbing down")
        try await move(3250, 3226, seconds: 45)
        try require(game.state.int("regionX") != originalRegionX || game.state.int("regionZ") != originalRegionZ, "walking crosses original region streaming origin")
        transitionSnapshot("walked into next region")
        let chunkX = game.player.int("x") / 16 * 16, chunkZ = game.player.int("z") / 16 * 16
        let chunk = try await game.json(path: "/v1/chunk?x=\(chunkX)&z=\(chunkZ)&level=\(originalFloor)")
        let meshes = chunk.objects("meshes"), vertexCount = meshes.reduce(0) { $0 + $1.doubles("vertices").count / 3 }
        try require(chunk.int("revision") == 274 && chunk.int("x") == chunkX && chunk.int("z") == chunkZ
                    && chunk.int("level") == originalFloor && vertexCount > 100
                    && meshes.allSatisfy { !$0.doubles("vertices").isEmpty && $0.doubles("vertices").count % 9 == 0
                        && $0.doubles("colours").count == $0.doubles("vertices").count
                        && $0.doubles("uv").count * 3 == $0.doubles("vertices").count * 2 },
                    "new region serves native terrain geometry", "Original terrain vertices: \(vertexCount)")
    }
    func heldInventoryCounts() -> JSONObject {
        let roots = game.state.ints("tabs"), inventoryRoot = roots.count > 3 ? roots[3] : -2
        var counts: JSONObject = [:]
        for item in game.state.objects("inventory") where item.int("root", -1) == inventoryRoot {
            let id = String(item.int("id")); counts[id] = (counts[id] as? Int ?? 0) + item.int("count", 1)
        }
        return counts
    }

    func control(_ mode: String) async throws {
        var request = URLRequest(url: URL(string: game.endpoint + "/__mode")!); request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode]); _ = try await URLSession.shared.data(for: request)
    }
    func trade() async throws {
        try await start()
        let peer = GameSession(); peer.audioEnabled = false; peer.endpoint = game.endpoint; peer.username = name(); peers.append(peer); peer.connect()
        try await wait("second native session") { peer.connected }
        try await wait("mutual player visibility") {
            self.game.state.objects("players").contains { $0.string("name").lowercased() == peer.username }
                && peer.state.objects("players").contains { $0.string("name").lowercased() == self.game.username }
        }
        guard let target = game.state.objects("players").first(where: { $0.string("name").lowercased() == peer.username }), let request = op(target, containing: "trade") else { try require(false, "player Trade action"); return }
        let swordA = count("Bronze sword"), tinderA = count("Tinderbox"), swordB = count("Bronze sword", in: peer), tinderB = count("Tinderbox", in: peer)
        try require(swordA > 0 && tinderB > 0, "independently owned starting trade items")
        game.target(kind: "player", actor: target, op: request)
        try await wait("trade request reaches peer") { peer.state.strings("messages").contains { $0.lowercased().contains(self.game.username) && $0.lowercased().contains("trade") } }
        guard let other = peer.state.objects("players").first(where: { $0.string("name").lowercased() == game.username }), let response = op(other, containing: "trade") else { try require(false, "peer Trade response"); return }
        peer.target(kind: "player", actor: other, op: response)
        try await wait("both original trade interfaces open") { self.game.state.int("mainRoot") == 3323 && peer.state.int("mainRoot") == 3323 }
        guard let offerA = game.state.objects("inventory").first(where: { $0.string("name") == "Bronze sword" && self.itemButton($0, named: "Offer 1") != nil }),
              let offerB = peer.state.objects("inventory").first(where: { $0.string("name") == "Tinderbox" && self.itemButton($0, named: "Offer 1") != nil }),
              let opA = itemButton(offerA, named: "Offer 1"), let opB = itemButton(offerB, named: "Offer 1") else { try require(false, "owned Offer actions"); return }
        game.itemAction(offerA, kind: "invbutton", op: opA); peer.itemAction(offerB, kind: "invbutton", op: opB)
        try await wait("trade offers attributed to the correct player") {
            self.game.state.objects("inventory").contains { $0.string("title") == "Your offer" && $0.string("name") == "Bronze sword" && $0.int("count") == 1 }
                && self.game.state.objects("inventory").contains { $0.string("title") == "Other player's offer" && $0.string("name") == "Tinderbox" && $0.int("count") == 1 }
                && peer.state.objects("inventory").contains { $0.string("title") == "Your offer" && $0.string("name") == "Tinderbox" && $0.int("count") == 1 }
                && peer.state.objects("inventory").contains { $0.string("title") == "Other player's offer" && $0.string("name") == "Bronze sword" && $0.int("count") == 1 }
        }
        guard let acceptA = game.state.objects("ui").first(where: { $0.int("id") == 3420 && $0.int("root") == 3323 }),
              let acceptB = peer.state.objects("ui").first(where: { $0.int("id") == 3420 && $0.int("root") == 3323 }) else { try require(false, "live first-stage Accept controls"); return }
        game.activateWidget(acceptA); peer.activateWidget(acceptB)
        try await wait("both trades reach independent confirmation stage") { self.game.state.int("mainRoot") == 3443 && peer.state.int("mainRoot") == 3443 }
        guard let confirmA = game.state.objects("ui").first(where: { $0.int("id") == 3546 && $0.int("root") == 3443 }),
              let confirmB = peer.state.objects("ui").first(where: { $0.int("id") == 3546 && $0.int("root") == 3443 }) else { try require(false, "live second-stage Accept controls"); return }
        game.activateWidget(confirmA); peer.activateWidget(confirmB)
        try await wait("two-stage trade transfers exactly the offered items") {
            self.game.state.int("mainRoot", -1) < 0 && peer.state.int("mainRoot", -1) < 0
                && self.count("Bronze sword") == swordA - 1 && self.count("Tinderbox") == tinderA + 1
                && self.count("Bronze sword", in: peer) == swordB + 1 && self.count("Tinderbox", in: peer) == tinderB - 1
        }
    }
    func stats() async throws -> JSONObject {
        let (data, _) = try await URLSession.shared.data(from: URL(string: game.endpoint + "/__stats")!)
        return try JSONSerialization.jsonObject(with: data) as! JSONObject
    }
    func fault() async throws {
        let sparse: JSONObject = ["ops": [NSNull(), "null", "Follow", "Trade with", "null"]]
        try require(sparse.strings("ops") == ["", "", "Follow", "Trade with", ""], "sparse player operations retain protocol indexes")
        try require(NativeBridgeCredential.endpointKey("https://Example.COM:443/game/") == "https://example.com/game", "bridge credential endpoint normalized")
        try await start()
        try await control("action_lost"); game.send(["kind": "move", "x": 3223, "z": 3218]); game.send(["kind": "move", "x": 3224, "z": 3218])
        try await wait("uncertain action pauses") { !self.game.connected }
        try await wait("read recovery") { self.game.connected }
        try require(try await stats().int("actions") == 1, "uncertain action never replayed and queued click discarded")
        try require(game.notice.contains("not confirmed"), "uncertain result visible to player")
        try await control("stale"); let tick = game.state.int("tick"); try await Task.sleep(nanoseconds: 500_000_000)
        try require(game.state.int("tick") >= tick, "older snapshot ignored")
        try await control("expired_once"); try await wait("expired session replaced") { self.game.sessionEpoch >= 2 && self.game.connected }
        let replacement = try await stats()
        try require(replacement.objects("logins").last?.bool("startLumbridge", true) == false, "recovery preserves character location")
        try await control("malformed"); try await wait("malformed state stops cleanly") { !self.game.connected && !self.game.connecting }
        try require(game.status.contains("unreadable"), "readable malformed-data message")
        try await control("normal"); game.connect(); try await wait("manual reconnect") { self.game.connected }
        try await control("redirect"); try await wait("redirect response stops cleanly") { !self.game.connected && !self.game.connecting }
        try require(try await stats().int("redirectHits") == 0, "redirect destination never receives a request")
        try await control("normal"); game.connect(); try await wait("reconnect after rejected redirect") { self.game.connected }
        try await control("unavailable"); try await wait("persistent outage stops after bounded retries", seconds: 40) { !self.game.connected && !self.game.connecting }
        try require(try await stats().int("failedStates") == 5, "exactly five failed state attempts")
        try await control("normal"); game.connect(); try await wait("manual recovery after retry limit") { self.game.connected }
        game.disconnect(); try await Task.sleep(nanoseconds: 300_000_000)
        try await control("delayed_login"); game.connect(); try await Task.sleep(nanoseconds: 150_000_000); game.disconnect()
        try await Task.sleep(nanoseconds: 2_200_000_000)
        let final = try await stats()
        try require(final.object("sessions").isEmpty && !game.connected && game.token == nil && game.state.isEmpty, "canceled late login released and view stays logged out")
    }
}

@main struct NativeCoreChecks {
    @MainActor static func main() async {
        let mode = CommandLine.arguments.dropFirst().first ?? "fault", suite = CoreChecks(mode)
        if mode == "persistence_cleanup" {
            do {
                try NativeSessionCredential.removeRecord(endpoint: suite.game.endpoint, username: suite.game.username)
                try NativeSessionCredential.removeRecord(endpoint: suite.game.endpoint + "/isolated-qa-scope", username: suite.game.username)
                exit(0)
            } catch { print("QA recovery record cleanup failed: " + error.localizedDescription); exit(1) }
        }
        var succeeded = false
        do {
            switch mode {
            case "live": try await suite.live()
            case "recipe": try await suite.recipe()
            case "magic": try await suite.magic()
            case "melee": try await suite.melee()
            case "commerce": try await suite.commerce()
            case "trade": try await suite.trade()
            case "transition": try await suite.transition()
            case "reorder": try await suite.reorder()
            case "persistence_seed": try await suite.persistenceSeed()
            case "persistence_resume": try await suite.persistenceResume()
            case "persistence_expired": try await suite.persistenceExpired()
            case "fault": try await suite.fault()
            default: throw CheckFailure.failed("Unknown suite " + mode)
            }
            succeeded = true
        } catch { print("FAILED \(mode): \(error)"); fflush(stdout) }
        if succeeded && ["persistence_seed", "persistence_resume"].contains(mode) { suite.save() }
        else { await suite.finish() }
        print("RESULT \(mode) \(succeeded ? "PASSED" : "FAILED") \(suite.checks.count) checks")
        exit(succeeded ? 0 : 1)
    }
}
