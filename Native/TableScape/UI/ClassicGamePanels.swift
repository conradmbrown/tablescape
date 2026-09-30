import SwiftUI

// Revision 274 interface 3917. Sprite indices follow the three original columns,
// not the skill IDs used by levels/baseLevels/experience. IDs 18/19 are unused.
private struct ClassicSkill: Identifiable {
    let id: Int
    let graphic: String
    let guideID: Int
    var name: String { GameContract.skillNames[id] }
    static let layout: [ClassicSkill] = {
        let skills = [0, 3, 14, 2, 16, 13, 1, 15, 10, 4, 17, 7, 5, 12, 11, 6, 9, 8, 20]
        let sprites = [0, 6, 12, 1, 7, 13, 2, 8, 14, 3, 9, 15, 4, 10, 16, 5, 11, 17]
        return skills.enumerated().map { position, skill in
            ClassicSkill(id: skill, graphic: position < sprites.count ? "staticons-\(sprites[position])" : "staticons2-0", guideID: 8654 + position)
        }
    }()
}

struct ClassicSkillsView: View {
    @ObservedObject var session: GameSession
    @State private var selectedSkill: ClassicSkill?

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 5) {
                ForEach(ClassicSkill.layout) { skill in skillButton(skill) }
                Color.clear.frame(height: 46).accessibilityHidden(true)
                Color.clear.frame(height: 46).accessibilityHidden(true)
            }
            Text("Total level: \(totalLevel)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("game.skills")
        .popover(item: $selectedSkill) { skill in skillDetails(skill) }
    }

    private var totalLevel: String {
        let base = session.state.ints("baseLevels")
        guard ClassicSkill.layout.allSatisfy({ $0.id < base.count }) else { return "—" }
        return String(ClassicSkill.layout.reduce(0) { $0 + base[$1.id] })
    }
    private func level(_ index: Int, key: String) -> Int? {
        let values = session.state.ints(key)
        return values.indices.contains(index) ? values[index] : nil
    }
    private func levelText(_ index: Int, key: String) -> String {
        level(index, key: key).map(String.init) ?? "—"
    }
    private func levelColour(_ index: Int) -> Color {
        guard let current = level(index, key: "levels"), let base = level(index, key: "baseLevels") else { return .primary }
        return current < base ? .red : current > base ? .green : .primary
    }
    private func skillButton(_ skill: ClassicSkill) -> some View {
        Button { selectedSkill = skill } label: {
            HStack(spacing: 5) {
                OriginalGameIcon(name: skill.graphic, size: 30)
                HStack(alignment: .center, spacing: 1) {
                    Text(levelText(skill.id, key: "levels")).foregroundStyle(levelColour(skill.id)).offset(y: -5)
                    Text("/").foregroundStyle(.secondary)
                    Text(levelText(skill.id, key: "baseLevels")).offset(y: 5)
                }.font(.system(size: 17, weight: .medium, design: .monospaced)).minimumScaleFactor(0.65).lineLimit(1)
            }.padding(.horizontal, 5).frame(maxWidth: .infinity, minHeight: 46)
                .background(.brown.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help(skill.name)
            .accessibilityLabel(skill.name)
            .accessibilityValue("\(levelText(skill.id, key: "levels")) of \(levelText(skill.id, key: "baseLevels"))")
            .accessibilityHint("Show level and experience")
            .accessibilityIdentifier("game.skill.\(skill.id)")
    }
    private func skillDetails(_ skill: ClassicSkill) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                OriginalGameIcon(name: skill.graphic, size: 34)
                Text(skill.name).font(.headline)
                Spacer()
                Button { selectedSkill = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close skill details").accessibilityIdentifier("game.skill.detail.close")
            }
            Text("Level \(levelText(skill.id, key: "levels")) / \(levelText(skill.id, key: "baseLevels"))")
                .font(.title3.monospacedDigit()).accessibilityIdentifier("game.skill.level.\(skill.id)")
            Text(level(skill.id, key: "experience").map { "\(($0 / 10).formatted()) XP" } ?? "Experience unavailable")
                .font(.body.monospacedDigit()).accessibilityIdentifier("game.skill.xp.\(skill.id)")
            if let guide = session.state.objects("ui").first(where: { $0.int("id") == skill.guideID && $0.int("button") > 0 }) {
                Button("Skill guide") { session.activateWidget(guide); selectedSkill = nil }
                    .disabled(!session.connected).accessibilityIdentifier("game.widget.\(skill.guideID)")
            }
        }.padding(20).frame(width: 280)
            .accessibilityElement(children: .contain).accessibilityIdentifier("game.skill.detail.\(skill.id)")
    }
}

private struct ClassicSpell: Identifiable {
    let node: JSONObject
    let widget: JSONObject
    let detail: JSONObject
    let x: Int
    let y: Int
    var id: Int { node.int("id") }
    var name: String {
        let action = widget.string("action")
        return gamePlain(action.isEmpty ? widget.string("option", node.string("option")) : action)
    }
    var available: Bool { node.bool("active") }
}

