import XCTest

final class NoteNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTappingNoteOpensDetailView() {
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
        XCTAssertTrue(detailPicker.waitForExistence(timeout: 5), "Detail view's Summary/Transcript picker never appeared after tapping the note")
    }
}
