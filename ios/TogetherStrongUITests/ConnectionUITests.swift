import XCTest

nonisolated final class ConnectionUITests: XCTestCase {
    private enum FixtureError: Error { case requiresSyntheticLoopback }
    private func safeFixture(origin: String, emails: [String]) -> Bool {
        guard let url = URL(string: origin), url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host ?? ""), emails.count == 2 else { return false }
        return emails.allSatisfy { $0.range(of: "^qa-(david|mary)-[a-f0-9]+@example\\.invalid$", options: .regularExpression) != nil }
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor
    func testSignInScreenAndValidation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TS_TEST_API_ORIGIN"] = "http://127.0.0.1:3191"
        if let path = ProcessInfo.processInfo.environment["TS_LIVE_CONFIG"], path.hasPrefix("/"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let origin = fields["origin"] as? String, let emails = fields["emails"] as? [String], safeFixture(origin: origin, emails: emails) {
            app.launchEnvironment["TS_TEST_API_ORIGIN"] = origin
        }
        app.launch()
        ensureSignedOut(app)
        XCTAssertTrue(app.secureTextFields["password"].exists)
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.alerts["Enter your sign-in details"].exists)
    }

    @MainActor func testLiveSignInSyncRestoreAndSignOut() throws {
        guard let path = ProcessInfo.processInfo.environment["TS_LIVE_CONFIG"], path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Live backend is opt-in.") }
        struct Config: Decodable { let origin: String; let emails: [String]; let password: String }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard safeFixture(origin: config.origin, emails: config.emails) else { throw FixtureError.requiresSyntheticLoopback }
        let app = XCUIApplication()
        app.launchEnvironment["TS_TEST_API_ORIGIN"] = config.origin
        app.launch()
        ensureSignedOut(app)
        app.textFields["email"].tap(); app.textFields["email"].typeText(config.emails[1])
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText(config.password)
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.staticTexts["workoutSummary"].waitForExistence(timeout: 15))
        let passwordPrompt = app.buttons["Not Now"]
        if passwordPrompt.waitForExistence(timeout: 3) { passwordPrompt.tap() }
        reveal(app.segmentedControls["rampSets"], in: app)
        app.segmentedControls["rampSets"].buttons["1 set"].tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: app.segmentedControls["rampSets"].buttons["1 set"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["workoutSummary"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.segmentedControls["rampSets"].buttons["1 set"].isSelected)
        XCTAssertTrue(app.buttons["sync"].isEnabled)
        app.buttons["sync"].tap()
        let synced = NSPredicate(format: "label == %@", "Synced securely")
        expectation(for: synced, evaluatedWith: app.staticTexts["syncState"])
        waitForExpectations(timeout: 15)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["workoutSummary"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.segmentedControls["rampSets"].buttons["1 set"].isSelected)
        app.buttons["signOut"].tap()
        app.alerts.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 15))
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 20), .completed)
        for _ in 0..<12 {
            if element.isHittable { return }
            if upwards { app.scrollViews.firstMatch.swipeUp() } else { app.scrollViews.firstMatch.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func ensureSignedOut(_ app: XCUIApplication) {
        if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
        var safe = false
        if let path = ProcessInfo.processInfo.environment["TS_LIVE_CONFIG"], path.hasPrefix("/"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let origin = fields["origin"] as? String, let emails = fields["emails"] as? [String] {
            safe = safeFixture(origin: origin, emails: emails)
        }
        if safe,
           app.staticTexts["workoutSummary"].waitForExistence(timeout: 3) {
            reveal(app.buttons["signOut"], in: app); app.buttons["signOut"].tap()
            let discard = app.alerts.buttons["Discard changes and sign out"]
            if discard.exists { discard.tap() } else { app.alerts.buttons["Sign out"].tap() }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: app.textFields["email"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    }

    @MainActor func testLiveHistoryCalendarAndProgress() throws {
        guard let path = ProcessInfo.processInfo.environment["TS_LIVE_CONFIG"], path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Live backend is opt-in.") }
        struct Config: Decodable { let origin: String; let emails: [String]; let password: String }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard safeFixture(origin: config.origin, emails: config.emails) else { throw FixtureError.requiresSyntheticLoopback }
        let app = XCUIApplication(); app.launchEnvironment["TS_TEST_API_ORIGIN"] = config.origin; app.launch()
        ensureSignedOut(app)
        app.textFields["email"].tap(); app.textFields["email"].typeText(config.emails[0])
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText(config.password)
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.buttons["savedSessions"].waitForExistence(timeout: 15))
        if app.buttons["Not Now"].waitForExistence(timeout: 3) { app.buttons["Not Now"].tap() }
        reveal(app.buttons["savedSessions"], in: app); app.buttons["savedSessions"].tap()
        XCTAssertTrue(app.segmentedControls["historyFilter"].waitForExistence(timeout: 10))
        app.segmentedControls["historyFilter"].buttons["Completed"].tap()
        XCTAssertTrue(app.staticTexts["historyDay"].label.contains("21 sessions"))
        app.segmentedControls["historyFilter"].buttons["Unfinished"].tap()
        XCTAssertTrue(app.staticTexts["historyDay"].label.contains("3 sessions"))
        app.segmentedControls["historyFilter"].buttons["All"].tap()
        app.buttons["historyToday"].tap()
        XCTAssertFalse(app.staticTexts["historyDay"].label.contains("All dates"))
        app.buttons["historyLatest"].tap()
        XCTAssertTrue(app.staticTexts["historyDay"].label.contains("1 session"))
        let calendarShot = XCTAttachment(screenshot: app.screenshot()); calendarShot.name = "Workout calendar on iPhone"; calendarShot.lifetime = .keepAlways; add(calendarShot)
        app.buttons["historyAllDates"].tap()
        XCTAssertTrue(app.staticTexts["historyDay"].label.contains("24 sessions"))
        app.tables.cells["session-draft"].tap()
        XCTAssertTrue(app.staticTexts["sessionProgress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["sessionProgress"].label.contains("2026-10-28"))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["openProgress"], in: app); app.buttons["openProgress"].tap()
        XCTAssertTrue(app.staticTexts["progressSummary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["progressSummary"].label.contains("21 workouts completed"))
        XCTAssertTrue(app.staticTexts["progressSummary"].label.contains("78 completed sets"))
        let progressShot = XCTAttachment(screenshot: app.screenshot()); progressShot.name = "Workout progress on iPhone"; progressShot.lifetime = .keepAlways; add(progressShot)
        reveal(app.buttons["exerciseChart-completed-18"], in: app); app.buttons["exerciseChart-completed-18"].tap()
        XCTAssertTrue(app.buttons["exerciseChart-completed-18"].isSelected)
        XCTAssertTrue(app.staticTexts["exerciseRecordDetail"].label.contains("12 reps"))
        let chartShot = XCTAttachment(screenshot: app.screenshot()); chartShot.name = "Exercise progress chart on iPhone"; chartShot.lifetime = .keepAlways; add(chartShot)
        reveal(app.buttons["progressExercise"], in: app, upwards: false); app.buttons["progressExercise"].tap()
        app.buttons["Bodyweight heel slides"].tap()
        reveal(app.staticTexts["exerciseRecordDetail"], in: app)
        XCTAssertTrue(app.staticTexts["exerciseRecordDetail"].label.contains("reps per side"))
        reveal(app.buttons["progressOpenWorkout"], in: app); app.buttons["progressOpenWorkout"].tap()
        XCTAssertTrue(app.staticTexts["sessionProgress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["sessionProgress"].label.contains("Complete"))
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["progressExercise"], in: app, upwards: false); app.buttons["progressExercise"].tap(); app.buttons["Dumbbell curls"].tap()
        XCTAssertTrue(app.staticTexts["progressEmpty"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["openProgress"].waitForExistence(timeout: 15)); reveal(app.buttons["openProgress"], in: app); app.buttons["openProgress"].tap()
        XCTAssertTrue(app.staticTexts["progressSummary"].waitForExistence(timeout: 10)); XCTAssertTrue(app.staticTexts["progressSummary"].label.contains("21 workouts completed"))
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["signOut"], in: app); app.buttons["signOut"].tap()
        let discard = app.alerts.buttons["Discard changes and sign out"]
        if discard.exists { discard.tap() } else { app.alerts.buttons["Sign out"].tap() }
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 15))
        app.textFields["email"].tap(); app.textFields["email"].typeText(config.emails[1])
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText(config.password)
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.buttons["openProgress"].waitForExistence(timeout: 15))
        if app.buttons["Not Now"].waitForExistence(timeout: 3) { app.buttons["Not Now"].tap() }
        reveal(app.buttons["openProgress"], in: app); app.buttons["openProgress"].tap()
        XCTAssertTrue(app.staticTexts["progressSummary"].waitForExistence(timeout: 10)); XCTAssertTrue(app.staticTexts["progressSummary"].label.contains("0 workouts completed"))
        XCTAssertTrue(app.staticTexts["progressEmpty"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["signOut"], in: app); app.buttons["signOut"].tap(); app.alerts.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 15))
    }

    @MainActor func testLiveTimerAndGuides() throws {
        guard let path = ProcessInfo.processInfo.environment["TS_LIVE_CONFIG"], path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Live backend is opt-in.") }
        struct Config: Decodable { let origin: String; let emails: [String]; let password: String }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard safeFixture(origin: config.origin, emails: config.emails) else { throw FixtureError.requiresSyntheticLoopback }
        let app = XCUIApplication(); app.launchEnvironment["TS_TEST_API_ORIGIN"] = config.origin; app.launch()
        ensureSignedOut(app)
        app.textFields["email"].tap(); app.textFields["email"].typeText(config.emails[0])
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText(config.password)
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.buttons["openWorkout"].waitForExistence(timeout: 15))
        if app.buttons["Not Now"].waitForExistence(timeout: 3) { app.buttons["Not Now"].tap() }
        reveal(app.buttons["openWorkout"], in: app, upwards: false); app.buttons["openWorkout"].tap()
        reveal(app.buttons["rest-press"], in: app); app.buttons["rest-press"].tap()
        XCTAssertTrue(app.buttons["timerToggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["timerToggle"].label, "Pause")
        app.buttons["timerToggle"].tap()
        XCTAssertEqual(app.staticTexts["timerState"].label, "Rest paused")
        app.buttons["timerAdd30"].tap(); app.buttons["timerReset"].tap()
        XCTAssertEqual(app.staticTexts["timerValue"].label, "2:00")
        app.segmentedControls["timerPresets"].buttons["60s"].tap()
        XCTAssertEqual(app.staticTexts["timerValue"].label, "1:00")
        app.buttons["timerToggle"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(app.buttons["timerToggle"].label, "Pause")
        app.buttons["timerToggle"].tap(); app.buttons["timerReset"].tap()
        XCTAssertEqual(app.staticTexts["timerState"].label, "Rest paused")
        XCTAssertEqual(app.staticTexts["timerValue"].label, "1:00")
        let timerShot = XCTAttachment(screenshot: app.screenshot()); timerShot.name = "Rest timer on iPhone"; timerShot.lifetime = .keepAlways; add(timerShot)
        app.buttons["timerToggle"].tap()
        app.buttons["closeRestTimer"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["openWorkout"].waitForExistence(timeout: 15)); app.buttons["openWorkout"].tap()
        app.buttons["openRestTimer"].tap()
        XCTAssertTrue(app.buttons["timerToggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["timerToggle"].label, "Pause")
        XCTAssertNotEqual(app.staticTexts["timerValue"].label, "1:00")
        app.buttons["endRest"].tap()
        reveal(app.buttons["guide-press"], in: app, upwards: false); app.buttons["guide-press"].tap()
        XCTAssertTrue(app.sliders["guidePosition"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders["guidePosition"].value as? String, "0 percent")
        reveal(app.buttons["pose-middle"], in: app); app.buttons["pose-middle"].tap()
        XCTAssertEqual(app.sliders["guidePosition"].value as? String, "50 percent")
        let guideShot = XCTAttachment(screenshot: app.screenshot()); guideShot.name = "Exercise guide on iPhone"; guideShot.lifetime = .keepAlways; add(guideShot)
        app.buttons["pose-finish"].tap(); XCTAssertEqual(app.sliders["guidePosition"].value as? String, "100 percent")
        app.buttons["pose-start"].tap(); XCTAssertEqual(app.sliders["guidePosition"].value as? String, "0 percent")
        reveal(app.buttons["guidePlay"], in: app); app.buttons["guidePlay"].tap()
        XCTAssertTrue(app.buttons["guidePlay"].isSelected)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "0 percent"), object: app.sliders["guidePosition"])
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.buttons["guidePlay"].isSelected)
        let paused = app.sliders["guidePosition"].value as? String
        app.segmentedControls["guideSpeed"].buttons["Normal"].tap()
        XCTAssertEqual(app.sliders["guidePosition"].value as? String, paused)
        reveal(app.buttons["guideReset"], in: app); app.buttons["guideReset"].tap()
        XCTAssertEqual(app.sliders["guidePosition"].value as? String, "0 percent")
        app.buttons["closeGuide"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["signOut"], in: app); app.buttons["signOut"].tap()
        let discard = app.alerts.buttons["Discard changes and sign out"]
        if discard.exists { discard.tap() } else { app.alerts.buttons["Sign out"].tap() }
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 15))
    }

    @MainActor func testLiveWorkoutLoggingAndRecovery() throws {
        guard let path = ProcessInfo.processInfo.environment["TS_LIVE_CONFIG"], path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Live backend is opt-in.") }
        struct Config: Decodable { let origin: String; let emails: [String]; let password: String }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard safeFixture(origin: config.origin, emails: config.emails) else { throw FixtureError.requiresSyntheticLoopback }
        let app = XCUIApplication(); app.launchEnvironment["TS_TEST_API_ORIGIN"] = config.origin; app.launch()
        ensureSignedOut(app)
        app.textFields["email"].tap(); app.textFields["email"].typeText(config.emails[1])
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText(config.password)
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.buttons["openWorkout"].waitForExistence(timeout: 15))
        if app.buttons["Not Now"].waitForExistence(timeout: 3) { app.buttons["Not Now"].tap() }
        reveal(app.buttons["openWorkout"], in: app, upwards: false); app.buttons["openWorkout"].tap()
        XCTAssertTrue(app.buttons["warmup-skipped"].waitForExistence(timeout: 10)); app.buttons["warmup-skipped"].tap()
        XCTAssertFalse(app.buttons["finishWorkout"].isEnabled)
        reveal(app.textFields["reps-row-0"], in: app)
        app.textFields["reps-row-0"].tap(); app.textFields["reps-row-0"].typeText("7")
        app.toolbars.buttons["Done"].tap()
        reveal(app.buttons["discardDraft"], in: app); app.buttons["discardDraft"].tap()
        app.alerts.buttons["Discard draft"].tap()
        XCTAssertTrue(app.buttons["savedSessions"].waitForExistence(timeout: 10))
        reveal(app.buttons["savedSessions"], in: app); app.buttons["savedSessions"].tap()
        let saved = app.tables.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        app.alerts.buttons["Restore draft"].tap(); saved.tap()
        XCTAssertTrue(app.textFields["reps-row-0"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["reps-row-0"].value as? String, "7")
        reveal(app.buttons["complete-row-0"], in: app); app.buttons["complete-row-0"].tap()
        XCTAssertTrue(app.alerts["Check this set"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        reveal(app.textFields["reps-row-0"], in: app, upwards: false)
        app.textFields["reps-row-0"].tap()
        app.textFields["reps-row-0"].typeText(XCUIKeyboardKey.delete.rawValue + "10")
        app.toolbars.buttons["Next"].tap(); app.textFields["kg-row-0"].typeText("5")
        app.toolbars.buttons["Done"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["openWorkout"].waitForExistence(timeout: 15))
        app.buttons["openWorkout"].tap()
        XCTAssertTrue(app.textFields["reps-row-0"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["reps-row-0"].value as? String, "10")
        XCTAssertEqual(app.textFields["kg-row-0"].value as? String, "5")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Workout logging restored on iPhone"
        screenshot.lifetime = .keepAlways; add(screenshot)
        reveal(app.buttons["complete-row-0"], in: app)
        app.buttons["complete-row-0"].tap(); XCTAssertTrue(app.buttons["complete-row-0"].isSelected)
        app.buttons["complete-row-0"].tap(); XCTAssertFalse(app.buttons["complete-row-0"].isSelected)
        app.buttons["complete-row-0"].tap()
        reveal(app.buttons["saveProgress"], in: app); app.buttons["saveProgress"].tap()
        let synced = NSPredicate(format: "label BEGINSWITH %@", "Synced securely")
        expectation(for: synced, evaluatedWith: app.staticTexts["workoutSaveStatus"]); waitForExpectations(timeout: 20)
        app.buttons["pauseWorkout"].tap()
        XCTAssertTrue(app.buttons["openWorkout"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["workoutSummary"].label.contains("0 workouts completed"))
        reveal(app.buttons["openWorkout"], in: app, upwards: false); app.buttons["openWorkout"].tap()
        reveal(app.buttons["finishWorkout"], in: app); app.buttons["finishWorkout"].tap()
        app.alerts.buttons["Finish and save"].tap()
        XCTAssertTrue(app.staticTexts["sessionProgress"].label.contains("Complete"))
        XCTAssertFalse(app.textFields["reps-row-0"].isEnabled)
        reveal(app.buttons["reopenWorkout"], in: app); app.buttons["reopenWorkout"].tap()
        reveal(app.buttons["finishWorkout"], in: app); app.buttons["finishWorkout"].tap(); app.alerts.buttons["Finish and save"].tap()
        expectation(for: synced, evaluatedWith: app.staticTexts["workoutSaveStatus"]); waitForExpectations(timeout: 20)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["workoutSummary"].label.contains("1 workouts completed"))
        reveal(app.buttons["signOut"], in: app); app.buttons["signOut"].tap(); app.alerts.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 15))
    }
}
