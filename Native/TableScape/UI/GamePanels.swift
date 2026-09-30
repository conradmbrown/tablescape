import SwiftUI
import UIKit

@MainActor
private enum GameImages {
    static let cache = NSCache<NSString, UIImage>()
    static func image(_ key: String) -> UIImage? {
        guard !key.isEmpty, !key.contains(".."), !key.contains("/") else { return nil }
        if let value = cache.object(forKey: key as NSString) { return value }
        guard let base = Bundle.main.resourceURL else { return nil }
        let direct = base.appendingPathComponent("Icons").appendingPathComponent(key + ".png")
        let nested = base.appendingPathComponent("Resources/Icons").appendingPathComponent(key + ".png")
        guard let value = UIImage(contentsOfFile: direct.path) ?? UIImage(contentsOfFile: nested.path) else { return nil }
        cache.countLimit = 256
        cache.setObject(value, forKey: key as NSString)
        return value
    }
}

struct OriginalGameIcon: View {
    let name: String
    var size: CGFloat = 30
    var body: some View {
        Group {
            if let image = GameImages.image(name) { Image(uiImage: image).resizable().interpolation(.none).scaledToFit() }
            else { Image(systemName: "square.dashed").resizable().scaledToFit().foregroundStyle(.secondary).padding(7) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct GameConnectionView: View {
    @ObservedObject var session: GameSession
    var showSetup = true
    var body: some View {
        Group {
            if session.connected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Connected as \(gamePlain(session.player.string("name")))", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.green)
                        Spacer()
                        Button("Disconnect", action: session.disconnect).controlSize(.small)
                    }
                    DisclosureGroup("Connection settings") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.endpoint).font(.caption).textSelection(.enabled)
                            Text(session.bridgeKeyConfigured ? "Private bridge key saved securely." : "Local game connection.").font(.caption).foregroundStyle(.secondary)
                            Text("Disconnect to change your server or character.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.caption)
                }.padding(.horizontal, 12).padding(.vertical, 8)
            } else if showSetup { setup }
        }
        .onAppear { session.inspectBridgeCredential() }
        .onChange(of: session.endpoint) { _, _ in session.inspectBridgeCredential() }
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to your game").font(.title3.bold())
            TextField("Game server", text: $session.endpoint).textFieldStyle(.roundedBorder).disabled(session.connected || session.connecting)
                .autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("game.endpoint")
            TextField("Character name", text: $session.username).textFieldStyle(.roundedBorder).disabled(session.connected || session.connecting)
                .autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("game.username")
            Text("Use unity followed by up to seven lowercase letters, numbers or underscores. Your character's progress is saved on the game server.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Private connection") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.bridgeKeyConfigured ? "A private connection key is saved securely for this server." : "Add the private bridge key when connecting through your protected game bridge.").font(.caption).foregroundStyle(.secondary)
                    SecureField("Private bridge key", text: $session.bridgeKeyInput).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                    HStack {
                        Button("Save key", action: session.saveBridgeCredential).disabled(session.bridgeKeyInput.isEmpty)
                        if session.bridgeKeyConfigured { Button("Remove saved key", action: session.removeBridgeCredential) }
                    }
                }
            }.disabled(session.connected || session.connecting)
            HStack {
                if session.connecting { ProgressView(); Button("Cancel", action: session.disconnect) }
                else if session.connected { Button("Disconnect", action: session.disconnect) }
                else { Button("Connect", action: session.connect).buttonStyle(.borderedProminent).accessibilityIdentifier("game.connect") }
                Spacer()
                Text(session.status).font(.caption)
            }
            if !session.notice.isEmpty { Text(session.notice).font(.callout).foregroundStyle(.orange) }
        }.padding(20).frame(minWidth: 320, idealWidth: 520)
    }
}

