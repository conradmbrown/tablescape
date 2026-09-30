import Foundation
import Combine

@MainActor
final class GameSession: ObservableObject {
    @Published private(set) var state: JSONObject = [:]
    @Published private(set) var status = "Ready to connect"
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var revision = 0
    @Published private(set) var sessionEpoch = 0
    @Published private(set) var notice = ""
    @Published private(set) var actionCount = 0
    @Published private(set) var stateCount = 0
    @Published var endpoint = "http://127.0.0.1:18890"
    @Published var username = "unitymetal"
    @Published var bridgeKeyInput = ""
    @Published private(set) var bridgeKeyConfigured = false
    @Published var selectedTarget: JSONObject?
    @Published private(set) var targetMenuRequest = 0
    @Published var selectedItem: JSONObject?
    @Published var selectedSpell: JSONObject?
    @Published private(set) var inventoryMoveSource: JSONObject?
    @Published private(set) var rearrangingInventory = false
    @Published var runEnabled = false
    @Published var musicVolume = 0.45
    @Published var soundVolume = 0.7
    @Published var audioEnabled = true
    private(set) var token: String?
    private(set) var lastAction: JSONObject?
    private var actions: [JSONObject] = []
    private let inventoryDragScope = UUID().uuidString
    private struct InventoryReorder {
        let component: Int, source: Int, destination: Int, sourceID: Int
        let destinationID: Int?
        let expires: TimeInterval
    }
    private var inventoryReorder: InventoryReorder?
    private var runner: Task<Void, Never>?
    private var generation = 0
    private var everConnected = false
    private var connectedUsername = ""
    private var connectionEndpoint: String?
    private let preferences: UserDefaults
    private var sessionRecoverySaved = false
    private var uncertainAction = false
    private var latestTick = -1
    private var nearbyCacheRevision = -1
    private var nearbyCache: [JSONObject] = []
    private var lastServerRunning: Bool?
    private let transport: URLSession
    private var bridgeKeys: [String: String] = [:]
    private var bridgeKeysLoaded = Set<String>()
    private struct RequestMetric { let path: String; let milliseconds: Double; let bytes: Int; let status: Int; let succeeded: Bool }
    private var requestMetrics: [RequestMetric] = []
    private var requestTotal = 0, requestFailures = 0, receivedBytes = 0, activeRequests = 0
    private lazy var media = GameAudio(session: self)

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        do {try NativeBridgeDeployment.importIfPresent(preferences:preferences)}
        catch {print("TABLESCAPE_CONNECTION_IMPORT_FAILED")}
        endpoint = preferences.string(forKey: "TableScape.gameEndpoint") ?? "http://127.0.0.1:18890"
        username = preferences.string(forKey: "TableScape.characterName") ?? "unitymetal"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 70
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 6
        transport = URLSession(configuration: configuration, delegate: NativeSessionTransportDelegate(), delegateQueue: nil)
    }

    var player: JSONObject { state.object("player") }
    var activeTab: Int { state.int("activeTab", 3) }
    var selectionLabel: String {
        if let selectedItem { return "Use \(selectedItem.string("name")) on…" }
        if let selectedSpell { return "Cast \(gamePlain(selectedSpell.string("action", selectedSpell.string("option")))) on…" }
        return ""
    }
    func inspectBridgeCredential() {
        bridgeKeyConfigured = bridgeCredential(for: endpoint) != nil
    }
    /// Bounded transport measurements only: never includes URLs, credentials, headers or response bodies.
    func networkMetricsSnapshot() -> JSONObject {
        let reads = requestMetrics.filter { $0.path == "/v1/state" && $0.succeeded }.map(\.milliseconds).sorted()
        let writes = requestMetrics.filter { $0.path == "/v1/action" && $0.succeeded }.map(\.milliseconds).sorted()
        func percentile(_ values: [Double], _ fraction: Double) -> Double { values.isEmpty ? 0 : values[min(values.count - 1, Int(Double(values.count - 1) * fraction))] }
        return ["requests": requestTotal, "failedRequests": requestFailures, "responseBytes": receivedBytes, "activeRequests": activeRequests,
                "retainedSamples": requestMetrics.count, "readMedianMs": percentile(reads, 0.5), "readP95Ms": percentile(reads, 0.95),
                "lastReadMs": requestMetrics.last(where: { $0.path == "/v1/state" })?.milliseconds ?? 0,
                "actionMedianMs": percentile(writes, 0.5), "actionP95Ms": percentile(writes, 0.95), "actionsDispatched": actionCount,
                "validatedStates": stateCount, "queuedActions": actions.count, "sessionEpoch": sessionEpoch, "sessionRecoverySaved": sessionRecoverySaved, "sessionKeychainStatus": NativeSessionCredential.diagnosticsSnapshot()]
    }
    func saveBridgeCredential() {
        let value = bridgeKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
            notice = "The private connection key must contain 64 hexadecimal characters."; return
        }
        do {
            try NativeBridgeCredential.save(value, endpoint: endpoint)
            let key = NativeBridgeCredential.endpointKey(endpoint)
            bridgeKeys[key] = value; bridgeKeysLoaded.insert(key); bridgeKeyInput = ""; bridgeKeyConfigured = true
            notice = "Private connection key saved securely for this server."
        } catch { notice = error.localizedDescription }
    }
    func removeBridgeCredential() {
        do {
            try NativeBridgeCredential.save(nil, endpoint: endpoint)
            let key = NativeBridgeCredential.endpointKey(endpoint)
            bridgeKeys.removeValue(forKey: key); bridgeKeysLoaded.insert(key); bridgeKeyInput = ""; bridgeKeyConfigured = false
            notice = "Private connection key removed for this server."
        } catch { notice = error.localizedDescription }
    }
    private func bridgeCredential(for endpoint: String) -> String? {
        let key = NativeBridgeCredential.endpointKey(endpoint)
        if bridgeKeysLoaded.insert(key).inserted { bridgeKeys[key] = NativeBridgeCredential.read(endpoint: endpoint) }
        return bridgeKeys[key]
    }
    var availableTabs: [Int] {
        let tabs = state.ints("tabs")
        return tabs.indices.filter { tabs[$0] >= 0 && $0 != 7 && $0 < GameContract.tabNames.count }
    }
    /// Sorting is only requested by the expanded Nearby panel and cached until the
    /// next validated state. Comparator work is numeric, never JSON dictionary casts.
    var nearbyTargets: [JSONObject] {
        if nearbyCacheRevision == revision { return nearbyCache }
        let x = player.double("x"), z = player.double("z")
        var candidates: [(distanceSquared: Double, key: String, value: JSONObject)] = []
        for (collection, kind) in [("npcs", "npc"), ("locs", "loc"), ("objects", "obj"), ("players", "player")] {
            for actor in state.objects(collection) {
                guard kind == "obj" || actor.strings("ops").contains(where: { !$0.isEmpty }) else { continue }
                let dx = actor.double("x") - x, dz = actor.double("z") - z, distance = dx * dx + dz * dz
                let key = GameContract.identity(kind: kind, actor: actor)
                candidates.append((distance, key, ["kind": kind, "actor": actor, "key": key, "distance": sqrt(distance)]))
            }
        }
        candidates.sort { $0.distanceSquared == $1.distanceSquared ? $0.key < $1.key : $0.distanceSquared < $1.distanceSquared }
        nearbyCache = candidates.map(\.value); nearbyCacheRevision = revision
        return nearbyCache
    }
    /// World selection refreshes one collection directly. It must not sort the full
    /// scenery list simply because a target panel remains open during state polling.
    private func currentTarget(kind: String, actor: JSONObject) -> JSONObject? {
        let collection: String
        switch kind {
        case "npc": collection = "npcs"
        case "loc": collection = "locs"
        case "obj": collection = "objects"
        case "player": collection = "players"
        default: return nil
        }
        let key = actor.string("key"), id = actor.int("id")
        guard let current = state.objects(collection).first(where: { key.isEmpty ? $0.int("id") == id : $0.string("key") == key }) else { return nil }
        return ["kind": kind, "actor": current, "key": GameContract.identity(kind: kind, actor: current)]
    }

    func connect() {
        guard runner == nil else { return }
        guard username.range(of: "^unity[a-z0-9_]{0,7}$", options: .regularExpression) != nil else {
            notice = "Choose unity followed by up to seven lowercase letters, numbers or underscores."
            return
        }
        guard let url = URL(string: endpoint), ["http", "https"].contains(url.scheme ?? ""), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            notice = "Enter a valid game server address."
            return
        }
        let normalizedEndpoint = NativeBridgeCredential.endpointKey(endpoint)
        if connectedUsername != username || connectionEndpoint != normalizedEndpoint {
            token = nil; everConnected = false; sessionRecoverySaved = false; clearSessionView()
        }
        endpoint = normalizedEndpoint; connectionEndpoint = normalizedEndpoint; connectedUsername = username
        if let saved = NativeSessionCredential.read(endpoint: normalizedEndpoint, username: connectedUsername) {
            if token == nil { token = saved.token }
            sessionRecoverySaved = saved.token != nil
            everConnected = everConnected || saved.previouslyConnected
        }
        preferences.set(normalizedEndpoint, forKey: "TableScape.gameEndpoint")
        preferences.set(connectedUsername, forKey: "TableScape.characterName")
        inspectBridgeCredential()
        generation += 1
        sessionEpoch += 1
        let expectedGeneration = generation
        connecting = true
        connected = false
        notice = ""
        status = token == nil ? "Connecting…" : "Resuming your character…"
        runner = Task { [weak self] in await self?.run(expectedGeneration) }
    }

    func disconnect() {
        let abandonedToken = token, abandonedEndpoint = connectionEndpoint ?? endpoint, abandonedUsername = connectedUsername
        if !abandonedUsername.isEmpty {
            do { try NativeSessionCredential.clearToken(endpoint: abandonedEndpoint, username: abandonedUsername, matching: abandonedToken) }
            catch { notice = error.localizedDescription }
        }
        generation += 1
        sessionEpoch += 1
        runner?.cancel()
        runner = nil
        token = nil; sessionRecoverySaved = false
        connecting = false
        connected = false
        everConnected = false
        uncertainAction = false
        clearSessionView()
        status = "Disconnected"
        if let abandonedToken {
            Task {
                try? await self.rawData(path: "/v1/session", method: "DELETE", body: nil, bearer: abandonedToken, server: abandonedEndpoint)
            }
        }
        print("SCAPE_NATIVE_DISCONNECTED")
    }

    func send(_ action: JSONObject) {
        guard connected, token != nil else { notice = "Reconnect before performing a game action."; return }
        guard actions.count < 20 else { notice = "Please wait for the queued actions to finish."; return }
        actions.append(action)
        notice = "Queued: \(action.string("kind"))"
    }
    func move(x: Int, z: Int) { send(["kind": "move", "x": x, "z": z, "run": runEnabled]) }
    func selectTab(_ tab: Int) {
        guard availableTabs.contains(tab) else { return }
        send(["kind": "tab", "id": tab])
    }
    func showTarget(kind: String, actor: JSONObject) {
        targetMenuRequest += 1
        selectedTarget = ["kind": kind, "actor": actor, "key": GameContract.identity(kind: kind, actor: actor)]
    }
    func target(kind: String, actor: JSONObject, op: Int = 1) {
        guard let current = currentTarget(kind: kind, actor: actor)?.object("actor") else {
            notice = "That target is no longer nearby."; selectedTarget = nil; return
        }
        if selectedItem == nil && selectedSpell == nil {
            let ops = current.strings("ops")
            guard op > 0, op <= ops.count, !ops[op - 1].isEmpty else { notice = "That action is no longer available."; return }
        }
        dispatchTarget(["kind": kind, "id": current.int("id"), "x": current.int("x"), "z": current.int("z"), "op": op, "run": runEnabled])
    }
    func selectItem(_ item: JSONObject) {
        guard let item = currentItem(item), item.bool("usable") else { return }
        selectedItem = item
        selectedSpell = nil; inventoryMoveSource = nil
    }
    func cancelSelection() { selectedItem = nil; selectedSpell = nil }
    func showNotice(_ text: String) { notice = text }
    func activateItem(_ stale: JSONObject) {
        guard let item = currentItem(stale) else { return }
        if selectedItem != nil || selectedSpell != nil { itemTarget(item); return }
        let op = item.strings("ops").firstIndex(where: { !$0.isEmpty })
        let button = item.strings("buttons").firstIndex(where: { !$0.isEmpty })
        if let op, op < 4 { itemAction(item, kind: "inventory", op: op + 1) }
        else if let button { itemAction(item, kind: "invbutton", op: button + 1) }
        else if item.bool("usable") { selectItem(item) }
        else if let op { itemAction(item, kind: "inventory", op: op + 1) }
    }
    func itemAction(_ stale: JSONObject, kind: String, op: Int) {
        guard let item = currentItem(stale) else { return }
        let ops = item.strings(kind == "invbutton" ? "buttons" : "ops")
        guard op > 0, op <= ops.count, !ops[op - 1].isEmpty else { notice = "That item action is no longer available."; return }
        send(["kind": kind, "id": item.int("id"), "slot": item.int("slot"), "component": item.int("component"), "op": op])
    }
    /// Revision 274's carried inventory has 28 slots. The existing gateway sends
    /// the original swap packet; an empty destination is therefore an ordinary move.
    func canReorderInventory(_ item: JSONObject) -> Bool {
        let roots = state.ints("tabs")
        return connected && activeTab == 3 && roots.count > 3 && state.int("mainRoot", -1) < 0
            && state.int("sideRoot", -1) < 0 && item.int("root", -1) == roots[3]
            && item.int("component") == 3214 && (0..<28).contains(item.int("slot", -1))
    }
    func beginInventoryMove(_ stale: JSONObject) {
        guard let item = currentItem(stale), canReorderInventory(item), !rearrangingInventory else { return }
        cancelSelection(); inventoryMoveSource = item; notice = "Choose an inventory slot for " + item.string("name") + "."
    }
    func cancelInventoryMove() { inventoryMoveSource = nil }
    func inventoryDragPayload(_ item: JSONObject) -> String {
        guard canReorderInventory(item) else { return "" }
        return "tablescape:\(inventoryDragScope):\(sessionEpoch):\(item.int("component")):\(item.int("slot")):\(item.int("id"))"
    }
    @discardableResult
    func dropInventory(_ payload: String, to slot: Int, expectedDestination: JSONObject?) -> Bool {
        guard payload.utf8.count <= 180 else { notice = "That is not a current inventory item."; return false }
        let parts = payload.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6, parts[0] == "tablescape", parts[1] == inventoryDragScope,
              Int(parts[2]) == sessionEpoch, let component = Int(parts[3]), let source = Int(parts[4]), let id = Int(parts[5]),
              let item = state.objects("inventory").first(where: { $0.int("component") == component && $0.int("slot") == source && $0.int("id") == id }) else {
            notice = "That dragged item moved or its session ended."; return false
        }
        return reorderInventory(item, to: slot, expectedDestination: expectedDestination)
    }
    @discardableResult
    func completeInventoryMove(to slot: Int, expectedDestination: JSONObject?) -> Bool {
        guard let item = inventoryMoveSource else { return false }
        return reorderInventory(item, to: slot, expectedDestination: expectedDestination)
    }
    @discardableResult
    func reorderInventory(_ stale: JSONObject, to slot: Int, expectedDestination: JSONObject?) -> Bool {
        guard let item = currentItem(stale), canReorderInventory(item), (0..<28).contains(slot), slot != item.int("slot"),
              !rearrangingInventory, actions.count < 20 else { return false }
        let destination = state.objects("inventory").first { $0.int("component") == item.int("component") && $0.int("slot") == slot }
        guard destination.map(GameContract.itemIdentity) == expectedDestination.map(GameContract.itemIdentity),
              destination?.int("count") == expectedDestination?.int("count") else {
            notice = "That destination changed. Choose its current item or an empty slot."; return false
        }
        inventoryMoveSource = nil; cancelSelection(); rearrangingInventory = true
        inventoryReorder = InventoryReorder(component: item.int("component"), source: item.int("slot"), destination: slot,
                                            sourceID: item.int("id"), destinationID: destination?.int("id"),
                                            expires: ProcessInfo.processInfo.systemUptime + 12)
        send(["kind": "reorder", "component": item.int("component"), "slot": item.int("slot"), "targetSlot": slot])
        return true
    }
    private func reconcileInventoryReorder() {
        if let moving = inventoryMoveSource,
           !canReorderInventory(moving) || !state.objects("inventory").contains(where: { GameContract.itemIdentity($0) == GameContract.itemIdentity(moving) }) {
            inventoryMoveSource = nil
        }
        guard let pending = inventoryReorder else { return }
        let items = state.objects("inventory").filter { $0.int("component") == pending.component }
        let source = items.first { $0.int("slot") == pending.source }, destination = items.first { $0.int("slot") == pending.destination }
        let confirmed = destination?.int("id") == pending.sourceID && source?.int("id") == pending.destinationID
        if confirmed || ProcessInfo.processInfo.systemUptime >= pending.expires {
            inventoryReorder = nil; rearrangingInventory = false
            notice = confirmed ? "Inventory arranged." : "The server did not move that item. Choose a slot to try again."
        }
    }

    func itemTarget(_ stale: JSONObject) {
        guard let item = currentItem(stale) else { return }
        dispatchTarget(["kind": "inventory", "id": item.int("id"), "slot": item.int("slot"), "component": item.int("component")])
    }
    func activateWidget(_ stale: JSONObject) {
        guard let widget = state.objects("ui").first(where: { $0.int("id") == stale.int("id") }) else { notice = "This interface has changed."; return }
        if widget.int("clientCode") == 205 { disconnect(); return }
        if widget.int("clientCode") == 326 {
            send(["kind": "appearance", "id": widget.int("id"), "gender": state.int("gender"), "body": state.ints("body"), "colors": state.ints("colors")]); return
        }
        if widget.int("button") == 2 { selectedSpell = widget; selectedItem = nil; inventoryMoveSource = nil; return }
        if widget.int("button") == 3 { send(["kind": "close"]); return }
        send(["kind": widget.int("button") == 6 ? "resume" : "button", "id": widget.int("id")])
    }

    func data(path: String) async throws -> Data {
        let expectedEpoch = sessionEpoch, bearer = token
        let result = try await rawData(path: path, method: "GET", body: nil, bearer: bearer, timeout: path.contains("/audio/") ? 65 : 10)
        guard expectedEpoch == sessionEpoch, bearer == token else { throw GameTransportError.superseded }
        return result
    }
    func json(path: String) async throws -> JSONObject { try decode(try await data(path: path)) }

    private func currentItem(_ item: JSONObject) -> JSONObject? {
        let found = state.objects("inventory").first { GameContract.itemIdentity($0) == GameContract.itemIdentity(item) }
        if found == nil { notice = "This item moved or is no longer available." }
        return found
    }
    private func dispatchTarget(_ original: JSONObject) {
        var action = original
        if let item = selectedItem {
            guard let item = currentItem(item) else { cancelSelection(); return }
            action["target"] = action["kind"]; action["kind"] = "use"
            action["useId"] = item.int("id"); action["useSlot"] = item.int("slot"); action["useComponent"] = item.int("component")
        } else if let spell = selectedSpell {
            action["target"] = action["kind"]; action["kind"] = "cast"; action["spell"] = spell.int("id")
        }
        send(action)
        cancelSelection()
    }
    private func clearSessionView() {
        state = [:]; latestTick = -1; lastServerRunning = nil; nearbyCache.removeAll(); nearbyCacheRevision = -1; actions.removeAll(); selectedTarget = nil; cancelSelection(); revision += 1
        inventoryMoveSource = nil; inventoryReorder = nil; rearrangingInventory = false
        media.reset()
    }
    private func isRetryable(_ error: Error) -> Bool {
        if let error = error as? GameTransportError { return error.retryable }
        if let error = error as? URLError { return error.code != .cancelled && error.code != .badURL && error.code != .unsupportedURL }
        return false
    }
    private func friendly(_ error: Error) -> String {
        if error is URLError { return "Cannot reach TableScape. Check the game connection." }
        return error.localizedDescription
    }
    private func pause(_ message: String) {
        connected = false; actions.removeAll(); cancelSelection(); selectedTarget = nil; inventoryMoveSource = nil; inventoryReorder = nil; rearrangingInventory = false; status = message
    }

    private func run(_ expectedGeneration: Int) async {
        var failures = 0
        var loginFailures = 0
        defer {
            if generation == expectedGeneration { runner = nil; connecting = false; connected = false }
        }
        while !Task.isCancelled && generation == expectedGeneration {
            do {
                if token == nil {
                    status = everConnected ? "Reconnecting…" : "Connecting…"
                    let expectedEpoch = sessionEpoch
                    let loginServer = connectionEndpoint ?? endpoint
                    let loginUsername = connectedUsername
                    let bytes = try await rawData(path: "/v1/session", method: "POST", body: ["username": connectedUsername, "startLumbridge": !everConnected], bearer: nil)
                    let login = try decode(bytes)
                    let newToken = login.string("token")
                    guard login.int("revision") == 274, !newToken.isEmpty else { throw GameTransportError.invalid("The server returned an invalid session. Reconnect to try again.") }
                    guard expectedGeneration == generation, expectedEpoch == sessionEpoch, !Task.isCancelled else {
                        // A completed login that outlived cancellation still owns a real server session.
                        Task { try? await self.rawData(path: "/v1/session", method: "DELETE", body: nil, bearer: newToken, server: loginServer) }
                        return
                    }
                    token = newToken; everConnected = true
                    do {
                        try NativeSessionCredential.save(.init(token: newToken, previouslyConnected: true), endpoint: loginServer, username: loginUsername)
                        sessionRecoverySaved = true
                    } catch { sessionRecoverySaved = false; notice = error.localizedDescription }
                    latestTick = -1
                }
                while !actions.isEmpty && connected && !Task.isCancelled {
                    let action = actions.removeFirst()
                    do {
                        let epoch = sessionEpoch
                        let reply = try decode(try await rawData(path: "/v1/action", method: "POST", body: action, bearer: token))
                        guard epoch == sessionEpoch, expectedGeneration == generation else { return }
                        guard reply.bool("queued") else { throw GameTransportError.invalid("The server did not confirm action dispatch.") }
                        actionCount += 1; lastAction = action
                        print("SCAPE_NATIVE_ACTION kind=\(action.string("kind")) tick=\(reply.int("tick"))")
                    } catch {
                        if Task.isCancelled || generation != expectedGeneration { return }
                        // Once sent, an action is never replayed: failure may have happened after execution.
                        if isRetryable(error) || !(error is GameTransportError) { uncertainAction = true; pause(friendly(error)); throw error }
                        if case GameTransportError.invalid = error { uncertainAction = true; pause(friendly(error)); throw error }
                        if case GameTransportError.http(401, _) = error { throw error }
                        notice = friendly(error)
                    }
                }
                let epoch = sessionEpoch
                let next = try decode(try await rawData(path: "/v1/state", method: "GET", body: nil, bearer: token))
                guard generation == expectedGeneration, epoch == sessionEpoch, !Task.isCancelled else { return }
                guard next.int("revision") == 274 else { throw GameTransportError.invalid("The server sent an unsupported game revision. Reconnect to try again.") }
                if !next.bool("pending") {
                    guard !next.object("player").isEmpty else { throw GameTransportError.invalid("The server sent invalid game data. Reconnect to try again.") }
                    let tick = next.int("tick")
                    if tick >= latestTick {
                        latestTick = tick
                        state = next; revision += 1; stateCount += 1
                        connected = true; connecting = false; everConnected = true
                        let serverRunning = next.bool("running")
                        if lastServerRunning != serverRunning { runEnabled = serverRunning; lastServerRunning = serverRunning }
                        if let target = selectedTarget {
                            selectedTarget = currentTarget(kind: target.string("kind"), actor: target.object("actor"))
                        }
                        if let selectedItem, !next.objects("inventory").contains(where: { GameContract.itemIdentity($0) == GameContract.itemIdentity(selectedItem) }) { self.selectedItem = nil }
                        reconcileInventoryReorder()
                        media.update(next)
                        status = "Connected · tick \(tick)" + (next.bool("busy") ? " · Performing action…" : "")
                        if uncertainAction { notice = "Reconnected. The last action was not confirmed; check its result before trying again."; uncertainAction = false }
                        if stateCount == 1 { print("SCAPE_NATIVE_CONNECTED name=\(next.object("player").string("name")) tick=\(tick)") }
                        if stateCount % 100 == 0 { print("SCAPE_NATIVE_STATE tick=\(tick) x=\(player.int("x")) z=\(player.int("z")) npcs=\(next.objects("npcs").count)") }
                    }
                }
                failures = 0
                if connected { loginFailures = 0 }
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                if Task.isCancelled || generation != expectedGeneration { return }
                if case GameTransportError.superseded = error { return }
                if case GameTransportError.http(401, _) = error {
                    do { try NativeSessionCredential.clearToken(endpoint: connectionEndpoint ?? endpoint, username: connectedUsername, matching: token) }
                    catch { notice = error.localizedDescription }
                    token = nil; sessionRecoverySaved = false; sessionEpoch += 1; clearSessionView(); pause("Session ended. Reconnecting…")
                    connecting = true
                    loginFailures += 1
                    if loginFailures >= 5 { status = "Unable to restore your session. Select Reconnect."; return }
                    try? await Task.sleep(nanoseconds: UInt64(min(16, 1 << loginFailures)) * 1_000_000_000)
                    continue
                }
                failures += 1
                pause(friendly(error))
                guard isRetryable(error), failures < 5 else { status = friendly(error) + " Select Reconnect."; return }
                let delay = min(16, 1 << failures)
                connecting = true
                status = friendly(error) + " Retrying in \(delay) seconds…"
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
        }
    }

    private func decode(_ data: Data) throws -> JSONObject {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? JSONObject else { throw GameTransportError.invalid("The server returned unreadable game data. Reconnect to try again.") }
        return object
    }
    @discardableResult
    private func rawData(path: String, method: String, body: JSONObject?, bearer: String?, server: String? = nil, timeout: TimeInterval = 10) async throws -> Data {
        let started = ProcessInfo.processInfo.systemUptime
        var responseBytes = 0, responseStatus = 0
        var succeeded = false
        activeRequests += 1
        defer {
            activeRequests -= 1; requestTotal += 1; receivedBytes += responseBytes
            if !succeeded { requestFailures += 1 }
            requestMetrics.append(RequestMetric(path: String(path.split(separator: "?").first ?? ""), milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000,
                                                bytes: responseBytes, status: responseStatus, succeeded: succeeded))
            if requestMetrics.count > 256 { requestMetrics.removeFirst(requestMetrics.count - 256) }
        }
        let scopedEndpoint = server ?? connectionEndpoint ?? endpoint
        guard let url = URL(string: scopedEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if let bridgeKey = bridgeCredential(for: scopedEndpoint) { request.setValue(bridgeKey, forHTTPHeaderField: "X-TableScape-Bridge-Key") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let bytes: Data
        let response: URLResponse
        if path == "/v1/session" && method == "POST" {
            // Let an in-flight login return its token even after cancellation, so it can
            // be released. Cancelling URLSession.data(for:) would hide a created token.
            (bytes, response) = try await withCheckedThrowingContinuation { continuation in
                transport.dataTask(with: request) { data, response, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, let response { continuation.resume(returning: (data, response)) }
                    else { continuation.resume(throwing: URLError(.badServerResponse)) }
                }.resume()
            }
        } else {
            (bytes, response) = try await transport.data(for: request)
        }
        guard let response = response as? HTTPURLResponse else { throw GameTransportError.invalid("The server returned an invalid response.") }
        responseStatus = response.statusCode; responseBytes = bytes.count
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: bytes) as? JSONObject)?.string("error") ?? ""
            throw GameTransportError.http(response.statusCode, message)
        }
        guard bytes.count <= (path.contains("/audio/") ? 64_000_000 : 16_000_000) else { throw GameTransportError.invalid("The server response was too large.") }
        succeeded = true
        return bytes
    }
}
