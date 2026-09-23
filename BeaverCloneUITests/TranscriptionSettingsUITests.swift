import XCTest

final class TranscriptionSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnDeviceOptionAppearsWhenSupported() {
        let app = XCUIApplication()
        app.launchArguments += ["-ForceOnDeviceTranscriptionAvailable", "-transcriptionMode", "cloud"]
        app.launch()

        app.buttons["Settings"].tap()
        let picker = app.segmentedControls["transcriptionMethodPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["Cloud"].exists)
        XCTAssertTrue(picker.buttons["On Device"].exists)

        picker.buttons["On Device"].tap()
        XCTAssertTrue(app.staticTexts["onDeviceDescription"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["onDeviceLanguagePicker"].exists || app.otherElements["onDeviceLanguagePicker"].exists)
        XCTAssertFalse(app.staticTexts["API Connection"].exists)
        XCTAssertFalse(app.textFields["Base URL"].exists)
    }

    func testUnavailableNoteCanBeHidden() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ForceOnDeviceTranscriptionUnavailable",
            "-hideOnDeviceUnavailableNotice", "NO",
            "-transcriptionMode", "cloud"
        ]
        app.launch()

        app.buttons["Settings"].tap()
        let note = app.staticTexts["onDeviceUnavailableNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["transcriptionMethodPicker"].exists)

        app.buttons["hideOnDeviceUnavailableNote"].tap()
        XCTAssertFalse(note.exists)
    }

    func testRecordingDoesNotStartWhenCloudValidationFails() {
        let app = XCUIApplication()
        app.launchArguments += ["-ForceCloudTranscriptionValidationFailure", "-transcriptionMode", "cloud"]
        app.launch()

        app.buttons["recordButton"].tap()

        XCTAssertTrue(app.alerts["Transcription isn't ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts["Transcription isn't ready"].buttons["Open Settings"].exists)
        XCTAssertFalse(app.staticTexts["Recording"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Transcription readiness failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
