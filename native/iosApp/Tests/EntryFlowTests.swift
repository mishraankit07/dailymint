import XCTest

final class EntryFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        app.launch()
    }
    private func openCategory() {
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let addCategory = app.buttons["addCategory"]
        XCTAssertTrue(addCategory.waitForExistence(timeout: 5))
        if !addCategory.isHittable { app.swipeUp() }
        addCategory.tap()
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
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing tab \(tab)")
            button.tap()
            let selected = NSPredicate(format: "selected == true")
            expectation(for: selected, evaluatedWith: button)
            waitForExpectations(timeout: 5)
        }
    }
    func testSMSSetupCanBeDeferredAndReopened() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--show-onboarding", "--reset-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["openShortcuts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["smsSetupStatus"].exists)
        app.buttons["continueWithoutSMS"].tap()
        XCTAssertTrue(app.buttons["Month"].waitForExistence(timeout: 5))
        app.buttons["settings"].tap()
        let setup = app.buttons["openSMSSetup"]
        if !setup.isHittable { app.swipeUp() }
        setup.tap()
        XCTAssertTrue(app.buttons["openShortcuts"].waitForExistence(timeout: 5))
    }
    func testDecimalExpenseUpdatesLedger() {
        app.buttons["Manual"].tap()
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
        let month = app.buttons["Month"]
        month.tap()
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: month)
        waitForExpectations(timeout: 5)
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 62.88")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 62.88")
    }
    func testIncomeEntryUpdatesMoneyInOnly() {
        app.buttons["Manual"].tap()
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
        app.buttons["Month"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["moneyIn"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["moneyIn"].label, "Money in: Rs 1234")
        XCTAssertEqual(app.descendants(matching: .any)["spent"].label, "Spent: Rs 0")
    }

    func testIncomingSMSUpdatesOpenMonthWithoutRelaunch() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-after-launch"]
        app.launch()
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        let updated = NSPredicate(format: "label == %@", "Spent: Rs 5")
        expectation(for: updated, evaluatedWith: spent)
        waitForExpectations(timeout: 10)
    }

    func testDarkModeScreensAndSettingsRemainUsable() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previousAppearance }
        XCUIDevice.shared.appearance = .dark
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        app.launch()

        for tab in ["Month", "Growth", "Import", "Manual", "Plan"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(button.isSelected)
        }

        app.buttons["Month"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let addCategory = app.buttons["addCategory"]
        if !addCategory.isHittable { app.swipeUp() }
        addCategory.tap()
        XCTAssertTrue(app.textFields["categoryName"].waitForExistence(timeout: 5))
        app.buttons["cancelCategory"].tap()
    }
}