struct GamePanels: View {
    @ObservedObject var session: GameSession
    var assets: NativeAssetStore? = nil
    var immersive = false
    var volumeOpen = false
    var collapsible = false
    var tableControlsContent: AnyView? = nil
    var onOpenTableWindow: (() -> Void)? = nil
    var onLeaveTable: (() -> Void)? = nil
    @State private var showMoreTabs = false
    @State private var showTableControls = false
    @State private var panelExpanded = false
    @Environment(\.openWindow) private var openWindow
    private var panelVisible: Bool { !collapsible || panelExpanded || session.state.isEmpty }
    var body: some View {
        Group {
            if collapsible {
                panelLayout.fixedSize(horizontal: false, vertical: true)
            } else {
                panelLayout.frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity, minHeight: 500, idealHeight: 560, maxHeight: .infinity)
            }
        }
    }
    private var panelLayout: some View {
        VStack(spacing: 0) {
            if panelVisible {
                panelContent.frame(height: collapsible ? 450 : nil)
                Divider()
            }
            toolbelt
        }
    }
    @ViewBuilder private var panelContent: some View {
        VStack(spacing: 0) {
            if session.state.isEmpty {
                GameConnectionView(session: session)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !session.connected { recovery }
                        if !session.selectionLabel.isEmpty {
                            HStack { Text(session.selectionLabel).font(.headline); Spacer(); Button("Cancel", action: session.cancelSelection) }
                                .padding(12).background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        }
                        activePanel
                    }.padding(12)
                }.id(session.activeTab).accessibilityIdentifier("game.panel.scroll")
                if !session.notice.isEmpty && !session.notice.hasPrefix("Queued: ") {
                    Text(session.notice).font(.caption).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
                }
            }
        }
    }
    @ViewBuilder private var popupShortcuts: some View {
        // System window-close hides a surface; these routes keep the live workflow reachable.
        if session.state.int("chatRoot", -1) >= 0 {
            Button("Conversation", systemImage: "bubble.left.and.bubble.right") { showMoreTabs = false; openWindow(id: GamePopup.dialogue.rawValue, value: GamePopup.dialogue.rawValue) }
                .accessibilityIdentifier("game.popup.reopen.dialogue")
        }
        if session.state.int("mainRoot", -1) >= 0 || session.state.bool("allowDesign") {
            Button(session.state.bool("allowDesign") ? "Character appearance" : "Open game interface", systemImage: "rectangle.on.rectangle") { showMoreTabs = false; openWindow(id: GamePopup.activity.rawValue, value: GamePopup.activity.rawValue) }
                .accessibilityIdentifier("game.popup.reopen.activity")
        }
        if session.state.bool("countDialog") {
            Button("Enter amount", systemImage: "number") { showMoreTabs = false; openWindow(id: GamePopup.amount.rawValue, value: GamePopup.amount.rawValue) }
                .accessibilityIdentifier("game.popup.reopen.amount")
        }
    }
    private var toolbelt: some View {
        HStack(spacing: 4) {
            ForEach(session.availableTabs.filter { $0 < 7 }, id: \.self) { tab in
                tabButton(tab)
            }
            Button { showTableControls = false; showMoreTabs.toggle() } label: {
                Image(systemName: "ellipsis").font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(showMoreTabs || (panelVisible && session.activeTab > 7) ? Color.orange.opacity(0.30) : Color.brown.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).help("More tools").accessibilityLabel("More tools")
                .accessibilityIdentifier("game.moreTabs")
            Button { showMoreTabs = false; showTableControls.toggle() } label: {
                Image(systemName: "table.furniture").font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(showTableControls ? Color.orange.opacity(0.30) : Color.brown.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).accessibilityLabel("Table controls")
                .accessibilityIdentifier("table.controls")
                .popover(isPresented: $showTableControls, arrowEdge: .bottom) { tableControls }
        }.padding(8)
            .popover(isPresented: $showMoreTabs, arrowEdge: .bottom) { moreTools }
            .accessibilityElement(children: .contain).accessibilityIdentifier("game.toolbelt")
            .accessibilityValue(panelVisible ? "Expanded" : "Collapsed")
    }
    private var moreTools: some View {
        VStack(spacing: 14) {
            HStack {
                Text("More tools").font(.headline)
                Spacer()
                Button { showMoreTabs = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close tools").accessibilityIdentifier("game.tools.close")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(session.availableTabs.filter { $0 > 7 }, id: \.self) { tab in tabButton(tab) }
            }
            Divider()
            HStack {
                Button("Nearby & messages", systemImage: "text.bubble") {
                    showMoreTabs = false
                    openWindow(id: GamePopup.explore.rawValue, value: GamePopup.explore.rawValue)
                }.accessibilityIdentifier("game.explore.open")
            }
            HStack {
                Button("Map", systemImage: "map") {
                    showMoreTabs = false
                    openWindow(id: GamePopup.map.rawValue, value: GamePopup.map.rawValue)
                }.accessibilityIdentifier("game.map.open")
                Toggle(isOn: $session.runEnabled) { Label("Run", systemImage: "figure.run") }
                    .toggleStyle(.button).help("Run · \(session.state.int("energy") / 100)% energy")
                    .accessibilityIdentifier("game.run")
            }
            if session.connected { popupShortcuts }
        }.padding(18).frame(width: 340)
            .accessibilityElement(children: .contain).accessibilityIdentifier("game.tools")
    }
    private var tableControls: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Table").font(.headline)
                Spacer()
                Button { showTableControls = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close table controls").accessibilityIdentifier("table.controls.close")
            }
            if let tableControlsContent { tableControlsContent }
            if !volumeOpen, let onOpenTableWindow {
                Button("Table window", systemImage: "cube.transparent") {
                    showTableControls = false
                    onOpenTableWindow()
                }.accessibilityIdentifier("table.window.open")
            }
            if !volumeOpen {
                Button("Table placement", systemImage: "table.furniture") {
                    showTableControls = false
                    openWindow(id: "placement", value: "placement")
                }.accessibilityIdentifier("table.setup")
            }
            if immersive || volumeOpen, let onLeaveTable {
                Button("Leave table", systemImage: "rectangle.portrait.and.arrow.right") {
                    showTableControls = false
                    onLeaveTable()
                }.accessibilityIdentifier("table.leave")
            } else {
                Button("Game window", systemImage: "macwindow") {
                    showTableControls = false
                    openWindow(id: "main", value: "main")
                }
            }
        }.padding(18).frame(width: 340)
            .accessibilityElement(children: .contain).accessibilityIdentifier("table.controls.menu")
    }
    private func tabButton(_ tab: Int) -> some View {
        let selected = panelVisible && tab == session.activeTab
        return Button {
            if collapsible && panelExpanded && tab == session.activeTab {
                panelExpanded = false
            } else {
                session.selectTab(tab)
                if collapsible { panelExpanded = true }
            }
            showMoreTabs = false; showTableControls = false
        } label: {
            OriginalGameIcon(name: "sideicons-\(GameContract.tabIcons[tab])", size: 24)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.orange.opacity(0.30) : Color.brown.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).help(GameContract.tabNames[tab]).accessibilityLabel(GameContract.tabNames[tab])
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("game.tab.\(tab)")
    }
    private var recovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.status).foregroundStyle(.orange)
            if session.connecting { Button("Cancel reconnect", action: session.disconnect) }
            else { Button("Reconnect", action: session.connect).buttonStyle(.borderedProminent) }
        }
    }
    @ViewBuilder private var activePanel: some View {
        if session.state.int("sideRoot", -1) >= 0 {
            WidgetList(session: session, root: session.state.int("sideRoot"))
            InventoryGroups(session: session, roots: [session.state.int("sideRoot")])
        } else {
            let roots = session.state.ints("tabs")
            let root = session.activeTab < roots.count ? roots[session.activeTab] : -1
            if session.activeTab == 1 { ClassicSkillsView(session: session) }
            else if session.activeTab == 6 { ClassicMagicView(session: session, root: root) }
            else if session.activeTab == 11 { GameSettingsView(session: session) }
            else if session.activeTab == 10 {
                Text("Your progress is saved when you leave.").foregroundStyle(.secondary)
                Button("Log out", action: session.disconnect).buttonStyle(.borderedProminent)
            } else {
                if session.activeTab < GameContract.tabNames.count { Text(GameContract.tabNames[session.activeTab]).font(.headline) }
                WidgetList(session: session, root: root, suppressTitle: session.activeTab < GameContract.tabNames.count ? GameContract.tabNames[session.activeTab] : nil)
                InventoryGroups(session: session, roots: [root], showTitles: ![3, 4].contains(session.activeTab))
                if session.activeTab == 8 || session.activeTab == 9 {
                    Text("Social controls shown here follow the current server interface.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct WidgetList: View {
    @ObservedObject var session: GameSession
    let root: Int
    var dialogue = false
    var suppressTitle: String? = nil
    var body: some View {
        LazyVStack(alignment: dialogue ? .center : .leading, spacing: 10) {
            ForEach(Array(widgets.enumerated()), id: \.offset) { _, widget in
                if widget.int("button") > 0 {
                    Button { session.activateWidget(widget) } label: {
                        HStack {
                            if widget.bool("active"), widget.int("button") == 4 || widget.int("button") == 5 { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            Text(label(widget)).frame(maxWidth: .infinity, alignment: dialogue ? .center : .leading)
                        }
                    }.buttonStyle(.bordered).tint(widget.int("button") == 6 ? .orange : .gray)
                        .accessibilityIdentifier("game.widget.\(widget.int("id"))")
                } else if !gamePlain(widget.string("text")).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(gamePlain(widget.string("text"))).frame(maxWidth: .infinity, alignment: dialogue ? .center : .leading)
                }
            }
        }
    }
    private var widgets: [JSONObject] {
        session.state.objects("ui").filter {
            guard $0.int("root", -1) == root, !((300...325).contains($0.int("clientCode"))) else { return false }
            if let suppressTitle, $0.int("button") == 0, gamePlain($0.string("text")).trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(suppressTitle) == .orderedSame { return false }
            return true
        }
    }
    private func label(_ widget: JSONObject) -> String {
        let text = dialogue ? widget.string("text") : widget.string("option")
        let alternatives = [text, widget.string("action"), widget.string("text"), widget.string("option")]
        return alternatives.map(gamePlain).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "Select" }) ?? (widget.int("button") == 6 ? "Continue" : widget.int("button") == 3 ? "Close" : "Select")
    }
}

struct InventoryGroups: View {
    @ObservedObject var session: GameSession
    let roots: [Int]
    var showTitles = true
    private var items: [JSONObject] { session.state.objects("inventory").filter { roots.contains($0.int("root", -1)) } }
    private var showsCarriedInventory: Bool {
        let tabs = session.state.ints("tabs")
        return tabs.count > 3 && tabs[3] >= 0 && roots.contains(tabs[3])
    }
    private var components: [Int] {
        var result = Set(items.map { $0.int("component") })
        // Keep the original 28-slot layout even when the carried inventory is empty
        // or a server interface temporarily disables rearranging it.
        if showsCarriedInventory { result.insert(3214) }
        return result.sorted()
    }
    var body: some View {
        ForEach(components, id: \.self) { component in
            let group = items.filter { $0.int("component") == component }.sorted { $0.int("slot") < $1.int("slot") }
            VStack(alignment: .leading, spacing: 10) {
                if showTitles { Text(title(group)).font(.subheadline.bold()) }
                if component == 3214 && showsCarriedInventory {
                    if let moving = session.inventoryMoveSource {
                        HStack {
                            Text("Move \(moving.string("name")): choose an empty slot or swap with an item.").font(.caption)
                            Button("Cancel", action: session.cancelInventoryMove).controlSize(.small)
                        }
                    }
                    if session.rearrangingInventory { Text("Arranging inventory…").font(.caption).foregroundStyle(.secondary) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(0..<28, id: \.self) { slot in
                            InventorySlotView(session: session, slot: slot, item: group.first { $0.int("slot") == slot })
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48, maximum: 72), spacing: 4)], spacing: 4) {
                        ForEach(Array(group.enumerated()), id: \.offset) { _, item in InventoryItemView(session: session, item: item) }
                    }
                }
            }
        }
    }
    private func title(_ group: [JSONObject]) -> String {
        guard let item = group.first else { return "Inventory" }
        if !item.string("title").isEmpty { return item.string("title") }
        let buttons = item.strings("buttons").joined(separator: " ")
        if buttons.contains("Withdraw") { return "Bank" }
        if buttons.contains("Buy") { return "Shop stock" }
        if buttons.contains("Sell") { return "Your items" }
        if buttons.contains("Remove") { return "Equipment" }
        return "Inventory"
    }
}