private struct ClassicInterfaceNode {
    let value: JSONObject
    let x: Int
    let y: Int
    let hidden: Bool
    static func flatten(_ node: JSONObject, x: Int = 0, y: Int = 0, hidden: Bool = false) -> [ClassicInterfaceNode] {
        guard !node.isEmpty else { return [] }
        let px = x + node.int("x"), py = y + node.int("y"), isHidden = hidden || node.bool("hidden")
        return [ClassicInterfaceNode(value: node, x: px, y: py, hidden: isHidden)] + node.objects("children").flatMap {
            flatten($0, x: px, y: py, hidden: isHidden)
        }
    }
}

struct ClassicMagicView: View {
    @ObservedObject var session: GameSession
    let root: Int
    @State private var detailSpellID: Int?

    var body: some View {
        let spells = self.spells
        Group {
            if spells.isEmpty {
                ProgressView("Opening spellbook…").frame(maxWidth: .infinity, minHeight: 120)
            } else {
                // The original sidebar's coordinates retain later-added spells in their
                // proper positions (Bind, Iban Blast, Snare, and Trollheim, among others).
                let columns = Array(Set(spells.map(\.x))).sorted()
                let rows = Array(Set(spells.map(\.y))).sorted()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: max(1, columns.count)), spacing: 4) {
                    ForEach(0..<(rows.count * columns.count), id: \.self) { slot in
                        if let spell = spells.first(where: { $0.x == columns[slot % columns.count] && $0.y == rows[slot / columns.count] }) {
                            spellButton(spell)
                        } else {
                            Color.clear.frame(height: 44).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("game.magic")
        .popover(isPresented: Binding(get: { detailSpellID != nil }, set: { if !$0 { detailSpellID = nil } })) {
            if let spell = spells.first(where: { $0.id == detailSpellID }) {
                spellDetails(spell)
            }
        }
        .onChange(of: root) { _, _ in detailSpellID = nil }
    }

    private var spells: [ClassicSpell] {
        let sidebar = session.state.object("sidebar")
        guard sidebar.int("root", -1) == root else { return [] }
        let all = ClassicInterfaceNode.flatten(sidebar.object("node"))
        let widgets = session.state.objects("ui").filter { $0.int("root", -1) == root && $0.int("button") > 0 }
        return all.compactMap { item in
            let node = item.value, graphic = node.string("graphic")
            guard !item.hidden, node.int("button") > 0,
                  graphic.hasPrefix("magicon-") || graphic.hasPrefix("magicoff-") || graphic.hasPrefix("magicon2-") || graphic.hasPrefix("magicoff2-"),
                  let widget = widgets.first(where: { $0.int("id") == node.int("id") }) else { return nil }
            let detail = all.first(where: { $0.value.int("id") == node.int("over", -1) })?.value ?? [:]
            return ClassicSpell(node: node, widget: widget, detail: detail, x: item.x, y: item.y)
        }.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
    }
    private func spellButton(_ spell: ClassicSpell) -> some View {
        let selected = session.selectedSpell?.int("id") == spell.id
        return Button { session.activateWidget(spell.widget) } label: {
            OriginalGameIcon(name: spell.node.string("graphic"), size: 30)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.orange.opacity(0.35) : Color.brown.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.orange : .clear, lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).disabled(!session.connected)
            .help(spell.name).accessibilityLabel(spell.name)
            .accessibilityValue(spell.available ? "Available" : "Requirements not met")
            .accessibilityHint("Press and hold for spell details")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("game.widget.\(spell.id)")
            .contextMenu { Button("Spell details") { detailSpellID = spell.id } }
            .accessibilityAction(named: "Spell details") { detailSpellID = spell.id }
    }
    private func spellDetails(_ spell: ClassicSpell) -> some View {
        let nodes = ClassicInterfaceNode.flatten(spell.detail).sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        let texts = nodes.filter { !$0.value.string("text").isEmpty }
        let graphics = nodes.filter { !$0.value.string("graphic").isEmpty }
        let counts = texts.filter { $0.value.string("text").contains("/") }
        let descriptions = texts.filter { !$0.value.string("text").contains("/") }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                OriginalGameIcon(name: spell.node.string("graphic"), size: 32)
                Text(descriptions.first.map { gamePlain($0.value.string("text")) } ?? spell.name).font(.headline)
                Spacer()
                Button { detailSpellID = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close spell details").accessibilityIdentifier("game.spell.detail.close")
            }
            ForEach(Array(descriptions.dropFirst().enumerated()), id: \.offset) { _, item in
                Text(gamePlain(item.value.string("text"))).font(.callout)
            }
            if !graphics.isEmpty {
                HStack(spacing: 24) {
                    ForEach(Array(graphics.enumerated()), id: \.offset) { _, item in
                        let center = item.x + item.value.int("width") / 2
                        let count = counts.min { abs($0.x + $0.value.int("width") / 2 - center) < abs($1.x + $1.value.int("width") / 2 - center) }
                        VStack(spacing: 4) {
                            OriginalGameIcon(name: item.value.string("graphic"), size: 32)
                            if let count {
                                Text(gamePlain(count.value.string("text"))).font(.caption.monospacedDigit())
                                    .foregroundStyle(count.value.bool("active") ? .green : .red)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
        }.padding(20).frame(width: 300)
            .accessibilityElement(children: .contain).accessibilityIdentifier("game.spell.detail.\(spell.id)")
    }
}
