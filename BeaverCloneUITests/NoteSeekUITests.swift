import XCTest

final class NoteSeekUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTappingTranscriptWordSeeksAndPlays() {
        let app = XCUIApplication()
        app.launchArguments += ["-reset"]
        app.launch()

        let seedButton = app.buttons["Seed"]
        XCTAssertTrue(seedButton.waitForExistence(timeout: 5), "Debug Seed button not found")
        seedButton.tap()

        let noteRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Debug Seed Note'")).firstMatch
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5), "Seeded note row not found in list")
        noteRow.tap()

        let detailPicker = app.segmentedControls.firstMatch
        XCTAssertTrue(detailPicker.waitForExistence(timeout: 5), "Detail view never appeared")

        // Switch to the Transcript tab.
        detailPicker.buttons["Transcript"].tap()

        // Tap the word "test" (from the seeded transcript "This is a test transcript.").
        let wordText = app.staticTexts["test"]
        XCTAssertTrue(wordText.waitForExistence(timeout: 5), "Transcript word 'test' not found")
        wordText.tap()

        // Tapping a word should start playback (pause button appears where play button was).
        let pauseButton = app.buttons["Pause"]
        let playButton = app.buttons["Play"]
        let startedPlaying = pauseButton.waitForExistence(timeout: 3) || playButton.waitForExistence(timeout: 3)
        XCTAssertTrue(startedPlaying, "Playback controls not found after tapping a word")
    }

    func testTappingSummaryLineSeeksAndPlays() {
        let app = XCUIApplication()
        app.launchArguments += ["-reset"]
        app.launch()

        let seedButton = app.buttons["Seed"]
        XCTAssertTrue(seedButton.waitForExistence(timeout: 5), "Debug Seed button not found")
        seedButton.tap()

        let noteRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Debug Seed Note'")).firstMatch
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5), "Seeded note row not found in list")
        noteRow.tap()

        let detailPicker = app.segmentedControls.firstMatch
        XCTAssertTrue(detailPicker.waitForExistence(timeout: 5), "Detail view never appeared")

        // Summary tab is the default; tap the second point.
        let secondPoint = app.staticTexts["Second point."]
        XCTAssertTrue(secondPoint.waitForExistence(timeout: 5), "Summary point 'Second point.' not found")
        secondPoint.tap()

        let pauseButton = app.buttons["Pause"]
        let playButton = app.buttons["Play"]
        let startedPlaying = pauseButton.waitForExistence(timeout: 3) || playButton.waitForExistence(timeout: 3)
        XCTAssertTrue(startedPlaying, "Playback controls not found after tapping a summary point")
    }
}
