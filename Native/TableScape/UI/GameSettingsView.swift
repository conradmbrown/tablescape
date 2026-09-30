import SwiftUI

/// Native controls use the original server options as their source of truth.
/// Desktop-only preferences stay reachable without crowding the tabletop controls.
struct GameSettingsView: View {
    @ObservedObject var session: GameSession
    @State private var showClassicOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.headline)
            VStack(spacing: 0) {
                audioRow("Music", symbol: "music.note", key: "musicSetting", firstButton: 930, identifier: "music")
                Divider().padding(.leading, 46)
                audioRow("Sound effects", symbol: "speaker.wave.2", key: "soundSetting", firstButton: 941, identifier: "sound")
            }.padding(.horizontal, 14)
                .background(.brown.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { session.state.bool("running") }, set: { enabled in
                    guard let option = widget(enabled ? 153 : 152, root: 147) else { return }
                    session.activateWidget(option)
                })) { Label("Run", systemImage: "figure.run") }
                    .frame(minHeight: 54).accessibilityValue(session.state.bool("running") ? "On" : "Off")
                    .accessibilityIdentifier("game.settings.run")
                    .disabled(!session.connected || widget(152, root: 147) == nil)
                Divider().padding(.leading, 46)
                Toggle(isOn: Binding(get: { widget(150, root: 147)?.bool("active") == true }, set: { enabled in
                    if let option = widget(enabled ? 150 : 151, root: 147) { session.activateWidget(option) }
                })) { Label("Auto-retaliate", systemImage: "shield") }
                    .frame(minHeight: 54)
                    .accessibilityValue(widget(150, root: 147)?.bool("active") == true ? "On" : "Off")
                    .accessibilityIdentifier("game.settings.retaliate")
                    .disabled(!session.connected || widget(150, root: 147) == nil)
            }.padding(.horizontal, 14)
                .background(.brown.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            Button { showClassicOptions = true } label: {
                HStack {
                    Label("Classic client", systemImage: "desktopcomputer")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.padding(.vertical, 8).frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).accessibilityIdentifier("game.settings.classic")
                .popover(isPresented: $showClassicOptions) { classicOptions }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("game.settings")
    }

    private func widget(_ id: Int, root: Int = 904) -> JSONObject? {
        session.state.objects("ui").first { $0.int("id") == id && $0.int("root") == root && $0.int("button") > 0 }
    }
    private func audioRow(_ title: String, symbol: String, key: String, firstButton: Int, identifier: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                audioLabel(title, symbol: symbol).frame(width: 158, alignment: .leading)
                audioChoices(title, key: key, firstButton: firstButton, identifier: identifier)
            }
            VStack(alignment: .leading, spacing: 8) {
                audioLabel(title, symbol: symbol)
                audioChoices(title, key: key, firstButton: firstButton, identifier: identifier)
            }
        }.padding(.vertical, 11)
    }
    private func audioLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 28).accessibilityHidden(true)
            Text(title)
        }
    }
    private func audioChoices(_ title: String, key: String, firstButton: Int, identifier: String) -> some View {
            HStack(spacing: 4) {
                ForEach(0...4, id: \.self) { level in
                    let option = widget(firstButton + level)
                    let selected = session.state.int(key, 2) == 4 - level
                    Button {
                        if !selected, let option { session.activateWidget(option) }
                    } label: {
                        Text(level == 0 ? "Off" : String(level)).font(.subheadline.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? Color.orange.opacity(0.35) : Color.brown.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.orange.opacity(0.8) : .clear, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(!session.connected || option == nil)
                        .accessibilityLabel("\(title) \(level == 0 ? "off" : "level \(level)")")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("game.settings.\(identifier).\(level)")
                }
            }.frame(minWidth: 236)
                .accessibilityElement(children: .contain).accessibilityIdentifier("game.settings.\(identifier)")
    }

    private var classicOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Classic client").font(.headline)
                Spacer()
                Button { showClassicOptions = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close classic settings")
                    .accessibilityIdentifier("game.settings.classic.close")
            }
            Text("These preferences apply in the desktop client.").font(.caption).foregroundStyle(.secondary)
            choiceRow("Brightness", symbol: "sun.max", choices: [(905, "Dark"), (907, "Normal"), (909, "Bright"), (911, "Very bright")])
            choiceRow("Mouse buttons", symbol: "computermouse", choices: [(914, "One"), (913, "Two")])
            choiceRow("Chat effects", symbol: "text.bubble", choices: [(916, "Off"), (915, "On")])
            choiceRow("Split private chat", symbol: "bubble.left.and.bubble.right", choices: [(958, "Off"), (957, "On")])
        }.padding(20).frame(width: 420)
            .accessibilityElement(children: .contain).accessibilityIdentifier("game.settings.classic.menu")
    }
    private func choiceRow(_ title: String, symbol: String, choices: [(Int, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline)
            HStack(spacing: 6) {
                ForEach(choices, id: \.0) { id, label in
                    let option = widget(id)
                    let selected = option?.bool("active") == true
                    Button { if !selected, let option { session.activateWidget(option) } } label: {
                        Text(label).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? Color.orange.opacity(0.35) : Color.brown.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.orange.opacity(0.8) : .clear, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(!session.connected || option == nil)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("game.widget.\(id)")
                }
            }
        }
    }
}
