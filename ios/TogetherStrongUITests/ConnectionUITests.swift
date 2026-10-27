import XCTest

nonisolated final class ConnectionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor
    func testSignInScreenAndValidation() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["password"].exists)
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.alerts["Enter your sign-in details"].exists)
    }

    @MainActor func testLiveSignInSyncRestoreAndSignOut() throws {
        guard let path = ProcessInfo.processInfo.environment["TS_LIVE_CONFIG"], path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Live backend is opt-in.") }
        struct Config: Decodable { let origin: String; let emails: [String]; let password: String }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let app = XCUIApplication()
        app.launchEnvironment["TS_TEST_API_ORIGIN"] = config.origin
        app.launch()
        XCTAssertTrue(app.textFields["email"].waitForExistence(timeout: 10))
        app.textFields["email"].tap(); app.textFields["email"].typeText(config.emails[1])
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText(config.password)
        app.buttons["signIn"].tap()
        XCTAssertTrue(app.staticTexts["workoutSummary"].waitForExistence(timeout: 15))
        let passwordPrompt = app.buttons["Not Now"]
        if passwordPrompt.waitForExistence(timeout: 3) { passwordPrompt.tap() }
        app.segmentedControls["rampSets"].buttons["1 set"].tap()
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
}
