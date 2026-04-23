import XCTest

class SnapshotHelper: XCTestCase {
    static func setupSnapshot(_ app: XCUIApplication) {
        app.launchArguments += ["-com.apple.CoreData.ConcurrencyDebug", "0"]
    }
}