struct InventorySlotView: View {
    @ObservedObject var session: GameSession
    let slot: Int
    let item: JSONObject?
    var body: some View {
        Group {
            if let item {
                InventoryItemView(session: session, item: item)
                    .draggable(session.inventoryDragPayload(item))
            } else {
                Button { session.completeInventoryMove(to: slot, expectedDestination: nil) } label: {
                    Image(systemName: "square.dashed").font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).background(.brown.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Empty inventory slot \(slot + 1)")
                    .accessibilityIdentifier("game.inventory.empty.\(slot)")
            }
        }.dropDestination(for: String.self) { values, _ in
            guard values.count == 1, let payload = values.first else { return false }
            return session.dropInventory(payload, to: slot, expectedDestination: item)
        }.overlay {
            if let item, let moving = session.inventoryMoveSource, GameContract.itemIdentity(item) == GameContract.itemIdentity(moving) {
                RoundedRectangle(cornerRadius: 12).stroke(.orange, lineWidth: 2).allowsHitTesting(false)
            }
        }
    }
}

struct InventoryItemView: View {
    @ObservedObject var session: GameSession
    let item: JSONObject
    var body: some View {
        Menu {
            if session.canReorderInventory(item) {
                if let moving = session.inventoryMoveSource {
                    if GameContract.itemIdentity(moving) != GameContract.itemIdentity(item) {
                        Button("Swap with this item") { session.completeInventoryMove(to: item.int("slot"), expectedDestination: item) }
                            .accessibilityIdentifier("game.item.swap.\(item.int("slot"))")
                    } else { Button("Cancel move", action: session.cancelInventoryMove) }
                }
                Button("Move") { session.beginInventoryMove(item) }.disabled(session.rearrangingInventory)
                    .accessibilityIdentifier("game.item.move.\(item.int("slot"))")
            }
            if session.selectedItem != nil || session.selectedSpell != nil {
                Button(session.selectionLabel + " " + item.string("name")) { session.itemTarget(item) }
            }
            ForEach(Array(item.strings("ops").enumerated()), id: \.offset) { index, option in
                if !option.isEmpty { Button(gamePlain(option)) { session.itemAction(item, kind: "inventory", op: index + 1) } }
            }
            if item.bool("usable") { Button("Use") { session.selectItem(item) } }
            ForEach(Array(item.strings("buttons").enumerated()), id: \.offset) { index, option in
                if !option.isEmpty { Button(gamePlain(option)) { session.itemAction(item, kind: "invbutton", op: index + 1) } }
            }
            Button("Examine") { session.showNotice(item.string("name") + " ×" + item.int("count", 1).formatted()) }
        } label: {
            ZStack(alignment: .topLeading) {
                OriginalGameIcon(name: item.string("graphic"), size: 36)
                    .frame(maxWidth: .infinity, minHeight: 44)
                if item.int("count") > 1 {
                    Text(quantity(item.int("count"))).font(.caption2.monospacedDigit().bold()).foregroundStyle(.yellow)
                        .padding(.horizontal, 4).padding(.top, 2)
                }
            }.background(selected ? Color.orange.opacity(0.25) : Color.brown.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        } primaryAction: {
            if session.inventoryMoveSource != nil && session.canReorderInventory(item) { session.completeInventoryMove(to: item.int("slot"), expectedDestination: item) }
            else { session.activateItem(item) }
        }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).help(gamePlain(item.string("name"))).accessibilityLabel(item.string("name") + ", " + item.int("count", 1).formatted())
            .accessibilityIdentifier("game.item.\(item.int("component")).\(item.int("slot"))")
    }
    private var selected: Bool { session.selectedItem.map { GameContract.itemIdentity($0) == GameContract.itemIdentity(item) } ?? false }
    private func quantity(_ number: Int) -> String { number >= 10_000_000 ? "\(number / 1_000_000)M" : number >= 100_000 ? "\(number / 1000)K" : String(number) }
}

struct TargetActionsView: View {
    @ObservedObject var session: GameSession
    let target: JSONObject
    @State private var examining = false
    var body: some View {
        let actor = target.object("actor"), kind = target.string("kind")
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(gamePlain(actor.string("name"))).font(.headline)
                if actor.int("combatLevel", -1) >= 0 { Text("Level \(actor.int("combatLevel"))").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { session.selectedTarget = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close target").accessibilityIdentifier("game.options.close")
            }
            if actor.int("maxHp") > 0 {
                ProgressView(value: Double(max(0, actor.int("hp"))), total: Double(max(1, actor.int("maxHp")))).tint(.green)
            }
            if session.selectedItem != nil || session.selectedSpell != nil {
                Button(session.selectionLabel + " " + gamePlain(actor.string("name"))) { session.target(kind: kind, actor: actor); session.selectedTarget = nil }.buttonStyle(.borderedProminent)
            } else {
                ForEach(Array(actor.strings("ops").enumerated()), id: \.offset) { index, option in
                    if !option.isEmpty { Button(gamePlain(option)) { session.target(kind: kind, actor: actor, op: index + 1); session.selectedTarget = nil }.buttonStyle(.bordered).accessibilityIdentifier("game.target.op.\(index + 1)") }
                }
            }
            Button("Examine") { examining = true }.font(.callout)
                .popover(isPresented: $examining) { Text(gamePlain(actor.string("description", actor.string("name")))).padding(20).frame(width: 280) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!session.connected)
            .onChange(of: target.string("key")) { _, _ in examining = false }
    }
}

struct AmountEntryView: View {
    @ObservedObject var session: GameSession
    @State private var amount = "1"
    var body: some View {
        let epoch = session.sessionEpoch, root = session.state.int("mainRoot", -1)
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter amount").font(.headline)
            HStack {
                TextField("Amount", text: $amount).textFieldStyle(.roundedBorder).keyboardType(.numberPad).accessibilityIdentifier("game.amount")
                Button("Confirm") {
                    if session.connected, session.sessionEpoch == epoch, session.state.bool("countDialog"), session.state.int("mainRoot", -1) == root,
                       let value = Int(amount), (0...Int(Int32.max)).contains(value) { session.send(["kind": "count", "id": value]) }
                }
                    .buttonStyle(.borderedProminent).disabled(Int(amount).map { !(0...Int(Int32.max)).contains($0) } ?? true)
            }
            Button("Cancel") {
                if session.connected, session.sessionEpoch == epoch, session.state.bool("countDialog"), session.state.int("mainRoot", -1) == root { session.send(["kind": "close"]) }
            }
        }.padding(20).disabled(!session.connected)
    }
}

struct DialogueView: View {
    @ObservedObject var session: GameSession
    var assets: NativeAssetStore? = nil
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        let epoch = session.sessionEpoch, root = session.state.int("chatRoot", -1)
        VStack(spacing: 12) {
            HStack {
                Image(systemName: session.state.object("dialogueHead").string("kind") == "player" ? "person.crop.circle" : "bubble.left.and.bubble.right")
                Text("Conversation").font(.headline)
                Spacer()
                Button("End") {
                    if session.connected, session.sessionEpoch == epoch, root >= 0, session.state.int("chatRoot", -1) == root { session.send(["kind": "close"]) }
                }.font(.callout).accessibilityLabel("End conversation").accessibilityIdentifier("game.dialogue.close")
                Button { dismissWindow(id: GamePopup.dialogue.rawValue) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Hide conversation").accessibilityIdentifier("game.dialogue.hide")
            }
            HStack(alignment: .center, spacing: 10) {
                let head = session.state.object("dialogueHead")
                if let assets, !head.isEmpty, head.string("kind") != "player" {
                    OriginalPortraitView(session: session, head: head, assets: assets)
                }
                WidgetList(session: session, root: session.state.int("chatRoot"), dialogue: true)
                if let assets, !head.isEmpty, head.string("kind") == "player" {
                    OriginalPortraitView(session: session, head: head, assets: assets)
                }
            }
        }.padding(22).disabled(!session.connected)
            .accessibilityElement(children: .contain).accessibilityIdentifier("game.dialogue")
    }
}

struct OriginalPortraitView: View {
    @ObservedObject var session: GameSession
    let head: JSONObject
    let assets: NativeAssetStore
    @State private var image: UIImage?
    private var identity: String {
        let bytes = (try? JSONSerialization.data(withJSONObject: head, options: [.sortedKeys])) ?? Data()
        return "\(session.sessionEpoch):" + bytes.base64EncodedString()
    }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().interpolation(.none).scaledToFit() }
            else { Color.clear }
        }.frame(width: 96, height: 118).accessibilityLabel("Original \(head.string("kind")) portrait")
            .task(id: identity) {
                image = nil
                let started = Date()
                while !Task.isCancelled {
                    do {
                        let frame = try await NativePortraitRenderer.image(head: head, store: assets, time: Date().timeIntervalSince(started), size: CGSize(width: 192, height: 236))
                        guard !Task.isCancelled else { return }
                        image = frame
                    } catch { if Task.isCancelled { return } }
                    do { try await Task.sleep(nanoseconds: 166_666_667) } catch { return }
                }
            }
    }
}

