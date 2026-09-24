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

    func testOnDeviceRecordingShowsLiveTimerWithoutCloudConfiguration() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ForceOnDeviceTranscriptionAvailable",
            "-ForceOnDeviceTranscriptionReady",
            "-transcriptionMode", "onDevice"
        ]
        app.launch()

        addUIInterruptionMonitor(withDescription: "Microphone permission") { alert in
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }

        app.buttons["recordButton"].tap()
        // Trigger delivery of the permission interruption monitor if this is the first launch.
        app.tap()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        let elapsedTime = app.staticTexts["recordingElapsedTime"]
        XCTAssertTrue(elapsedTime.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["onDeviceLiveTranscript"].exists)
        let timeAdvanced = NSPredicate(format: "label != %@", "00:00")
        expectation(for: timeAdvanced, evaluatedWith: elapsedTime)
        waitForExpectations(timeout: 5)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "On-device recording live timer"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Cancel"].tap()
    }

    func testOnDeviceSelectionExplainsMissingSpeechPermissionImmediately() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ForceOnDeviceTranscriptionAvailable",
            "-ForceOnDeviceTranscriptionPermissionDenied",
            "-transcriptionMode", "cloud"
        ]
        app.launch()

        app.buttons["Settings"].tap()
        let picker = app.segmentedControls["transcriptionMethodPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["On Device"].tap()

        XCTAssertTrue(app.staticTexts["onDeviceReadinessError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Base URL"].exists)
    }
}
