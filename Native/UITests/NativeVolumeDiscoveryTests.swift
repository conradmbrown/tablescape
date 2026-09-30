import XCTest

/// Opt-in inspection, not a gameplay-picking or system-resize acceptance test.
/// Run with TEST_RUNNER_TABLESCAPE_VOLUME_DISCOVERY=1 and
/// -only-testing:TableScapeUITests/NativeVolumeDiscoveryTests/testVolumeSystemControlDiscovery.
/// All output stays in XCTest's result bundle/log; no credentials are inspected.
final class NativeVolumeDiscoveryTests: XCTestCase {
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["TABLESCAPE_VOLUME_DISCOVERY"] == "1" || environment["TEST_RUNNER_TABLESCAPE_VOLUME_DISCOVERY"] == "1",
                          "Opt-in system-control discovery; this is not a regular acceptance test.")
    }

    override func tearDownWithError() throws {
        guard let app, app.state != .notRunning else { return }
        // Best-effort cleanup is limited to this test's newly created character.
        if !app.buttons["Disconnect"].firstMatch.exists {
            let closeTools = app.buttons["game.tools.close"].firstMatch
            if closeTools.exists && closeTools.isHittable { closeTools.tap() }
            let leave = app.buttons["table.leave"].firstMatch
            if !leave.exists {
                let controls = app.buttons["table.controls"].firstMatch
                if controls.exists && controls.isHittable { controls.tap() }
            }
            if leave.waitForExistence(timeout: 3) && leave.isHittable { leave.tap() }
        }
        let disconnect = app.buttons["Disconnect"].firstMatch
        if disconnect.waitForExistence(timeout: 5) && disconnect.isHittable {
            disconnect.tap()
            _ = app.buttons["game.connect"].firstMatch.waitForExistence(timeout: 5)
            Thread.sleep(forTimeInterval: 1)
        }
        app.terminate()
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Preserve hierarchy/frames/identifiers while excluding arbitrary text and
    /// every field value. Only known system-control labels remain readable.
    private func compactTree(_ application: XCUIApplication, name: String) -> String {
        let allowedLabels = "(?i)^(?:table(?:scape)?(?: controls)?|controls|game menu|more tools|leave table|open table window|close|close window|move|move window|resize|resize window|window controls|adjust|adjust window|volume|baseplate|home|recenter|environments?|minimize|maximize|expand|collapse|window|drag|grabber|scale|tilt|rotate)(?:[ .,:-].*)?$"
        let labels = try! NSRegularExpression(pattern: "label: '([^']*)'")
        let values = try! NSRegularExpression(pattern: "(?:value|placeholderValue): '(?:[^']*)'")
        let structure = try! NSRegularExpression(pattern: "(?:Application|Window|Button|Slider|Switch|ScrollView|Handle)[, (]|world\\.volume|table\\.volume|SFBSystemService")
        var output = ["TABLESCAPE_VOLUME_AX_BEGIN \(name)"]
        for raw in application.debugDescription.split(separator: "\n") {
            var line = String(raw)
            let full = NSRange(line.startIndex..<line.endIndex, in: line)
            guard structure.firstMatch(in: line, range: full) != nil else { continue }
            for match in labels.matches(in: line, range: full).reversed() {
                guard let whole = Range(match.range, in: line), let content = Range(match.range(at: 1), in: line) else { continue }
                let label = String(line[content])
                if label.range(of: allowedLabels, options: .regularExpression) == nil {
                    line.replaceSubrange(whole, with: "label: '<omitted>'")
                }
            }
            line = values.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line), withTemplate: "value: '<omitted>'")
            output.append(String(line.prefix(350)))
            if output.count >= 121 { output.append("[structure truncated after 120 lines]"); break }
        }
        output.append("TABLESCAPE_VOLUME_AX_END \(name)")
        return output.joined(separator: "\n")
    }

    /// Public-input discovery only. A missing popup is never counted as a pick.
    /// Use the framework's hittable point first, then at most three total taps.
    private func probeVolumeInput(_ application: XCUIApplication, volume: XCUIElement) {
        let popups = application.descendants(matching: .any).matching(identifier: "game.popup.options")
        guard volume.exists && !volume.frame.isEmpty else {
            print("TABLESCAPE_VOLUME_PICK_PROBE skipped-volume-unavailable")
            return
        }
        guard !popups.firstMatch.exists else {
            print("TABLESCAPE_VOLUME_PICK_PROBE skipped-existing-options-window")
            return
        }
        // Normal element.tap() asks XCTest to compute a hittable point; nil is
        // deliberately different from guessing the center of the AX frame.
        let candidates: [CGVector?] = volume.isHittable
            ? [nil, CGVector(dx: 0.5, dy: 0.7), CGVector(dx: 0.3, dy: 0.6)]
            : [CGVector(dx: 0.5, dy: 0.5), CGVector(dx: 0.5, dy: 0.7), CGVector(dx: 0.3, dy: 0.6)]
        let appFrame = application.frame
        print("TABLESCAPE_VOLUME_PICK_FRAME app x=\(appFrame.minX) y=\(appFrame.minY) width=\(appFrame.width) height=\(appFrame.height)")
        for (index, window) in application.windows.allElementsBoundByIndex.prefix(8).enumerated() {
            let frame = window.frame
            print("TABLESCAPE_VOLUME_PICK_FRAME window=\(index) x=\(frame.minX) y=\(frame.minY) width=\(frame.width) height=\(frame.height)")
        }
        for (index, position) in candidates.enumerated() {
            guard volume.exists && !volume.frame.isEmpty else {
                print("TABLESCAPE_VOLUME_PICK_PROBE stopped-volume-unavailable attempt=\(index + 1)")
                break
            }
            let frame = volume.frame
            print("TABLESCAPE_VOLUME_PICK_FRAME attempt=\(index + 1) x=\(frame.minX) y=\(frame.minY) width=\(frame.width) height=\(frame.height) containerHittable=\(volume.isHittable)")
            if let position {
                let coordinate = volume.coordinate(withNormalizedOffset: position)
                let screenPoint = coordinate.screenPoint
                print("TABLESCAPE_VOLUME_PICK_PROBE tapping attempt=\(index + 1) method=normalized-coordinate normalizedX=\(position.dx) normalizedY=\(position.dy) screenX=\(screenPoint.x) screenY=\(screenPoint.y)")
                coordinate.tap()
            } else {
                guard volume.isHittable else {
                    print("TABLESCAPE_VOLUME_PICK_PROBE stopped-element-no-longer-hittable attempt=\(index + 1)")
                    break
                }
                print("TABLESCAPE_VOLUME_PICK_PROBE tapping attempt=\(index + 1) method=element-tap framework-computed-hittable-point")
                volume.tap()
            }
            _ = waitUntil(4) { popups.firstMatch.exists }
            if volume.exists { print("TABLESCAPE_VOLUME_PICK_INPUT_STATUS attempt=\(index + 1) value=\(volume.value as? String ?? "")") }
            let popup = popups.firstMatch
            if popup.exists {
                let title = popup.staticTexts.allElementsBoundByIndex.first?.label ?? ""
                let operations = popup.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "game.target.op.")).allElementsBoundByIndex.map { $0.label }
                let summary: [String: Any] = ["attempt": index + 1, "popupCount": popups.count, "title": title, "operations": operations]
                if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) {
                    print("TABLESCAPE_VOLUME_PICK_PROBE observed-options \(json)")
                }
                print("TABLESCAPE_VOLUME_PICK_CAPTURE attempt=\(index + 1)")
                Thread.sleep(forTimeInterval: 5)
                let close = application.buttons["game.options.close"].firstMatch
                if close.exists && close.isHittable { close.tap() }
                break
            }
            // The connected UI hides Queued notices, and the volume has no
            // player-coordinate label. Do not pretend absence of either proves
            // the ground was untouched. Existing app logs record acknowledged
            // move actions and periodic authoritative positions separately.
            print("TABLESCAPE_VOLUME_PICK_PROBE no-options attempt=\(index + 1); movement-not-exposed-in-AX; input-outcome-unconfirmed")
        }
        print("TABLESCAPE_VOLUME_PICK_PROBE_SCOPE discovery-only; max-three-taps; no-calibrated-ray-picking-or-movement-acceptance-assertion")
    }

    private func inspectHomeEnvironments(_ system: XCUIApplication) {
        // Native XCTest input, after our game character has been logged out.
        // This inspects Home's controls; it never activates or downloads an environment.
        XCUIDevice.shared.press(.home)
        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@ OR identifier CONTAINS[c] %@", "Environments", "environment")
        let candidates = system.descendants(matching: .any).matching(predicate)
        _ = waitUntil(8) { candidates.count > 0 }
        let home = compactTree(system, name: "SurfBoard-Home-after-native-home")
        let homeAttachment = XCTAttachment(string: home)
        homeAttachment.name = "Home system controls after native Home press (sanitized)"
        homeAttachment.lifetime = .keepAlways
        add(homeAttachment)
        print(home)
        for (index, candidate) in candidates.allElementsBoundByIndex.prefix(12).enumerated() {
            let frame = candidate.frame
            print("TABLESCAPE_ENVIRONMENTS_AX index=\(index) role=\(candidate.elementType.rawValue) enabled=\(candidate.isEnabled) hittable=\(candidate.isHittable) selected=\(candidate.isSelected) x=\(frame.minX) y=\(frame.minY) width=\(frame.width) height=\(frame.height)")
        }
        let buttons = system.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Environments")).allElementsBoundByIndex
        print("TABLESCAPE_ENVIRONMENTS_DISCOVERY_CAPTURE phase=home candidates=\(candidates.count) buttons=\(buttons.count)")
        Thread.sleep(forTimeInterval: 5)
        guard let tab = buttons.first(where: { $0.exists && $0.isEnabled && $0.isHittable }) else {
            // Missing, covered, and disabled are distinct observations. Never infer
            // a disabled Environments feature from a failed coordinate click.
            if buttons.isEmpty { print("TABLESCAPE_ENVIRONMENTS_RESULT environments-button-not-exposed") }
            else if buttons.contains(where: \.isEnabled) { print("TABLESCAPE_ENVIRONMENTS_RESULT button-enabled-but-not-hittable") }
            else { print("TABLESCAPE_ENVIRONMENTS_RESULT observed-buttons-disabled") }
            return
        }
        tab.tap()
        let after = compactTree(system, name: "SurfBoard-after-Environments-tab-tap")
        let chooserAttachment = XCTAttachment(string: after)
        chooserAttachment.name = "System controls after native Environments tab tap (sanitized)"
        chooserAttachment.lifetime = .keepAlways
        add(chooserAttachment)
        print(after)
        print("TABLESCAPE_ENVIRONMENTS_RESULT native-tab-tap-returned selected=\(tab.exists && tab.isSelected)")
        print("TABLESCAPE_ENVIRONMENTS_DISCOVERY_CAPTURE phase=after-tab-tap")
        print("TABLESCAPE_ENVIRONMENTS_DISCOVERY_SCOPE chooser-inspection-only; no environment activation, download, or coexistence acceptance")
        Thread.sleep(forTimeInterval: 5)
    }

    func testVolumeSystemControlDiscovery() throws {
        let application = XCUIApplication()
        let username = "unityv" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
        application.launchArguments = ["--tablescape-connect", "--tablescape-volume", "--tablescape-unplaced", "--tablescape-profile", "--tablescape-user=" + username]
        app = application
        application.launch()
        let belt = application.descendants(matching: .any).matching(identifier: "game.toolbelt").firstMatch
        XCTAssertTrue(belt.waitForExistence(timeout: 35), "The volume exposes its permanent toolbelt")
        XCTAssertTrue(application.buttons["game.tab.3"].firstMatch.waitForExistence(timeout: 35), "The fresh QA character connects with inventory immediately reachable")
        XCTAssertTrue(waitUntil(15) {
            (belt.value as? String) == "Collapsed" && !application.descendants(matching: .any).matching(identifier: "game.panel.scroll").firstMatch.exists
        }, "Only the permanent toolbelt remains before map input discovery")
        let tableControls = application.buttons["table.controls"].firstMatch
        XCTAssertTrue(tableControls.isHittable, "Table controls are reachable without opening a game panel")
        let volume = application.descendants(matching: .any).matching(identifier: "world.volume").firstMatch
        XCTAssertTrue(volume.waitForExistence(timeout: 30))
        XCTAssertTrue(waitUntil(15) { !application.buttons["table.immersive"].firstMatch.exists }, "Inspect only the connected volume, with setup fields closed")
        XCTAssertTrue(waitUntil(45) {
            guard volume.exists, let reading = volume.value as? String else { return false }
            return reading.range(of: "\\b[1-9][0-9,]* meshes · [1-9][0-9,]* triangles\\b", options: .regularExpression) != nil
        }, "The real volume must contain uploaded geometry before inspecting system controls")
        XCTAssertTrue(waitUntil(45) {
            guard volume.exists, let reading = volume.value as? String else { return false }
            return reading.contains("Map ready")
        }, "Real map collision surfaces are enabled before input discovery")

        let system = XCUIApplication(bundleIdentifier: "com.apple.SurfBoard")
        let report = [compactTree(application, name: "app"), compactTree(system, name: "SurfBoard")].joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = "Sanitized volume and system control hierarchy (discovery only)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(report)
        let frame = volume.frame
        print("TABLESCAPE_VOLUME_DISCOVERY_CAPTURE x=\(frame.minX) y=\(frame.minY) width=\(frame.width) height=\(frame.height)")
        print("TABLESCAPE_VOLUME_DISCOVERY_SCOPE hierarchy-and-capture followed by bounded public-input discovery; no calibrated picking or resizing acceptance")
        Thread.sleep(forTimeInterval: 5)
        probeVolumeInput(application, volume: volume)

        XCTAssertTrue(tableControls.waitForExistence(timeout: 10) && tableControls.isHittable)
        tableControls.tap()
        XCTAssertTrue(application.descendants(matching: .any).matching(identifier: "table.controls.menu").firstMatch.waitForExistence(timeout: 10))
        let leave = application.buttons["table.leave"].firstMatch
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        leave.tap()
        let disconnect = application.buttons["Disconnect"].firstMatch
        XCTAssertTrue(disconnect.waitForExistence(timeout: 10))
        disconnect.tap()
        XCTAssertTrue(application.buttons["game.connect"].firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        application.terminate()
        inspectHomeEnvironments(system)
    }
}
