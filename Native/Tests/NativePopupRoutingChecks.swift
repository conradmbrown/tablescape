import Foundation

/// Tests the real pure coordinator with explicit demand values. Window-system events
/// are modeled locally; the conditional build excludes SwiftUI and session mapping.
@main struct NativePopupRoutingChecks {
    @MainActor static func main() {
        let coordinator = GamePopupCoordinator()
        var visible = Set<GamePopup>()
        var verified = 0
        func expect(_ demand: GamePopupDemand, _ expected: [GamePopupCoordinator.Change], _ context: String) {
            let actual = coordinator.update(demand)
            precondition(actual == expected, "\(context): unexpected routing changes \(actual)")
            for change in actual {
                if change.open { visible.insert(change.popup) } else { visible.remove(change.popup) }
            }
            verified += 1
        }
        func open(_ popup: GamePopup) -> GamePopupCoordinator.Change { .init(popup: popup, open: true) }
        func close(_ popup: GamePopup) -> GamePopupCoordinator.Change { .init(popup: popup, open: false) }
        func duplicateHosts(_ demand: GamePopupDemand, _ context: String) {
            for host in ["home", "controls", "popup", "replacement host"] {
                expect(demand, [], "\(context), \(host)")
            }
        }

        // Initial hosts have no workflow; neither polls nor duplicate subscriptions
        // should issue blanket dismissals against other app windows.
        let empty = GamePopupDemand()
        expect(empty, [], "initial empty host")
        duplicateHosts(empty, "duplicate initial host")

        var demand = GamePopupDemand(keys: [.options: "epoch1:request1:npc42"])
        expect(demand, [open(.options)], "first explicit target request")
        duplicateHosts(demand, "same target published by every host")
        visible.remove(.options) // System window-close does not alter game demand.
        for poll in 0..<50 { expect(demand, [], "unchanged actor poll after hide \(poll)") }
        precondition(!visible.contains(.options), "Polling reopened manually hidden options")
        demand.keys[.options] = "epoch1:request2:npc42"
        expect(demand, [open(.options)], "same actor explicitly requested again")
        duplicateHosts(demand, "repeated request deduplicated")
        precondition(visible.contains(.options), "Explicit repeated click did not reopen options")

        // Target action transitions into a conversation. Server dialogue pages share
        // a conversation key, so they do not produce repeated window-open actions.
        demand = GamePopupDemand(keys: [.dialogue: "epoch1"])
        expect(demand, [close(.options), open(.dialogue)], "target action starts conversation")
        for page in 0..<12 { duplicateHosts(demand, "conversation page \(page) has constant key") }
        visible.remove(.dialogue)
        for page in 0..<12 { expect(demand, [], "conversation page while manually hidden \(page)") }
        precondition(!visible.contains(.dialogue), "Hidden conversation was reopened")
        visible.insert(.dialogue) // Explicit Conversation shortcut opens directly.
        duplicateHosts(demand, "new host after explicit shortcut")
        expect(empty, [close(.dialogue)], "conversation ends")
        duplicateHosts(empty, "closed conversation poll")
        expect(demand, [open(.dialogue)], "new conversation after completed workflow")

        // Amount entry must coexist with its bank/shop/trade activity. Closing or
        // reopening either channel cannot inadvertently change the other channel.
        demand.keys[.activity] = "epoch1"
        expect(demand, [open(.activity)], "activity opens alongside conversation")
        demand.keys[.amount] = "epoch1"
        expect(demand, [open(.amount)], "amount opens over activity")
        duplicateHosts(demand, "concurrent workflow hosts")
        precondition(visible == [.dialogue, .activity, .amount], "Concurrent channels were replaced")
        visible.remove(.activity)
        expect(demand, [], "hidden activity remains hidden while amount is active")
        demand.keys[.amount] = nil
        expect(demand, [close(.amount)], "amount finishes without reopening activity")
        precondition(!visible.contains(.activity), "Amount completion reopened hidden activity")
        demand.keys[.amount] = "epoch1"
        expect(demand, [open(.amount)], "next amount request after completion")
        demand.keys[.activity] = nil
        expect(demand, [close(.activity)], "activity closes independently")
        precondition(visible.contains(.amount), "Activity close dismissed amount")
        demand.keys[.activity] = "epoch1"
        expect(demand, [open(.activity)], "activity restarts independently")

        // Disconnect dismisses only channels represented by prior workflow demand;
        // map is manually managed and absent from this supplied demand.
        expect(empty, [close(.dialogue), close(.activity), close(.amount)], "disconnect")
        precondition(visible.isEmpty, "Disconnect retained a demanded workflow window")
        duplicateHosts(empty, "remaining hosts see disconnected state")
        demand = GamePopupDemand(keys: [.options: "epoch2:request1:npc42", .dialogue: "epoch2", .activity: "epoch2", .amount: "epoch2"])
        expect(demand, [open(.options), open(.dialogue), open(.activity), open(.amount)], "new session workflows")
        duplicateHosts(demand, "new session host handoff")
        let replaced = GamePopupDemand(keys: [.options: "epoch3:request1:npc42", .dialogue: "epoch3", .activity: "epoch3", .amount: "epoch3"])
        expect(replaced, [open(.options), open(.dialogue), open(.activity), open(.amount)], "session epoch changes even when actor is the same")
        duplicateHosts(replaced, "replacement session polls")
        expect(empty, [close(.options), close(.dialogue), close(.activity), close(.amount)], "all workflows end")
        expect(empty, [], "repeated disconnect does not emit extra closes")

        print("PASS real popup coordinator: \(verified) routing assertions; duplicate hosts/polls deduplicated; manual hide stays hidden; repeated same-actor request reopens; constant dialogue key retains placement; amount/activity independent; closes affect previously demanded channels; session replacement handled")
        print("LIMIT: explicit demand values only; POPUP_ROUTING_CHECKS excludes GameSession mapping, SwiftUI open/dismiss dispatch, scene value identity and actual system window lifecycle")
    }
}
