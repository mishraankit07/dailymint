import XCTest

final class EntryFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        app.launch()
        logCheckpoint("setUp launched app")
    }
    private func logCheckpoint(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let state: String
        switch app.state {
        case .notRunning: state = "notRunning"
        case .runningBackgroundSuspended: state = "runningBackgroundSuspended"
        case .runningBackground: state = "runningBackground"
        case .runningForeground: state = "runningForeground"
        @unknown default: state = "unknown"
        }
        print("DailyMintUITest checkpoint: \(message); appState=\(state)")
        XCTContext.runActivity(named: message) { activity in
            let attachment = XCTAttachment(string: "appState=\(state)\n\(app.debugDescription)")
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        XCTAssertEqual(app.state, .runningForeground, "App was not foreground at checkpoint: \(message)", file: file, line: line)
    }
    private func openCategory() {
        app.buttons["settings"].tap()
        app.buttons["addCategory"].tap()
        XCTAssertTrue(app.textFields["categoryName"].waitForExistence(timeout: 5))
    }
    func testSaveCategoryWithKeyboardAndRelaunch() {
        openCategory()
        let field = app.textFields["categoryName"]
        field.tap()
        field.typeText("Travel")
        app.buttons["saveCategory"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Travel"].exists)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Travel"].exists)
    }
    func testCancelDoesNotSave() {
        openCategory()
        app.textFields["categoryName"].typeText("Travel")
        app.buttons["cancelCategory"].tap()
        XCTAssertFalse(app.staticTexts["Travel"].exists)
        XCTAssertFalse(app.textFields["categoryName"].exists)
    }
    func testBlankCategoryStaysOpen() {
        openCategory()
        app.buttons["saveCategory"].tap()
        XCTAssertTrue(app.staticTexts["categoryError"].exists)
        XCTAssertTrue(app.textFields["categoryName"].exists)
    }
    func testEveryTabOpens() {
        for tab in ["Month", "Growth", "Import", "Manual", "Plan"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing tab \(tab)")
            button.tap()
            let selected = NSPredicate(format: "selected == true")
            expectation(for: selected, evaluatedWith: button)
            waitForExpectations(timeout: 5)
        }
    }
    func testReminderTogglePersists() {
        logCheckpoint("before opening settings for reminder")
        app.buttons["settings"].tap()
        logCheckpoint("after opening settings for reminder")
        let toggle = app.buttons["reminderToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Reminder toggle did not appear after opening Settings")
        print("DailyMintUITest checkpoint: tapping reminder toggle")
        toggle.tap()
        let status = app.staticTexts["reminderStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), "Reminder status text did not appear")
        expectation(for: NSPredicate(format: "label == 'Reminder on'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        logCheckpoint("after enabling reminder")
        print("DailyMintUITest checkpoint: terminating app for reminder persistence check")
        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "App did not terminate before relaunch")
        app.launchArguments = ["--ui-testing"]
        app.launch()
        logCheckpoint("after relaunch for reminder persistence check")
        app.buttons["settings"].tap()
        logCheckpoint("after reopening settings post relaunch")
        XCTAssertTrue(app.staticTexts["reminderStatus"].waitForExistence(timeout: 5), "Reminder status did not appear after relaunch")
        XCTAssertEqual(app.staticTexts["reminderStatus"].label, "Reminder on")
    }
    func testDecimalExpenseUpdatesLedger() {
        app.tabBars.buttons["Manual"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Lunch")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("62.88")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.alerts["Transaction saved"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let month = app.tabBars.buttons["Month"]
        month.tap()
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: month)
        waitForExpectations(timeout: 5)
        let spent = app.staticTexts["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 62.88")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 62.88")
    }
    func testIncomeEntryUpdatesMoneyInOnly() {
        app.tabBars.buttons["Manual"].tap()
        app.buttons["Income"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Salary")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("1234.00")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.alerts["Transaction saved"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.tabBars.buttons["Month"].tap()
        XCTAssertTrue(app.staticTexts["moneyIn"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["moneyIn"].label, "Money in: Rs 1234")
        XCTAssertEqual(app.staticTexts["spent"].label, "Spent: Rs 0")
    }
}
