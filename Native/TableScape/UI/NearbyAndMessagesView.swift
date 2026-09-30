import SwiftUI

/// Secondary gameplay information stays in its own window so inventory and the
/// original skill/spell grids can use the entire controls panel.
struct NearbyAndMessagesView: View {
    @ObservedObject var session: GameSession
    @State private var showingMessages = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button("Nearby", systemImage: "location.magnifyingglass") { showingMessages = false }
                    .tint(showingMessages ? .gray : .orange)
                    .accessibilityAddTraits(showingMessages ? [] : .isSelected)
                    .accessibilityIdentifier("game.explore.nearby")
                Button("Messages", systemImage: "text.bubble") { searchFocused = false; showingMessages = true }
                    .tint(showingMessages ? .orange : .gray)
                    .accessibilityAddTraits(showingMessages ? .isSelected : [])
                    .accessibilityIdentifier("game.explore.messages")
                Spacer(minLength: 0)
                Button { searchFocused = false; dismissWindow(id: GamePopup.explore.rawValue) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close nearby and messages")
                    .accessibilityIdentifier("game.explore.close")
            }
            if showingMessages { messages }
            else { nearby }
        }.padding(16)
            .frame(minWidth: 380, idealWidth: 420, maxWidth: 620, minHeight: 350, idealHeight: 520, maxHeight: 800)
    }

    private var nearby: some View {
        VStack(spacing: 10) {
            TextField("Find nearby", text: $search).textFieldStyle(.roundedBorder)
                .focused($searchFocused).accessibilityIdentifier("game.nearby.search")
            ScrollView {
                LazyVStack(spacing: 4) {
                    let targets = search.isEmpty ? session.nearbyTargets : session.nearbyTargets.filter {
                        gamePlain($0.object("actor").string("name")).localizedCaseInsensitiveContains(search)
                    }
                    if targets.isEmpty {
                        Text(session.connected ? "Nothing nearby matches." : "Connect to see nearby targets.")
                            .foregroundStyle(.secondary).padding(.vertical, 24)
                    }
                    ForEach(Array(targets.prefix(50).enumerated()), id: \.offset) { _, target in
                        let actor = target.object("actor")
                        Button {
                            searchFocused = false
                            session.showTarget(kind: target.string("kind"), actor: actor)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: target.string("kind") == "npc" ? "person.fill" : target.string("kind") == "obj" ? "shippingbox.fill" : "tree.fill")
                                    .frame(width: 22)
                                Text(gamePlain(actor.string("name")))
                                Spacer()
                                Text(String(format: "%.0f tiles", target.double("distance"))).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 10).padding(.horizontal, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!session.connected)
                            .accessibilityIdentifier("game.nearby.name.\(gamePlain(actor.string("name")))")
                    }
                }
            }.accessibilityIdentifier("game.nearby.scroll")
        }
    }

    private var messages: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                let entries = session.state.strings("messages")
                if entries.isEmpty {
                    Text("No game messages yet.").foregroundStyle(.secondary).padding(.vertical, 24)
                }
                ForEach(Array(entries.suffix(100).enumerated()), id: \.offset) { index, text in
                    Text(gamePlain(text)).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("game.message.\(index)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("game.messages")
    }
}
