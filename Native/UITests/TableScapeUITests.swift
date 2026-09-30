import XCTest

final class TableScapeUITests: XCTestCase {
    private var runningApp: XCUIApplication?
    private var qaUsername = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Failures still release only this test's fresh character when its controls
        // are reachable. Normal success asserts logout before terminating below.
        if let app = runningApp, app.state != .notRunning {
            for identifier in ["game.skill.detail.close", "game.spell.detail.close", "game.options.close", "game.dialogue.close", "game.explore.close", "game.map.close"] {
                let close = app.buttons[identifier].firstMatch
                if close.exists && close.isHittable { close.tap() }
            }
            let leave = app.buttons["table.leave"].firstMatch
            if !app.buttons["table.immersive"].firstMatch.exists && !leave.exists {
                let closeTools = app.buttons["game.tools.close"].firstMatch
                if closeTools.exists && closeTools.isHittable { closeTools.tap() }
                let controls = app.buttons["table.controls"].firstMatch
                if controls.exists && controls.isHittable {
                    controls.tap()
                    _ = leave.waitForExistence(timeout: 3)
                }
            }
            if leave.exists && leave.isHittable {
                leave.tap()
                _ = app.buttons["table.immersive"].firstMatch.waitForExistence(timeout: 10)
            }
            let disconnect = app.buttons["Disconnect"].firstMatch
            if disconnect.exists && disconnect.isHittable {
                disconnect.tap()
                _ = app.buttons["game.connect"].firstMatch.waitForExistence(timeout: 5)
                Thread.sleep(forTimeInterval: 1)
            }
            app.terminate()
        }
        runningApp = nil
    }

    private func launchCharacter(immersive: Bool = false, unplaced: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let name = "unityu" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        qaUsername = name
        app.launchArguments = ["--tablescape-connect", "--tablescape-profile", "--tablescape-user=" + name]
        if immersive { app.launchArguments.append("--tablescape-immersive") }
        if unplaced { app.launchArguments.append("--tablescape-unplaced") }
        runningApp = app
        app.launch()
        XCTAssertTrue(app.buttons["game.tab.3"].firstMatch.waitForExistence(timeout: 35), "Fresh QA character connects")
        return app
    }

    private func elements(_ app: XCUIApplication, _ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func reveal(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let element = elements(app, identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Control exists: " + identifier)
        let containing = app.scrollViews.containing(.any, identifier: identifier).firstMatch
        let scroll = containing.exists ? containing : app.scrollViews.firstMatch
        for _ in 0..<10 {
            if element.isHittable { return element }
            guard scroll.exists else { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Control is reachable: " + identifier)
        return element
    }

    @discardableResult
    private func openUtilities(_ app: XCUIApplication) -> XCUIElement {
        let utilities = elements(app, "game.tools").firstMatch
        if !utilities.exists {
            let more = app.buttons["game.moreTabs"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 10), "The fixed toolbelt exposes utilities")
            more.tap()
        }
        XCTAssertTrue(utilities.waitForExistence(timeout: 10), "Utilities popover opens")
        return utilities
    }

    private func closeUtilities(_ app: XCUIApplication) {
        guard elements(app, "game.tools").firstMatch.exists else { return }
        app.buttons["game.tools.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.tools").firstMatch.exists })
    }

    private func utility(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        openUtilities(app)
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Utility exists: " + identifier)
        XCTAssertTrue(button.isHittable, "Utility is reachable: " + identifier)
        return button
    }

    @discardableResult
    private func openTableControls(_ app: XCUIApplication) -> XCUIElement {
        let menu = elements(app, "table.controls.menu").firstMatch
        if !menu.exists {
            closeUtilities(app)
            let controls = app.buttons["table.controls"].firstMatch
            XCTAssertTrue(controls.waitForExistence(timeout: 10), "The fixed toolbelt exposes table controls")
            XCTAssertTrue(controls.isHittable)
            controls.tap()
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Table controls open independently of game panels")
        return menu
    }

    private func closeTableControls(_ app: XCUIApplication) {
        guard elements(app, "table.controls.menu").firstMatch.exists else { return }
        let close = app.buttons["table.controls.close"].firstMatch
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "table.controls.menu").firstMatch.exists })
    }

    private func tableControl(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        openTableControls(app)
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Table action exists: " + identifier)
        XCTAssertTrue(button.isHittable, "Table action is reachable: " + identifier)
        return button
    }

    private func awaitFloatingControls(_ app: XCUIApplication) {
        XCTAssertTrue(elements(app, "game.toolbelt").firstMatch.waitForExistence(timeout: 25))
        XCTAssertTrue(waitUntil(25) { !app.buttons["table.immersive"].firstMatch.exists }, "Floating controls replace the closed main window")
    }

    private func awaitVolumeMeshes(_ app: XCUIApplication) {
        let volume = elements(app, "world.volume").firstMatch
        XCTAssertTrue(waitUntil(45) {
            guard volume.exists, let reading = volume.value as? String else { return false }
            return reading.range(of: "\\b[1-9][0-9,]* meshes · [1-9][0-9,]* triangles\\b", options: .regularExpression) != nil
        }, "The real volume renderer uploads and installs nonempty mesh geometry")
    }

    private func awaitVolumeInput(_ app: XCUIApplication) {
        let volume = elements(app, "world.volume").firstMatch
        XCTAssertTrue(waitUntil(45) {
            guard volume.exists, let reading = volume.value as? String else { return false }
            return reading.contains("Map ready")
        }, "Real map collision surfaces become enabled without simulator-only table placement")
    }

    private func leaveTable(_ app: XCUIApplication) {
        tableControl(app, "table.leave").tap()
        XCTAssertTrue(app.buttons["table.immersive"].firstMatch.waitForExistence(timeout: 10), "Leaving immersion restores the main window")
    }

    private func assertSinglePopup(_ app: XCUIApplication, _ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(elements(app, identifier).firstMatch.waitForExistence(timeout: 10), "Popup opens: " + identifier, file: file, line: line)
        // Observe multiple native update cycles, including delayed window opening.
        let end = Date().addingTimeInterval(1)
        repeat {
            XCTAssertEqual(elements(app, identifier).count, 1, "Exactly one popup: " + identifier, file: file, line: line)
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < end
    }

    private func dialogueSignature(_ app: XCUIApplication) -> String {
        let dialogue = elements(app, "game.dialogue").firstMatch
        let text = dialogue.staticTexts.allElementsBoundByIndex.map(\.label)
        let controls = dialogue.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "game.widget.")).allElementsBoundByIndex
            .map { $0.identifier + ":" + $0.label }
        return (text + controls).joined(separator: "\n")
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func logOut(_ app: XCUIApplication) {
        let disconnect = app.buttons["Disconnect"].firstMatch
        XCTAssertTrue(disconnect.waitForExistence(timeout: 10))
        disconnect.tap()
        XCTAssertTrue(app.buttons["game.connect"].firstMatch.waitForExistence(timeout: 10))
        // The UI clears immediately; give its owned remote DELETE time to finish.
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
    }

    func testNativePanelsAndImmersion() throws {
        let app = launchCharacter()
        attachScreen("Native game and inventory")
        app.buttons["game.tab.1"].firstMatch.tap()
        XCTAssertTrue(app.buttons["game.skill.0"].firstMatch.waitForExistence(timeout: 10), "The original Attack icon is reachable")
        app.buttons["game.tab.6"].firstMatch.tap()
        app.buttons["game.tab.3"].firstMatch.tap()
        app.buttons["table.immersive"].firstMatch.tap()
        awaitFloatingControls(app)
        Thread.sleep(forTimeInterval: 3)
        attachScreen("Immersive virtual table")
        leaveTable(app)
        // Real force quit: the gateway still holds this character's session. A new
        // login would fail; the next app process must recover its saved bearer.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["game.tab.3"].firstMatch.waitForExistence(timeout: 25), "Character resumes after process termination")
        logOut(app)
    }

    func testCompactInventoryAndFixedToolbelt() throws {
        let app = launchCharacter(immersive: true)
        awaitFloatingControls(app)
        let inventory = app.buttons["game.tab.3"].firstMatch
        inventory.tap()
        let belt = elements(app, "game.toolbelt").firstMatch
        let slots = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "game\\.item\\.[0-9]+\\.[0-9]+|game\\.inventory\\.empty\\.[0-9]+"))
        XCTAssertTrue(waitUntil { slots.count == 28 }, "All 28 occupied and empty inventory slots are present")
        let beltFrame = belt.frame
        let scroll = elements(app, "game.panel.scroll").firstMatch
        XCTAssertTrue(scroll.exists)
        var slotNumbers = Set<Int>()
        for slot in slots.allElementsBoundByIndex {
            let number = Int(slot.identifier.split(separator: ".").last ?? "")
            if let number { slotNumbers.insert(number) }
            XCTAssertTrue(slot.isHittable, "Inventory slot is visible without scrolling: " + slot.identifier)
            XCTAssertTrue(scroll.frame.insetBy(dx: -1, dy: -1).contains(slot.frame), "The complete slot fits inside the initial inventory viewport")
            XCTAssertLessThanOrEqual(slot.frame.maxY, beltFrame.minY + 1, "The fixed toolbelt sits below inventory")
            if slot.identifier.hasPrefix("game.item.") {
                let itemName = String(slot.label.split(separator: ",", maxSplits: 1).first ?? "")
                XCTAssertFalse(itemName.isEmpty, "Icon-only items retain accessible item names")
                XCTAssertFalse(slot.staticTexts[itemName].exists, "Inventory item names do not consume visual rows")
            }
        }
        XCTAssertEqual(slotNumbers, Set(0..<28), "The grid contains every slot exactly once")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", qaUsername)).firstMatch.exists, "The player-name header is removed")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " · Floor ")).firstMatch.exists, "The coordinate header is removed")
        XCTAssertFalse(app.images["heart.fill"].firstMatch.exists, "The HP header is removed")
        XCTAssertFalse(app.buttons["table.setup"].firstMatch.exists)
        XCTAssertFalse(app.buttons["table.leave"].firstMatch.exists, "Table actions stay inside their own menu")
        for tab in 0..<7 {
            let button = app.buttons["game.tab.\(tab)"].firstMatch
            XCTAssertTrue(button.isHittable, "Every primary tool is reachable without scrolling")
            XCTAssertTrue(beltFrame.insetBy(dx: -1, dy: -1).contains(button.frame))
        }
        attachScreen("All 28 inventory slots above fixed toolbelt")
        print("TABLESCAPE_TOOLBELT_CAPTURE inventory")
        Thread.sleep(forTimeInterval: 5)

        XCTAssertFalse(app.textFields["game.nearby.search"].firstMatch.exists, "Nearby content is outside the inventory panel")
        XCTAssertFalse(elements(app, "game.messages").firstMatch.exists, "Messages are outside the inventory panel")
        app.buttons["game.tab.1"].firstMatch.tap()
        XCTAssertEqual(belt.frame.minY, beltFrame.minY, accuracy: 1, "Switching compact panels does not move the fixed toolbelt")
        XCTAssertEqual(belt.frame.height, beltFrame.height, accuracy: 1)
        XCTAssertTrue(inventory.isHittable)
        inventory.tap()
        XCTAssertTrue(waitUntil { slots.count == 28 && slots.allElementsBoundByIndex.allSatisfy(\.isHittable) }, "Returning to inventory reveals all 28 slots")

        utility(app, "game.tab.10").tap()
        XCTAssertTrue(app.buttons["Log out"].firstMatch.waitForExistence(timeout: 10), "A secondary tab opens its real game panel")
        XCTAssertFalse(elements(app, "game.tools").firstMatch.exists, "Selecting a secondary tab dismisses utilities")
        inventory.tap()
        openUtilities(app)
        XCTAssertFalse(app.buttons["table.setup"].firstMatch.exists, "Table placement is separate from More tools")
        XCTAssertFalse(app.buttons["table.leave"].firstMatch.exists, "Leave table is separate from More tools")
        closeUtilities(app)
        openTableControls(app)
        XCTAssertTrue(app.buttons["table.setup"].firstMatch.isHittable, "Table placement remains reachable inside its own menu")
        XCTAssertTrue(app.buttons["table.leave"].firstMatch.isHittable)
        print("TABLESCAPE_TOOLBELT_CAPTURE table-controls")
        Thread.sleep(forTimeInterval: 5)
        closeTableControls(app)
        XCTAssertFalse(app.buttons["table.setup"].firstMatch.exists)
        XCTAssertFalse(app.buttons["table.leave"].firstMatch.exists)
        utility(app, "game.tab.10").tap()
        let logout = app.buttons["Log out"].firstMatch
        XCTAssertTrue(logout.waitForExistence(timeout: 10))
        logout.tap()
        XCTAssertTrue(app.buttons["game.connect"].firstMatch.waitForExistence(timeout: 10), "In-room logout returns to connection setup")
        XCTAssertTrue(app.buttons["game.moreTabs"].firstMatch.isHittable, "Logout preserves the fixed utility controls")
        leaveTable(app)
        XCTAssertTrue(app.buttons["game.connect"].firstMatch.waitForExistence(timeout: 10), "Leaving the room remains available after logout")
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
    }

    func testCompactOriginalSkillsAndMagicPanels() throws {
        let app = launchCharacter(immersive: true)
        awaitFloatingControls(app)
        let belt = elements(app, "game.toolbelt").firstMatch
        let beltFrame = belt.frame
        app.buttons["game.tab.1"].firstMatch.tap()
        XCTAssertTrue(elements(app, "game.skills").firstMatch.waitForExistence(timeout: 10))
        let skills = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "game\\.skill\\.[0-9]+"))
        XCTAssertTrue(waitUntil { skills.count == 19 }, "All 19 original named skills appear")
        XCTAssertEqual(Set(skills.allElementsBoundByIndex.map(\.identifier)), Set((Array(0..<18) + [20]).map { "game.skill.\($0)" }))
        let scroll = elements(app, "game.panel.scroll").firstMatch
        for skill in skills.allElementsBoundByIndex {
            XCTAssertTrue(skill.isHittable, "Skill icon fits without scrolling: " + skill.identifier)
            XCTAssertTrue(scroll.frame.insetBy(dx: -1, dy: -1).contains(skill.frame))
            XCTAssertFalse(skill.label.isEmpty, "Original skill icons retain accessible names")
        }
        print("TABLESCAPE_WINDOW_CAPTURE skills")
        Thread.sleep(forTimeInterval: 3)
        app.buttons["game.skill.0"].firstMatch.tap()
        XCTAssertTrue(elements(app, "game.skill.detail.0").firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(elements(app, "game.skill.detail.0").firstMatch.staticTexts["Attack"].exists)
        let experience = app.staticTexts["game.skill.xp.0"].firstMatch
        XCTAssertTrue(experience.exists && experience.label.range(of: "^[0-9,]+ XP$", options: .regularExpression) != nil, "Skill details expose numeric experience from the character state")
        let level = app.staticTexts["game.skill.level.0"].firstMatch
        XCTAssertTrue(level.exists && level.label.range(of: "^Level [0-9]+ / [0-9]+$", options: .regularExpression) != nil, "Skill details retain current and base levels")
        app.buttons["game.skill.detail.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.skill.detail.0").firstMatch.exists })

        app.buttons["game.tab.6"].firstMatch.tap()
        let magic = elements(app, "game.magic").firstMatch
        XCTAssertTrue(magic.waitForExistence(timeout: 10))
        let spells = magic.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "game\\.widget\\.[0-9]+"))
        XCTAssertTrue(waitUntil { spells.count == 52 }, "The original spellbook contains all 52 spells")
        for spell in spells.allElementsBoundByIndex {
            XCTAssertTrue(spell.isHittable, "Spell icon fits without scrolling: " + spell.identifier)
            XCTAssertTrue(scroll.frame.insetBy(dx: -1, dy: -1).contains(spell.frame))
            XCTAssertFalse(spell.label.isEmpty)
        }
        XCTAssertEqual(belt.frame.minY, beltFrame.minY, accuracy: 1, "Original icon panels preserve toolbelt position")
        print("TABLESCAPE_WINDOW_CAPTURE spells")
        Thread.sleep(forTimeInterval: 3)
        let windStrike = app.buttons["game.widget.1152"].firstMatch
        XCTAssertTrue(windStrike.label.localizedCaseInsensitiveContains("Wind strike"))
        windStrike.press(forDuration: 1)
        let details = app.buttons["Spell details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.tap()
        let spellDetails = elements(app, "game.spell.detail.1152").firstMatch
        XCTAssertTrue(spellDetails.waitForExistence(timeout: 10))
        XCTAssertTrue(spellDetails.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Wind strike")).firstMatch.exists)
        XCTAssertTrue(spellDetails.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "/")).count > 0, "Original spell details retain rune requirements")
        app.buttons["game.spell.detail.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.spell.detail.1152").firstMatch.exists })
        windStrike.tap()
        let selection = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", "Cast ", "Wind strike")).firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 10), "The original spell icon selects the real spell-targeting workflow")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !selection.exists }, "Spell selection can be cancelled without casting")
        app.buttons["game.tab.3"].firstMatch.tap()
        leaveTable(app)
        logOut(app)
    }

    func testVolumetricTableWindowLifecycle() throws {
        let app = launchCharacter(unplaced: true)
        let openTable = app.buttons["table.window.open"].firstMatch
        XCTAssertTrue(openTable.waitForExistence(timeout: 10))
        openTable.tap()
        let volume = elements(app, "world.volume").firstMatch
        let belt = elements(app, "game.toolbelt").firstMatch
        let panel = elements(app, "game.panel.scroll").firstMatch
        let inventory = app.buttons["game.tab.3"].firstMatch
        let skills = app.buttons["game.tab.1"].firstMatch
        let controls = app.buttons["table.controls"].firstMatch
        func assertCollapsedToolbelt() {
            XCTAssertTrue(waitUntil(25) { !app.buttons["table.immersive"].firstMatch.exists }, "The main window closes when the volume opens")
            XCTAssertTrue(waitUntil { belt.exists && (belt.value as? String) == "Collapsed" && !panel.exists }, "Collapsing hides only the active panel")
            assertSinglePopup(app, "game.toolbelt")
            for button in [inventory, skills, controls] {
                XCTAssertTrue(button.exists && button.isHittable, "Primary tools remain directly usable while the panel is collapsed")
            }
            XCTAssertFalse(app.buttons["table.volume.controls"].firstMatch.exists, "The old extra game-menu toggle is removed")
        }
        XCTAssertTrue(volume.waitForExistence(timeout: 30), "A normal public action opens the true 3D table volume")
        assertCollapsedToolbelt()
        assertSinglePopup(app, "world.volume")
        awaitVolumeMeshes(app)
        awaitVolumeInput(app)
        print("TABLESCAPE_WINDOW_CAPTURE volume-toolbar")
        attachScreen("Volume with persistent collapsed toolbelt")

        inventory.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { (belt.value as? String) == "Expanded" })
        let slots = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "game\\.item\\.[0-9]+\\.[0-9]+|game\\.inventory\\.empty\\.[0-9]+"))
        XCTAssertTrue(waitUntil { slots.count == 28 }, "Inventory opens directly from the permanent icon and contains every slot")
        XCTAssertEqual(Set(slots.allElementsBoundByIndex.compactMap { Int($0.identifier.split(separator: ".").last ?? "") }), Set(0..<28))
        for slot in slots.allElementsBoundByIndex {
            XCTAssertTrue(slot.isHittable, "Inventory slot is visible without scrolling: " + slot.identifier)
            XCTAssertTrue(panel.frame.insetBy(dx: -1, dy: -1).contains(slot.frame), "All inventory slots fit above the toolbelt")
        }
        attachScreen("Volume inventory above permanent toolbelt")
        inventory.tap()
        assertCollapsedToolbelt()
        XCTAssertEqual(slots.count, 0, "The active inventory icon collapses its grid")
        skills.tap()
        XCTAssertTrue(elements(app, "game.skills").firstMatch.waitForExistence(timeout: 10), "A different tool icon reopens its own panel")
        XCTAssertTrue(app.buttons["game.skill.0"].firstMatch.isHittable)
        XCTAssertTrue(waitUntil { (belt.value as? String) == "Expanded" })
        skills.tap()
        assertCollapsedToolbelt()

        openTableControls(app)
        assertSinglePopup(app, "table.controls.menu")
        XCTAssertTrue(app.buttons["table.leave"].firstMatch.isHittable, "Leave is reachable even with no game panel open")
        XCTAssertFalse(app.buttons["table.setup"].firstMatch.exists, "The window does not offer physical-table placement")
        XCTAssertFalse(panel.exists, "Table settings do not expand the active game panel")
        closeTableControls(app)
        assertCollapsedToolbelt()
        utility(app, "game.explore.open").tap()
        assertSinglePopup(app, "game.popup.explore")
        XCTAssertTrue(app.textFields["game.nearby.search"].firstMatch.waitForExistence(timeout: 10))
        // Use the live nearest target: wandering NPCs such as Hans may leave
        // this fresh character's streamed area during a menu lifecycle test.
        let nearby = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "game.nearby.name.")).firstMatch
        XCTAssertTrue(nearby.waitForExistence(timeout: 15), "Connected nearby targets appear")
        XCTAssertTrue(nearby.isHittable)
        nearby.tap()
        assertSinglePopup(app, "game.popup.options")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "game.target.op.")).firstMatch.exists,
                      "Real nearby actions remain available while the table volume is open")
        app.buttons["game.options.close"].firstMatch.tap()
        app.buttons["game.explore.close"].firstMatch.tap()
        assertCollapsedToolbelt()
        leaveTable(app)
        XCTAssertTrue(waitUntil { !volume.exists }, "Leaving the table closes its volume")
        XCTAssertTrue(openTable.waitForExistence(timeout: 10))
        openTable.tap()
        XCTAssertTrue(volume.waitForExistence(timeout: 30))
        assertCollapsedToolbelt()
        assertSinglePopup(app, "world.volume")
        awaitVolumeMeshes(app)
        awaitVolumeInput(app)
        inventory.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "The reopened volume's permanent inventory icon remains usable")
        inventory.tap()
        assertCollapsedToolbelt()
        leaveTable(app)
        XCTAssertTrue(waitUntil { !volume.exists })
        logOut(app)
    }

    func testVolumeCombatHitSplats() throws {
        let app = launchCharacter(unplaced: true)
        let openTable = app.buttons["table.window.open"].firstMatch
        XCTAssertTrue(openTable.waitForExistence(timeout: 10))
        openTable.tap()
        let volume = elements(app, "world.volume").firstMatch
        let belt = elements(app, "game.toolbelt").firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 30))
        XCTAssertTrue(waitUntil(25) { !app.buttons["table.immersive"].firstMatch.exists })
        awaitVolumeMeshes(app)
        awaitVolumeInput(app)
        XCTAssertEqual(belt.value as? String, "Collapsed")

        let environment = ProcessInfo.processInfo.environment
        if environment["TABLESCAPE_COMBAT_ZOOM"] == "1" || environment["TEST_RUNNER_TABLESCAPE_COMBAT_ZOOM"] == "1" {
            openTableControls(app)
            let zoomIn = app.buttons["table.zoom.in"].firstMatch
            for _ in 0..<5 where zoomIn.isEnabled { zoomIn.tap() }
            app.buttons["table.controls.close"].firstMatch.tap()
        }
        utility(app, "game.explore.open").tap()
        assertSinglePopup(app, "game.popup.explore")
        let search = app.textFields["game.nearby.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let preferredTarget = environment["TABLESCAPE_COMBAT_TARGET"] ?? environment["TEST_RUNNER_TABLESCAPE_COMBAT_TARGET"] ?? "Man"
        var targetName = preferredTarget == "Goblin" ? "Goblin" : "Man"
        search.typeText(targetName)
        if targetName == "Man" && !app.buttons["game.nearby.name.Man"].firstMatch.waitForExistence(timeout: 10) {
            search.tap()
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "Goblin")
            targetName = "Goblin"
        }
        let target = reveal(app, "game.nearby.name." + targetName)
        target.tap()
        assertSinglePopup(app, "game.popup.options")
        let attack = elements(app, "game.popup.options").firstMatch.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "game.target.op.", "attack")).firstMatch
        XCTAssertTrue(attack.waitForExistence(timeout: 10), "The live nearby NPC offers its original Attack action")
        XCTAssertTrue(attack.isEnabled && attack.isHittable)
        attack.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.popup.options").firstMatch.exists }, "Selecting Attack dismisses its options")
        app.buttons["game.explore.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.popup.explore").firstMatch.exists })
        XCTAssertFalse(app.staticTexts["That target is no longer nearby."].firstMatch.exists, "The fresh target was not rejected as stale")
        XCTAssertTrue(waitUntil { volume.exists && (belt.value as? String) == "Collapsed" })
        XCTAssertFalse(elements(app, "game.panel.scroll").firstMatch.exists, "The game panel stays out of the combat view")
        XCTAssertFalse(elements(app, "game.tools").firstMatch.exists)
        XCTAssertFalse(elements(app, "table.controls.menu").firstMatch.exists)

        // This bounded playtest proves ordinary UI reachability. The opt-in
        // profile's receivedHits/drawnHits counters independently establish
        // actual combat feedback, while the capture verifies its appearance.
        let requestedPause = Double(environment["TABLESCAPE_COMBAT_CAPTURE_SECONDS"] ?? environment["TEST_RUNNER_TABLESCAPE_COMBAT_CAPTURE_SECONDS"] ?? "0") ?? 0
        let capturePause = min(45,max(0,requestedPause))
        print("TABLESCAPE_COMBAT_CAPTURE attack-issued user=\(qaUsername) target=\(targetName) pause=\(capturePause)")
        fflush(stdout)
        attachScreen("Volume after ordinary Attack action with menus closed")
        if capturePause > 0 { Thread.sleep(forTimeInterval: capturePause) }
        attachScreen("Volume after bounded combat observation")
        leaveTable(app)
        XCTAssertTrue(waitUntil { !volume.exists })
        logOut(app)
    }

    func testGameSettingsMenu() throws {
        let app = launchCharacter(unplaced: true)
        let openTable = app.buttons["table.window.open"].firstMatch
        XCTAssertTrue(openTable.waitForExistence(timeout: 10))
        openTable.tap()
        let volume = elements(app, "world.volume").firstMatch
        let belt = elements(app, "game.toolbelt").firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 30))
        XCTAssertTrue(waitUntil(25) { !app.buttons["table.immersive"].firstMatch.exists })
        awaitVolumeMeshes(app)
        awaitVolumeInput(app)
        utility(app, "game.tab.11").tap()
        let settings = elements(app, "game.settings").firstMatch
        let panel = elements(app, "game.panel.scroll").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings opens as a compact native panel")
        XCTAssertTrue(panel.exists)
        let run = elements(app, "game.settings.run").firstMatch
        let retaliate = elements(app, "game.settings.retaliate").firstMatch
        let classic = app.buttons["game.settings.classic"].firstMatch
        var mainControls: [XCUIElement] = [run,retaliate,classic]
        for kind in ["music","sound"] {
            XCTAssertTrue(elements(app, "game.settings.\(kind)").firstMatch.exists)
            for level in 0...4 { mainControls.append(app.buttons["game.settings.\(kind).\(level)"].firstMatch) }
        }
        for control in mainControls {
            XCTAssertTrue(control.exists && control.isEnabled && control.isHittable, "Settings control is usable without scrolling: " + control.identifier)
            XCTAssertTrue(panel.frame.insetBy(dx: -1, dy: -1).contains(control.frame), "Settings control fits the initial viewport: " + control.identifier)
        }
        XCTAssertEqual(settings.buttons.matching(NSPredicate(format: "label ==[c] %@", "Select")).count, 0, "Settings does not contain anonymous legacy Select buttons")
        XCTAssertFalse(settings.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Mouse Buttons")).firstMatch.exists, "Desktop-only preferences do not crowd the main panel")
        XCTAssertEqual(settings.sliders.count, 0, "Audio uses discrete original-server options instead of drag-generated requests")
        func selectAudio(_ kind: String, level: Int) {
            let choice = app.buttons["game.settings.\(kind).\(level)"].firstMatch
            XCTAssertTrue(choice.isHittable && choice.isEnabled)
            choice.tap()
            XCTAssertTrue(waitUntil { choice.isSelected }, "The server acknowledges \(kind) level \(level)")
            Thread.sleep(forTimeInterval: 1.4)
            XCTAssertTrue(choice.isSelected, "The audio choice survives subsequent server polls")
            XCTAssertEqual((0...4).filter { app.buttons["game.settings.\(kind).\($0)"].firstMatch.isSelected }, [level], "Exactly one audio level is selected")
        }
        selectAudio("music", level: 0)
        selectAudio("music", level: 2)
        selectAudio("sound", level: 1)
        selectAudio("sound", level: 2)
        if (run.value as? String) == "On" {
            run.tap()
            XCTAssertTrue(waitUntil { (run.value as? String) == "Off" })
        }
        XCTAssertEqual(run.value as? String, "Off")
        run.tap()
        XCTAssertTrue(waitUntil { (run.value as? String) == "On" }, "Run can be enabled from Settings")
        Thread.sleep(forTimeInterval: 1.4)
        XCTAssertEqual(run.value as? String, "On", "Run survives server polling")
        run.tap()
        XCTAssertTrue(waitUntil { (run.value as? String) == "Off" }, "Run can be restored to walking")
        let originalRetaliate = try XCTUnwrap(retaliate.value as? String)
        XCTAssertTrue(["On","Off"].contains(originalRetaliate))
        retaliate.tap()
        XCTAssertTrue(waitUntil { (retaliate.value as? String) == (originalRetaliate == "On" ? "Off" : "On") }, "Auto-retaliate uses the original server option")
        Thread.sleep(forTimeInterval: 1.4)
        XCTAssertNotEqual(retaliate.value as? String, originalRetaliate)
        retaliate.tap()
        XCTAssertTrue(waitUntil { (retaliate.value as? String) == originalRetaliate }, "Auto-retaliate restores the fresh character's original setting")

        classic.tap()
        assertSinglePopup(app, "game.settings.classic.menu")
        for identifier in [905,907,909,911,913,914,915,916,957,958] {
            let buttons = app.buttons.matching(identifier: "game.widget.\(identifier)")
            XCTAssertEqual(buttons.count, 1, "Each classic choice appears once")
            XCTAssertTrue(buttons.firstMatch.isEnabled && buttons.firstMatch.isHittable)
        }
        let bright = app.buttons["game.widget.909"].firstMatch
        bright.tap()
        XCTAssertTrue(waitUntil { bright.isSelected }, "Bright is acknowledged by the server")
        let normal = app.buttons["game.widget.907"].firstMatch
        normal.tap()
        XCTAssertTrue(waitUntil { normal.isSelected && !bright.isSelected }, "Normal restores brightness with one selected choice")
        app.buttons["game.settings.classic.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.settings.classic.menu").firstMatch.exists })
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        utility(app, "game.tab.11").tap()
        XCTAssertTrue(waitUntil { (belt.value as? String) == "Collapsed" && !settings.exists && !panel.exists }, "The active Settings tool collapses its panel")
        XCTAssertTrue(app.buttons["game.moreTabs"].firstMatch.isHittable)
        utility(app, "game.tab.11").tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Settings reopens from the persistent toolbar")
        for kind in ["music","sound"] {
            XCTAssertTrue(app.buttons["game.settings.\(kind).2"].firstMatch.isSelected, "The server's audio choice persists after reopening")
        }
        XCTAssertEqual(run.value as? String, "Off")
        XCTAssertEqual(retaliate.value as? String, originalRetaliate)
        utility(app, "game.tab.13").tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertFalse(settings.exists)
        XCTAssertEqual(panel.sliders.count, 0, "Music does not duplicate the removed native volume sliders")
        XCTAssertFalse(elements(app, "game.settings.music").firstMatch.exists)
        XCTAssertFalse(elements(app, "game.settings.sound").firstMatch.exists)
        utility(app, "game.tab.11").tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        attachScreen("Compact game settings after cleanup")
        let environment = ProcessInfo.processInfo.environment
        let requestedPause = Double(environment["TABLESCAPE_SETTINGS_CAPTURE_SECONDS"] ?? environment["TEST_RUNNER_TABLESCAPE_SETTINGS_CAPTURE_SECONDS"] ?? "0") ?? 0
        let capturePause = min(45,max(0,requestedPause))
        print("TABLESCAPE_SETTINGS_CAPTURE after pause=\(capturePause)")
        fflush(stdout)
        if capturePause > 0 { Thread.sleep(forTimeInterval: capturePause) }
        leaveTable(app)
        XCTAssertTrue(waitUntil { !volume.exists })
        logOut(app)
    }

    func testTableZoomAndQuarterTurns() throws {
        let app = launchCharacter(unplaced: true)
        let openTable = app.buttons["table.window.open"].firstMatch
        XCTAssertTrue(openTable.waitForExistence(timeout: 10))
        openTable.tap()
        let volume = elements(app, "world.volume").firstMatch
        let belt = elements(app, "game.toolbelt").firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 30))
        XCTAssertTrue(waitUntil(25) { !app.buttons["table.immersive"].firstMatch.exists })
        awaitVolumeMeshes(app)
        awaitVolumeInput(app)
        XCTAssertTrue(waitUntil { (belt.value as? String) == "Collapsed" })
        func sceneTiles() -> Int? {
            guard volume.exists, let value = volume.value as? String,
                  let range = value.range(of: "(?<=tiles=)[0-9]+", options: .regularExpression) else { return nil }
            return Int(value[range])
        }
        XCTAssertTrue(waitUntil { sceneTiles() != nil }, "The live volume exposes its live scene zoom state")
        let startingTiles = try XCTUnwrap(sceneTiles())
        XCTAssertGreaterThan(startingTiles, 16, "A fresh scene can zoom in")
        XCTAssertLessThan(startingTiles, 60, "A fresh scene can zoom out")
        func awaitSceneState(_ message: String, _ condition: @escaping () -> Bool) {
            let matched = waitUntil { volume.exists && condition() }
            if !matched {
                let visible = volume.exists
                let value = visible ? String((volume.value as? String ?? "<no value>").prefix(240)) : "<hidden>"
                print("TABLESCAPE_VIEW_STATE \(message) exists=\(visible) value=\(value)")
            }
            XCTAssertTrue(matched, message)
        }
        openTableControls(app)
        assertSinglePopup(app, "table.controls.menu")
        let zoom = app.sliders["table.zoom"].firstMatch
        XCTAssertTrue(zoom.exists && zoom.isEnabled && zoom.isHittable, "The shared table zoom slider is accessible")
        let originalSliderValue = try XCTUnwrap(zoom.value as? String)
        let zoomIn = app.buttons["table.zoom.in"].firstMatch
        let zoomOut = app.buttons["table.zoom.out"].firstMatch
        XCTAssertTrue(zoomIn.isEnabled && zoomIn.isHittable)
        zoomIn.tap()
        XCTAssertTrue(waitUntil { (zoom.value as? String) != originalSliderValue }, "The slider follows the same zoom state")
        // visionOS popovers hide the background volume from accessibility.
        // Read its scene state only after closing the actual public popover.
        closeTableControls(app)
        awaitSceneState("Zoom in updates the live scene tile span") { sceneTiles() == max(16,startingTiles-4) }
        openTableControls(app)
        XCTAssertTrue(zoomOut.isEnabled && zoomOut.isHittable)
        zoomOut.tap()
        XCTAssertTrue(waitUntil { (zoom.value as? String) == originalSliderValue }, "Zoom out restores the slider state")
        closeTableControls(app)
        awaitSceneState("Zoom out restores the original scene tile span") { sceneTiles() == startingTiles }
        let rotate = app.buttons["table.rotate"].firstMatch
        for degrees in [90,180,270,0] {
            openTableControls(app)
            XCTAssertTrue(rotate.exists && rotate.isHittable)
            if degrees == 90 { XCTAssertEqual(rotate.value as? String, "0°") }
            rotate.tap()
            XCTAssertTrue(waitUntil { (rotate.value as? String) == "\(degrees)°" }, "Rotate advances its accessible state to \(degrees) degrees")
            XCTAssertTrue(elements(app, "table.controls.menu").firstMatch.exists, "Rotation keeps table controls open")
            closeTableControls(app)
            awaitSceneState("The real scene snapshot rotates to \(degrees) degrees") {
                (volume.value as? String)?.contains("rotation=\(degrees)°") == true
            }
            XCTAssertEqual(sceneTiles(), startingTiles, "Rotating does not change game zoom")
            XCTAssertEqual(belt.value as? String, "Collapsed", "View controls do not expand a game panel")
        }
        XCTAssertFalse(elements(app, "game.panel.scroll").firstMatch.exists, "View controls do not open an unrelated game panel")
        attachScreen("Table zoom and four quarter turns")
        XCTAssertTrue(app.buttons["game.tab.3"].firstMatch.isHittable, "The collapsed toolbelt remains usable after closing view controls")
        XCTAssertEqual(belt.value as? String, "Collapsed")
        leaveTable(app)
        XCTAssertTrue(waitUntil { !volume.exists })
        logOut(app)
    }

    func testSeparateActionDialogueAndMapWindows() throws {
        let app = launchCharacter(immersive: true)
        awaitFloatingControls(app)
        XCTAssertFalse(app.textFields["game.nearby.search"].firstMatch.exists)
        XCTAssertFalse(elements(app, "game.messages").firstMatch.exists)
        utility(app, "game.explore.open").tap()
        assertSinglePopup(app, "game.popup.explore")
        let explore = elements(app, "game.popup.explore").firstMatch
        XCTAssertTrue(app.textFields["game.nearby.search"].firstMatch.exists, "Nearby search opens directly in Explore")
        explore.buttons["game.explore.messages"].tap()
        XCTAssertTrue(elements(app, "game.messages").firstMatch.waitForExistence(timeout: 10), "Retained messages have a dedicated Explore panel")
        let messageRows = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "game.message."))
        XCTAssertTrue(waitUntil { messageRows.count > 0 }, "The fresh character's actual server messages are readable")
        XCTAssertTrue(messageRows.allElementsBoundByIndex.contains { !$0.label.isEmpty && $0.isHittable })
        explore.buttons["game.explore.nearby"].tap()
        XCTAssertTrue(app.textFields["game.nearby.search"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["game.explore.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.popup.explore").firstMatch.exists })
        utility(app, "game.explore.open").tap()
        assertSinglePopup(app, "game.popup.explore")
        utility(app, "game.explore.open").tap()
        assertSinglePopup(app, "game.popup.explore")
        let search = app.textFields["game.nearby.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Hans")
        // The visionOS system keyboard is not always exposed under the app's
        // accessibility tree. Assert dismissal when this runtime exposes it.
        let keyboardWasExposed = app.keyboards.firstMatch.exists
        let hans = app.buttons["game.nearby.name.Hans"].firstMatch
        XCTAssertTrue(hans.waitForExistence(timeout: 15), "The real nearby Hans is searchable")
        hans.tap()
        assertSinglePopup(app, "game.popup.options")
        if keyboardWasExposed {
            XCTAssertTrue(waitUntil { !app.keyboards.firstMatch.exists }, "Choosing a target dismisses the search keyboard")
        }
        XCTAssertTrue(elements(app, "game.popup.options").firstMatch.staticTexts["Hans"].exists)
        XCTAssertFalse(elements(app, "game.dialogue").firstMatch.exists, "Selecting a target alone does not start a conversation")
        app.buttons["game.options.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.popup.options").firstMatch.exists }, "Options can close without sending an action")
        XCTAssertFalse(elements(app, "game.dialogue").firstMatch.exists)

        hans.tap()
        assertSinglePopup(app, "game.popup.options")
        let staleTarget = app.staticTexts["That target is no longer nearby."].firstMatch
        for attempt in 0..<3 {
            let talk = elements(app, "game.popup.options").firstMatch.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "game.target.op.", "talk")).firstMatch
            XCTAssertTrue(talk.waitForExistence(timeout: 10), "Hans advertises Talk-to")
            talk.tap()
            XCTAssertTrue(waitUntil(45) { self.elements(app, "game.dialogue").firstMatch.exists || staleTarget.exists },
                          "Talk-to opens dialogue or reports a definite local stale-target rejection")
            if elements(app, "game.dialogue").firstMatch.exists { break }
            // Hans moves in the live world. This exact notice means Core refused
            // to enqueue the stale action. Only a new, explicit selection permits
            // another attempt; uncertain, sent or timed-out actions never retry.
            XCTAssertTrue(staleTarget.exists)
            XCTAssertLessThan(attempt, 2, "Hans remained outside the nearby state after bounded fresh selections")
            XCTAssertTrue(hans.waitForExistence(timeout: 30), "The current nearby list advertises Hans again")
            hans.tap()
            assertSinglePopup(app, "game.popup.options")
        }
        XCTAssertTrue(elements(app, "game.dialogue").firstMatch.exists, "Ordinary server interaction opens a separate conversation")
        assertSinglePopup(app, "game.dialogue")
        app.buttons["game.explore.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.popup.explore").firstMatch.exists }, "Explore closes independently of a live conversation")
        let inventory = app.buttons["game.tab.3"].firstMatch
        XCTAssertTrue(inventory.exists && inventory.isHittable, "Inventory controls remain usable beside the conversation")
        inventory.tap()
        XCTAssertTrue(elements(app, "game.dialogue").firstMatch.exists, "Using inventory controls preserves the active conversation")
        attachScreen("Separate Hans conversation and inventory")
        print("TABLESCAPE_TOOLBELT_CAPTURE dialogue")
        Thread.sleep(forTimeInterval: 2)

        let before = dialogueSignature(app)
        let hide = app.buttons["game.dialogue.hide"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 10))
        hide.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.dialogue").firstMatch.exists }, "Hide dismisses only the local conversation window")
        Thread.sleep(forTimeInterval: 1.4)
        XCTAssertFalse(elements(app, "game.dialogue").firstMatch.exists, "Later server polls do not reopen a deliberately hidden conversation")
        utility(app, "game.popup.reopen.dialogue").tap()
        assertSinglePopup(app, "game.dialogue")
        XCTAssertEqual(dialogueSignature(app), before, "Reopening does not send Continue or change the conversation")
        let continueButton = elements(app, "game.dialogue").firstMatch.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "game.widget.", "continue")).firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10), "The current server dialogue offers Continue")
        continueButton.tap()
        XCTAssertTrue(waitUntil(15) { self.elements(app, "game.dialogue").firstMatch.exists && self.dialogueSignature(app) != before }, "Continue advances actual dialogue text or server widget controls")
        assertSinglePopup(app, "game.dialogue")
        utility(app, "game.popup.reopen.dialogue").tap()
        assertSinglePopup(app, "game.dialogue")
        app.buttons["game.dialogue.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.dialogue").firstMatch.exists }, "Closing the conversation dismisses its popup")
        openUtilities(app)
        XCTAssertTrue(waitUntil { !app.buttons["game.popup.reopen.dialogue"].firstMatch.exists }, "Closed server dialogue leaves no stale utility even when utilities are open")
        closeUtilities(app)
        XCTAssertTrue(inventory.exists)

        utility(app, "game.map.open").tap()
        assertSinglePopup(app, "game.popup.map")
        utility(app, "game.map.open").tap()
        assertSinglePopup(app, "game.popup.map")
        attachScreen("Separate native map window")
        app.buttons["game.map.close"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !self.elements(app, "game.popup.map").firstMatch.exists }, "Map can close independently")
        leaveTable(app)
        let enter = app.buttons["table.immersive"].firstMatch
        // Reenter as soon as the ordinary UI permits it. An old renderer teardown
        // callback must not close or stop this newly opened immersive session.
        enter.tap()
        awaitFloatingControls(app)
        XCTAssertTrue(app.buttons["game.tab.3"].firstMatch.exists)
        XCTAssertTrue(utility(app, "game.map.open").isHittable)
        leaveTable(app)
        logOut(app)
    }
}
