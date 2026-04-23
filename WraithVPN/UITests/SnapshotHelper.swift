import XCTest

func setupSnapshot(_ app: XCUIApplication) {
    continueAfterFailure = false
    app.launchArguments += ["-com.apple.CoreData.ConcurrencyDebug", "0"]
}