struct MainInterfaceView: View {
    @ObservedObject var session: GameSession
    var body: some View {
        let epoch = session.sessionEpoch, root = session.state.int("mainRoot", -1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(interfaceTitle).font(.title3.bold())
                Spacer()
                Button("Close") {
                    if session.connected, session.sessionEpoch == epoch, root >= 0, session.state.int("mainRoot", -1) == root { session.send(["kind": "close"]) }
                }.accessibilityIdentifier("game.closeInterface")
            }
            if !session.state.object("overlay").isEmpty { OriginalOverlayView(session: session, overlay: session.state.object("overlay")) }
            else { WidgetList(session: session, root: session.state.int("mainRoot")) }
            InventoryGroups(session: session, roots: [session.state.int("mainRoot")])
        }.padding(22).disabled(!session.connected)
    }
    private var interfaceTitle: String {
        let inventory = session.state.objects("inventory").filter { $0.int("root") == session.state.int("mainRoot") }
        if inventory.contains(where: { $0.string("title").contains("offer") }) { return "Trade" }
        if inventory.contains(where: { $0.strings("buttons").contains(where: { $0.contains("Withdraw") }) }) { return "Bank" }
        if inventory.contains(where: { $0.strings("buttons").contains(where: { $0.contains("Buy") }) }) { return "Shop" }
        return session.state.object("overlay").isEmpty ? "Game interface" : "Quest complete"
    }
}

