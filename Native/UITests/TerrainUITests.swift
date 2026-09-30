import XCTest

/// Ordinary UI route to the ground and river below a Lumbridge tower.
/// Framebuffer captures are taken separately with simctl during the named pauses;
/// visionOS XCTest screenshot attachments can be 1x1 and are not visual proof.
final class TerrainUITests: XCTestCase {
    private var app: XCUIApplication?

    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        guard let app, app.state != .notRunning else { return }
        closeTargetOptions()
        closeExplore()
        let map = app.buttons["game.map.close"].firstMatch
        if map.exists && map.isHittable { map.tap() }
        if !app.buttons["table.immersive"].firstMatch.exists {
            let leave = app.buttons["table.leave"].firstMatch
            if !leave.exists {
                let utilities = app.buttons["game.moreTabs"].firstMatch
                if utilities.exists && utilities.isHittable { utilities.tap() }
            }
            if leave.waitForExistence(timeout: 3) && leave.isHittable {
                leave.tap()
                _ = app.buttons["table.immersive"].firstMatch.waitForExistence(timeout: 10)
            }
        }
        let disconnect = app.buttons["Disconnect"].firstMatch
        if disconnect.exists && disconnect.isHittable {
            disconnect.tap()
            _ = app.buttons["game.connect"].firstMatch.waitForExistence(timeout: 10)
            Thread.sleep(forTimeInterval: 1)
        }
        app.terminate()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app!.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func wait(_ seconds: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: seconds) == .completed
    }

    private func closeExplore() {
        let close = app!.buttons["game.explore.close"].firstMatch
        if close.exists && close.isHittable { close.tap() }
    }

    private func openNearby() {
        if !element("game.popup.explore").exists {
            let open = app!.buttons["game.explore.open"].firstMatch
            if !open.exists { app!.buttons["game.moreTabs"].firstMatch.tap() }
            XCTAssertTrue(open.waitForExistence(timeout: 5), "More tools offers Nearby & messages")
            open.tap()
            XCTAssertTrue(element("game.popup.explore").waitForExistence(timeout: 10), "Nearby opens in its own window")
        }
        if !app!.textFields["game.nearby.search"].firstMatch.exists {
            app!.buttons["game.explore.nearby"].firstMatch.tap()
        }
    }

    private func closeTargetOptions() {
        let close = app!.buttons["game.options.close"].firstMatch
        if close.exists && close.isHittable { close.tap() }
    }

    private func selectNearest(_ name: String) {
        closeTargetOptions()
        app!.buttons["game.tab.0"].firstMatch.tap()
        openNearby()
        let search = app!.textFields["game.nearby.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        let old = search.value as? String ?? ""
        if old != name {
            XCTAssertTrue(search.isHittable, "Nearby search is reachable in its separate window")
            search.tap()
            if !old.isEmpty && old != search.placeholderValue {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            search.typeText(name)
        }
        let target = app!.buttons["game.nearby.name." + name].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 15), "Original nearby target exists: " + name)
        let scroll = app!.scrollViews["game.nearby.scroll"].firstMatch
        for _ in 0..<5 where !target.isHittable && scroll.exists { scroll.swipeDown() }
        XCTAssertTrue(target.isHittable, "The nearest matching target is reachable")
        target.tap()
        XCTAssertTrue(element("game.popup.options").waitForExistence(timeout: 10))
    }

    private func operation(_ name: String) -> XCUIElement {
        element("game.popup.options").buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label ==[c] %@", "game.target.op.", name)).firstMatch
    }

    /// Read the current server-advertised ladder actions through fresh local menu
    /// selections. Opening or closing this menu never sends a climb action.
    private func waitForLadder(up: Bool? = nil, down: Bool, seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            closeTargetOptions()
            let ladder = app!.buttons["game.nearby.name.Ladder"].firstMatch
            if ladder.exists && ladder.isHittable {
                ladder.tap()
                if element("game.popup.options").waitForExistence(timeout: 1),
                   up.map({ operation("Climb-up").exists == $0 }) ?? true,
                   operation("Climb-down").exists == down {
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        return false
    }

    private func capturePause(_ stage: String) {
        closeTargetOptions()
        closeExplore()
        // The root runner uses this marker to capture the actual simulator framebuffer.
        print("TABLESCAPE_TERRAIN_CAPTURE " + stage)
        Thread.sleep(forTimeInterval: 15)
        XCTAssertTrue(app!.buttons["game.tab.3"].firstMatch.exists, "Gameplay controls remain present at " + stage)
        XCTAssertFalse(app!.buttons["Reconnect"].firstMatch.exists, "No connection failure at " + stage)
        XCTAssertFalse(app!.buttons["Cancel reconnect"].firstMatch.exists, "No connection recovery at " + stage)
    }

    func testLowerTerrainFromTower() throws {
        let application = XCUIApplication()
        app = application
        let character = "unityt" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        application.launchArguments = ["--tablescape-connect", "--tablescape-immersive", "--tablescape-profile", "--tablescape-user=" + character]
        application.launch()
        XCTAssertTrue(application.buttons["game.tab.3"].firstMatch.waitForExistence(timeout: 35))
        XCTAssertTrue(application.buttons["game.moreTabs"].firstMatch.waitForExistence(timeout: 25))
        selectNearest("Ladder")
        let up = operation("Climb-up")
        XCTAssertTrue(up.waitForExistence(timeout: 10), "The ground-level tower ladder advertises Climb-up")
        XCTAssertFalse(operation("Climb-down").exists, "The fresh character is at the bottom of the tower ladder")
        up.tap()
        if !waitForLadder(down: true, seconds: 20) {
            XCTAssertTrue(operation("Climb-up").exists && !operation("Climb-down").exists,
                          "Only open the entrance while the current ladder still advertises ground-level actions")
            // A closed tower door blocks the original approach path. Explicitly
            // opening it replaces that action before a fresh Ladder selection.
            selectNearest("Door")
            let open = operation("Open")
            XCTAssertTrue(open.waitForExistence(timeout: 10), "The blocked tower entrance advertises Open")
            open.tap()
            XCTAssertTrue(wait { !self.element("game.popup.options").exists })
            Thread.sleep(forTimeInterval: 3)
            selectNearest("Ladder")
            XCTAssertFalse(operation("Climb-down").exists, "The newly selected ladder remains downstairs")
            let freshUp = operation("Climb-up")
            XCTAssertTrue(freshUp.waitForExistence(timeout: 10))
            freshUp.tap()
        }
        XCTAssertTrue(waitForLadder(down: true, seconds: 35),
                      "The original ladder now offers Climb-down after the server moves the character upstairs")
        // Lower chunks load asynchronously after the confirmed floor transition.
        Thread.sleep(forTimeInterval: 8)
        capturePause("tower-floor-1")
        selectNearest("Ladder")
        let down = operation("Climb-down")
        XCTAssertTrue(down.waitForExistence(timeout: 10))
        down.tap()
        XCTAssertTrue(waitForLadder(up: true, down: false, seconds: 30),
                      "Climb-down returns to the original ground ladder with no lower floor")
        Thread.sleep(forTimeInterval: 5)
        capturePause("tower-ground-with-river")
    }
}
