import Foundation
#if !POPUP_ROUTING_CHECKS
import SwiftUI
import Combine
#endif

enum GamePopup: String, CaseIterable {
    case options = "game-options"
    case dialogue = "game-dialogue"
    case activity = "game-activity"
    case amount = "game-amount"
    case map = "game-map"
    case explore = "game-explore"
}

struct GamePopupDemand: Equatable {
    var keys: [GamePopup: String] = [:]
}

/// Only workflow edges request windows. Polls and conversation page changes never
/// re-open a manually hidden surface or move an already positioned conversation.
@MainActor final class GamePopupCoordinator {
    struct Change: Equatable {
        let popup: GamePopup
        let open: Bool
    }
    private var previous = GamePopupDemand()
    #if !POPUP_ROUTING_CHECKS
    private var observation: AnyCancellable?
    private var reconcileScheduled = false
    private var present: ((GamePopup, Bool) -> Void)?

    func bind(session: GameSession, present: @escaping (GamePopup, Bool) -> Void) {
        // Retain the app's window actions so world clicks still work when the
        // inventory window is hidden and only the immersive scene remains.
        self.present = present
        if observation == nil {
            observation = session.objectWillChange.sink { [weak self, weak session] _ in
                guard let self, !self.reconcileScheduled else { return }
                self.reconcileScheduled = true
                Task { @MainActor [weak self, weak session] in
                    guard let self, let session else { return }
                    self.reconcileScheduled = false
                    self.reconcile(session)
                }
            }
        }
        reconcile(session)
    }
    private func reconcile(_ session: GameSession) {
        for change in update(GamePopupDemand(session: session)) { present?(change.popup, change.open) }
    }
    #endif
    func update(_ demand: GamePopupDemand) -> [Change] {
        defer { previous = demand }
        return GamePopup.allCases.compactMap { popup in
            guard previous.keys[popup] != demand.keys[popup] else { return nil }
            return Change(popup: popup, open: demand.keys[popup] != nil)
        }
    }
}

#if !POPUP_ROUTING_CHECKS
@MainActor private extension GamePopupDemand {
    init(session: GameSession) {
        guard session.connected else { self.init(); return }
        let epoch = String(session.sessionEpoch)
        var keys: [GamePopup: String] = [:]
        if let target = session.selectedTarget {
            // Refreshed actor dictionaries are not new user requests. A repeated
            // click after a system window-close must still reopen the same target.
            keys[.options] = epoch + ":" + String(session.targetMenuRequest) + ":" + target.string("key")
        }
        if session.state.int("chatRoot", -1) >= 0 { keys[.dialogue] = epoch }
        if session.state.int("mainRoot", -1) >= 0 || session.state.bool("allowDesign") { keys[.activity] = epoch }
        if session.state.bool("countDialog") { keys[.amount] = epoch }
        self.init(keys: keys)
    }
}

/// Hosted by every surviving app window. The shared coordinator makes multiple
/// hosts harmless when transitioning between the home, controls and popup scenes.
struct GamePopupRouter: ViewModifier {
    @ObservedObject var session: GameSession
    let coordinator: GamePopupCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    func body(content: Content) -> some View {
        content.onAppear {
            let open = openWindow, dismiss = dismissWindow
            coordinator.bind(session: session) { popup, shouldOpen in
                if shouldOpen { open(id: popup.rawValue, value: popup.rawValue) }
                else { dismiss(id: popup.rawValue) }
            }
        }
    }
}

struct GamePopupWindow: View {
    let popup: GamePopup
    @ObservedObject var session: GameSession
    let scene: GameScene
    let coordinator: GamePopupCoordinator
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        surface
            .id(session.sessionEpoch)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("game.popup." + identifier)
            .modifier(GamePopupRouter(session: session, coordinator: coordinator))
    }
    private var identifier: String {
        switch popup {
        case .options: return "options"
        case .dialogue: return "dialogue"
        case .activity: return "activity"
        case .amount: return "amount"
        case .map: return "map"
        case .explore: return "explore"
        }
    }
    @ViewBuilder private var surface: some View {
        switch popup {
        case .options:
            Group {
                if let target = session.selectedTarget { TargetActionsView(session: session, target: target) }
                else { Color.clear.frame(height: 1) }
            }.frame(width: 340).fixedSize(horizontal: false, vertical: true)
        case .dialogue:
            ScrollView {
                if session.state.int("chatRoot", -1) >= 0 { DialogueView(session: session, assets: scene.assets) }
            }.frame(minWidth: 420, idealWidth: 580, maxWidth: 760, minHeight: 180, idealHeight: 280, maxHeight: 560)
        case .activity:
            ScrollView {
                if session.state.bool("allowDesign") {
                    let epoch = session.sessionEpoch, root = session.state.int("mainRoot", -1)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Spacer()
                            Button("Close") {
                                if session.connected, session.sessionEpoch == epoch, session.state.bool("allowDesign"), session.state.int("mainRoot", -1) == root { session.send(["kind": "close"]) }
                            }
                        }
                        AppearanceView(session: session)
                    }.padding(22)
                } else if session.state.int("mainRoot", -1) >= 0 { MainInterfaceView(session: session) }
            }.frame(minWidth: 420, idealWidth: 620, maxWidth: 900, minHeight: 320, idealHeight: 580, maxHeight: 850)
        case .amount:
            Group {
                if session.state.bool("countDialog") { AmountEntryView(session: session).id(session.state.int("mainRoot", -1)) }
                else { Color.clear.frame(height: 1) }
            }.frame(width: 340).fixedSize(horizontal: false, vertical: true)
        case .explore:
            NearbyAndMessagesView(session: session)
        case .map:
            VStack(spacing: 14) {
                HStack {
                    Text("Map").font(.headline)
                    Spacer()
                    Button { dismissWindow(id: GamePopup.map.rawValue) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Close map").accessibilityIdentifier("game.map.close")
                }
                NativeMinimap(scene: scene)
            }.padding(20).frame(width: 240).fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