struct OriginalOverlayView: View {
    @ObservedObject var session: GameSession
    let overlay: JSONObject
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(overlay.objects("nodes").enumerated()), id: \.offset) { _, node in
                if !node.string("image").isEmpty { AuthenticatedGameImage(session: session, path: "/v1/overlay/" + node.string("image")).frame(maxHeight: 160) }
                if !node.string("text").isEmpty {
                    if node.int("button") > 0 {
                        Button(gamePlain(node.string("text"))) { if let widget = session.state.objects("ui").first(where: { $0.int("id") == node.int("id") }) { session.activateWidget(widget) } }
                    } else { Text(gamePlain(node.string("text"))).multilineTextAlignment(.center) }
                }
            }
        }.frame(maxWidth: .infinity)
    }
}

struct AuthenticatedGameImage: View {
    @ObservedObject var session: GameSession
    let path: String
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().interpolation(.none).scaledToFit() } }
            .task(id: "\(session.sessionEpoch):\(path)") {
                image = nil
                if let data = try? await session.data(path: path), !Task.isCancelled { image = UIImage(data: data) }
            }
    }
}

struct AppearanceView: View {
    @ObservedObject var session: GameSession
    @State private var gender = 0
    @State private var bodyParts: [Int] = []
    @State private var colors: [Int] = []
    private let parts = ["Hair", "Jaw", "Torso", "Arms", "Hands", "Legs", "Feet"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Character appearance").font(.headline)
            Picker("Body", selection: $gender) { Text("Male").tag(0); Text("Female").tag(1) }.pickerStyle(.segmented)
                .onChange(of: gender) { _, value in
                    bodyParts = (0..<7).map { part in session.state.objects("design").first(where: { $0.int("type") == part + value * 7 })?.int("id") ?? -1 }
                }
            ForEach(0..<min(7, bodyParts.count), id: \.self) { part in
                Button("\(parts[part]): style \(bodyParts[part])") {
                    let options = session.state.objects("design").filter { $0.int("type") == part + gender * 7 }.map { $0.int("id") }
                    if !options.isEmpty { bodyParts[part] = options[((options.firstIndex(of: bodyParts[part]) ?? -1) + 1) % options.count] }
                }
            }
            ForEach(0..<min(5, colors.count), id: \.self) { color in
                Button("Colour \(color + 1): \(colors[color])") {
                    let limits = session.state.ints("colorCounts")
                    if color < limits.count, limits[color] > 0 { colors[color] = (colors[color] + 1) % limits[color] }
                }
            }
            Button("Confirm appearance") {
                if let button = session.state.objects("ui").first(where: { $0.int("clientCode") == 326 }) {
                    session.send(["kind": "appearance", "id": button.int("id"), "gender": gender, "body": bodyParts, "colors": colors])
                }
            }.buttonStyle(.borderedProminent)
        }.onAppear { gender = session.state.int("gender"); bodyParts = session.state.ints("body"); colors = session.state.ints("colors") }
    }
}
