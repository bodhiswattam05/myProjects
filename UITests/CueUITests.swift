import XCTest

/// Create a script → open the prompter → play/pause → record a take (simulated camera).
final class CueUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateScriptPromptAndRecord() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        // iPhone opens on the script list; iPad shows it next to the sidebar.
        let newScript = app.buttons["library.newScript"]
        XCTAssertTrue(newScript.waitForExistence(timeout: 10))
        newScript.tap()

        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("UI test script")

        let body = app.textViews["editor.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Hello from the UI test. [pause] This is the second sentence.")
        XCTAssertTrue(app.staticTexts["editor.readTime"].exists)

        // Prompter: play, then pause.
        app.buttons["editor.openPrompter"].tap()
        let playPause = app.buttons["prompter.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))
        playPause.tap()
        // Countdown, then running; the controls stay reachable by tapping the stage.
        sleep(4)
        app.tap()
        XCTAssertTrue(playPause.waitForExistence(timeout: 3))
        playPause.tap()
        app.buttons["prompter.close"].tap()

        // Recorder with the simulated camera.
        let record = app.buttons["editor.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        let recordButton = app.buttons["recorder.record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10))
        recordButton.tap()
        sleep(2)
        if !recordButton.isHittable { app.tap() }
        recordButton.tap()

        let done = app.buttons["takeSummary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        XCTAssertTrue(app.otherElements["coachCard"].exists || app.staticTexts["Delivery"].exists)
        done.tap()
    }
}
