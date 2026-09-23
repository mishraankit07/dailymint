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
    func testExpenseCategoryCanBeCreatedFromAdd() {
        app.buttons["Add"].tap()
        app.buttons["entryCategory"].tap()
        let addCategory = app.buttons["addCategoryFromEntry"]
        XCTAssertTrue(addCategory.waitForExistence(timeout: 5))
        addCategory.tap()
        XCTAssertTrue(app.textFields["categoryName"].waitForExistence(timeout: 5))
        app.textFields["categoryName"].typeText("Travel")
        app.buttons["saveCategory"].tap()
        XCTAssertTrue(app.textFields["categoryName"].waitForNonExistence(timeout: 5))
        app.buttons["entryCategory"].tap()
        XCTAssertTrue(app.buttons["Travel"].waitForExistence(timeout: 5))
    }
    func testEveryTabOpens() {
        for tab in ["Home", "Growth", "Ledger", "Plan"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing tab \(tab)")
            button.tap()
            let selected = NSPredicate(format: "selected == true")
            expectation(for: selected, evaluatedWith: button)
            waitForExpectations(timeout: 5)
        }
        app.buttons["Add"].tap()
        XCTAssertTrue(app.textFields["entryName"].waitForExistence(timeout: 5))
        app.buttons["cancelEntry"].tap()
        XCTAssertTrue(app.buttons["Plan"].isSelected)
    }
    func testHomeGreetingFollowsTimeOfDay() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--test-hour=9"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Good morning"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--test-hour=14"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Good afternoon"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--test-hour=20"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Good evening"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--test-hour=23"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Good evening"].waitForExistence(timeout: 5))
    }
    func testSMSSetupCanBeDeferredAndReopened() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--show-onboarding", "--reset-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["openShortcuts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["smsSetupStatus"].exists)
        app.buttons["continueWithoutSMS"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "settings").count, 1)
        app.buttons["settings"].tap()
        let setup = app.buttons["openSMSSetup"]
        if !setup.isHittable { app.swipeUp() }
        setup.tap()
        XCTAssertTrue(app.buttons["openShortcuts"].waitForExistence(timeout: 5))
    }
    func testDecimalExpenseUpdatesLedger() {
        app.buttons["Add"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Lunch")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("62.88")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let month = app.buttons["Home"]
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: month)
        waitForExpectations(timeout: 5)
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Rs 62.88")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Rs 62.88")
    }
    func testIncomeEntryUpdatesMoneyInOnly() {
        app.buttons["Add"].tap()
        app.buttons["Income"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Salary")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("1234.00")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["moneyIn"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["moneyIn"].label, "Income: Rs 1234")
        XCTAssertEqual(app.descendants(matching: .any)["spent"].label, "Rs 0")
    }

    func testReimbursementIsVisibleButNotEarnedIncome() {
        app.buttons["Add"].tap()
        app.buttons["Income"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Expense reimbursement")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("200")
        app.buttons["entryCategory"].tap()
        app.buttons["Reimbursement"].tap()
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertEqual(app.descendants(matching: .any)["moneyIn"].label, "Income: Rs 0")
        app.buttons["Ledger"].tap()
        XCTAssertTrue(app.staticTexts["Expense reimbursement"].waitForExistence(timeout: 5))
    }

    func testManualEqualSplitUsesPersonalShareInHome() {
        app.buttons["Add"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Dinner")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("800")
        app.buttons["entryCategory"].tap()
        app.buttons["Food"].tap()
        let split = app.switches["manualSplit"]
        if !split.isHittable { app.swipeUp() }
        split.tap()
        let people = app.textFields["manualSplitPeople"]
        people.tap()
        people.typeText(XCUIKeyboardKey.delete.rawValue + "3")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Rs 267")
    }

    func testLedgerSearchSurvivesTabRoundTrip() {
        app.buttons["Ledger"].tap()
        let search = app.textFields["ledgerSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("coffee")
        app.buttons["Growth"].tap()
        app.buttons["Ledger"].tap()
        XCTAssertEqual(app.textFields["ledgerSearch"].value as? String, "coffee")
    }

    func testIncomingSMSUpdatesOpenMonthWithoutRelaunch() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-after-launch"]
        app.launch()
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        let updated = NSPredicate(format: "label == %@", "Rs 5")
        expectation(for: updated, evaluatedWith: spent)
        waitForExpectations(timeout: 10)
    }

    func testImportedPersonalShareUpdatesHomeAndSurvivesRelaunch() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-after-launch"]
        app.launch()
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "Rs 5"), evaluatedWith: spent)
        waitForExpectations(timeout: 10)

        app.buttons["Ledger"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledgerEntry-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let category = app.buttons["transactionCategory"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        let food = app.buttons["transactionCategoryOption-Food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(category.label.contains("Food"))
        app.swipeUp()
        let split = app.switches["splitTransaction"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        split.tap()
        app.buttons["Custom share"].tap()
        let share = app.textFields["customShare"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        share.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        let save = app.buttons["saveImportedTransaction"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertFalse(app.staticTexts["transactionError"].exists)
        app.buttons["Home"].tap()
        XCTAssertEqual(spent.label, "Rs 2")

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Rs 2")
    }

    func testDarkModeScreensAndSettingsRemainUsable() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previousAppearance }
        XCUIDevice.shared.appearance = .dark
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        app.launch()

        for tab in ["Home", "Growth", "Ledger", "Plan"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(button.isSelected)
        }

        app.buttons["Home"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let addCategory = app.buttons["addCategory"]
        if !addCategory.isHittable { app.swipeUp() }
        addCategory.tap()
        XCTAssertTrue(app.textFields["categoryName"].waitForExistence(timeout: 5))
        app.buttons["cancelCategory"].tap()
    }

}
