import XCTest

/// Smoke tests for launch and navigation. The app is launched with
/// `-ui-testing`, which uses a throwaway data directory and disables network
/// access, so these tests are deterministic and need no live streams.
final class WorldTVUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testLaunchShowsMainWindowAndSidebar() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        for title in ["Home", "Explore", "Live TV", "TV Guide", "Favorites", "Playlists", "Settings"] {
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5), "missing sidebar item \(title)")
        }
    }

    func testNavigatesBetweenScreens() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        app.staticTexts["Playlists"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Bring your own playlists"].waitForExistence(timeout: 5))

        app.staticTexts["TV Guide"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["No programme guide yet"].waitForExistence(timeout: 5))

        app.staticTexts["Favorites"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["No favorites yet"].waitForExistence(timeout: 5))
    }

    func testKeyboardShortcutSwitchesScreen() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("6", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Bring your own playlists"].waitForExistence(timeout: 5))
    }

    func testAddPlaylistURLSheetValidatesInput() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Playlists"].firstMatch.click()
        app.buttons["Add Playlist URL…"].firstMatch.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let field = sheet.textFields["url-entry-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("rtmp://example.com/live")
        sheet.buttons["Add"].click()
        let error = sheet.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", "not supported", "not supported"))
        XCTAssertTrue(error.firstMatch.waitForExistence(timeout: 5))
    }
}
