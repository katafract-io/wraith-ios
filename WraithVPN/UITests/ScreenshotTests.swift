import XCTest

@MainActor
final class WraithVPNScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapture01Hero() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-subscribed", "--mock-connected",
        ])
        sleep(4)
        snapshot("01_hero")
    }

    func testCapture02Operator() {
        let app = launch(flags: [
            "--screenshots", "--force-onboarding",
        ])
        sleep(3)
        snapshot("02_operator")
    }

    func testCapture03Regions() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-subscribed", "--mock-regions",
        ])
        let regionButton = app.buttons.matching(identifier: "region-button").firstMatch
        if regionButton.waitForExistence(timeout: 5) {
            regionButton.tap()
            sleep(3)
        }
        snapshot("03_regions")
    }

    func testCapture04Haven() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-subscribed", "--mock-haven-prefs",
        ])
        let settingsTab = app.buttons.matching(identifier: "settings-tab").firstMatch
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
        }
        let havenRow = app.buttons.matching(identifier: "haven-row").firstMatch
        if havenRow.waitForExistence(timeout: 5) {
            havenRow.tap()
            sleep(3)
        }
        snapshot("04_haven")
    }

    func testCapture05Stats() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-subscribed", "--mock-dns-stats",
        ])
        let settingsTab = app.buttons.matching(identifier: "settings-tab").firstMatch
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
        }
        let statsRow = app.buttons.matching(identifier: "stats-row").firstMatch
        if statsRow.waitForExistence(timeout: 5) {
            statsRow.tap()
            sleep(3)
        }
        snapshot("05_stats")
    }

    func testCapture06Paywall() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-unsubscribed", "--paywall-sovereign-annual",
        ])
        sleep(4)
        snapshot("06_paywall")
    }

    func testCapture07KillSwitch() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-subscribed", "--mock-disconnected-advanced",
        ])
        sleep(4)
        snapshot("07_killswitch")
    }

    // MARK: - Frame 08: Connected with live DNS stats + byte counters

    func testCapture08ConnectedStats() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-subscribed", "--mock-connected",
            "--mock-dns-stats",
        ])
        sleep(4)
        snapshot("08_connected_stats")
    }

    // MARK: - Frame 09: Stealth mode active (Shadowsocks fallback engaged)

    func testCapture09Stealth() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-subscribed",
            "--mock-connected",
        ])
        sleep(4)
        snapshot("09_stealth")
    }

    // MARK: - Frame 10: Multi-hop server selection (Sovereign feature)

    func testCapture10MultiHop() {
        let app = launch(flags: [
            "--screenshots", "--skip-onboarding", "--mock-subscribed", "--mock-connected",
            "--mock-regions",
        ])
        let regionButton = app.buttons.matching(identifier: "region-button").firstMatch
        if regionButton.waitForExistence(timeout: 5) {
            regionButton.tap()
            sleep(3)
        }
        snapshot("10_multihop")
    }

    // MARK: - Helpers

    private func launch(flags: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += flags
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "App did not reach foreground within 30s — aborting to avoid silent 0-PNG run"
        )
        return app
    }
}
