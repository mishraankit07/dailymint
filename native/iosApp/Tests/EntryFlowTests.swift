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
    private func replaceText(in field: XCUIElement, with replacement: String) {
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let deleteExisting = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
        field.typeText(deleteExisting + replacement)
    }
    private func tapTab(_ title: String) {
        let button = app.buttons["tab-" + title]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: button
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        button.tap()
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
    func testCategoriesCanOnlyBeCreatedFromSettings() {
        app.buttons["Add"].tap()
        XCTAssertFalse(app.buttons["addCategoryFromEntry"].exists)
    }
    func testSettingsUsesStartDateLabelAndCloses() {
        app.buttons["settings"].tap()
        XCTAssertTrue(app.staticTexts["Start date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["reminderToggle"].exists)
        XCTAssertTrue(app.buttons["theme-light"].exists)
        XCTAssertTrue(app.buttons["theme-dark"].exists)
        XCTAssertTrue(app.buttons["theme-system"].exists)

        let close = app.buttons["closeSettings"]
        XCTAssertTrue(close.exists)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }
    func testEveryTabOpens() {
        let tabButtons = ["Home", "Growth", "Add", "Ledger"].map { app.buttons["tab-" + $0] }
        tabButtons.forEach { XCTAssertTrue($0.waitForExistence(timeout: 5)) }
        let tabGaps = zip(tabButtons, tabButtons.dropFirst()).map { $1.frame.midX - $0.frame.midX }
        XCTAssertEqual(tabGaps[0], tabGaps[1], accuracy: 1)
        XCTAssertEqual(tabGaps[1], tabGaps[2], accuracy: 1)
        for tab in ["Home", "Growth", "Ledger"] {
            let button = app.buttons["tab-" + tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing tab \(tab)")
            button.tap()
            let selected = NSPredicate(format: "selected == true")
            expectation(for: selected, evaluatedWith: button)
            waitForExpectations(timeout: 5)
            if tab == "Growth" {
                XCTAssertTrue(app.staticTexts["Saved + invested"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["Period details"].exists)
                XCTAssertTrue(app.buttons["growthPeriodMenu"].exists)
                XCTAssertTrue(app.buttons["growthRangeMenu"].exists)
                XCTAssertFalse(app.staticTexts["Full calendar months"].exists)
                XCTAssertFalse(app.staticTexts["Full calendar years"].exists)
            }
        }
        app.buttons["Add"].tap()
        XCTAssertTrue(app.textFields["entryName"].waitForExistence(timeout: 5))
        app.buttons["cancelEntry"].tap()
        XCTAssertTrue(app.buttons["Ledger"].isSelected)
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
        XCTAssertTrue(app.staticTexts["Open Automation"].exists)
        for title in [
            "Choose Message",
            "Set the trigger",
            "Run automatically",
            "Find DailyMint",
            "Tap Message",
            "Choose Shortcut Input",
            "Confirm the connection",
            "Save and repeat"
        ] {
            app.buttons["onboardingNext"].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
            if title == "Run automatically" {
                XCTAssertTrue(
                    app.staticTexts["Enter a short bank name, such as HDFC, PNB, ICICI, or BOB. Choose Run Immediately, then tap Next."].exists
                )
            }
        }
        XCTAssertTrue(app.staticTexts["Save and repeat"].exists)
        app.buttons["continueWithoutSMS"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "settings").count, 1)
        app.buttons["settings"].tap()
        let notificationToggle = app.switches["automaticImportNotificationToggle"]
        if !notificationToggle.exists { app.swipeUp() }
        XCTAssertTrue(notificationToggle.waitForExistence(timeout: 5))
        let setupGuide = app.buttons["openSMSSetup"]
        if !setupGuide.isHittable { app.swipeUp() }
        setupGuide.tap()
        XCTAssertTrue(app.buttons["openShortcuts"].waitForExistence(timeout: 5))
    }

    func testOnboardingReturnsAfterAppVersionChanges() {
        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--show-onboarding",
            "--reset-onboarding-release",
            "--test-app-release=1.0 (1)"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Open Automation"].waitForExistence(timeout: 5))
        app.buttons["continueWithoutSMS"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--show-onboarding", "--test-app-release=1.0 (1)"]
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Open Automation"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing", "--show-onboarding", "--test-app-release=1.0 (2)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Open Automation"].waitForExistence(timeout: 5))
    }

    func testDecimalExpenseUpdatesLedger() {
        app.buttons["Add"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Lunch")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("1234.56")
        XCTAssertEqual(app.textFields["entryAmount"].value as? String, "1,234.56")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        let toast = app.staticTexts["transactionSavedToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertEqual(toast.label, "Transaction Saved!")
        XCTAssertTrue(toast.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let month = app.buttons["Home"]
        let selected = NSPredicate(format: "selected == true")
        expectation(for: selected, evaluatedWith: month)
        waitForExpectations(timeout: 5)
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 1,234.56")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 1,234.56")
    }
    func testIncomeEntryUpdatesMoneyInOnly() {
        app.buttons["Add"].tap()
        app.buttons["Credit"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Salary")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("1234.00")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["moneyIn"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["moneyIn"].label, "Money in: Rs 1,234")
        XCTAssertEqual(app.descendants(matching: .any)["spent"].label, "Spent: Rs 0")
    }

    func testSettlementIsVisibleButNotEarnedIncome() {
        app.buttons["Add"].tap()
        app.buttons["Credit"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Expense reimbursement")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("200")
        let settlement = app.buttons["entryCategoryOption-Settlement"]
        if !settlement.isHittable { app.swipeUp() }
        settlement.tap()
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertEqual(app.descendants(matching: .any)["moneyIn"].label, "Money in: Rs 0")
        app.buttons["Ledger"].tap()
        XCTAssertTrue(app.staticTexts["Expense reimbursement"].waitForExistence(timeout: 5))
    }

    func testManualExpenseUsesEnteredPersonalAmountWithoutSplitControls() {
        app.buttons["Add"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Dinner")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("800")
        let food = app.buttons["entryCategoryOption-Food"]
        if !food.isHittable { app.swipeUp() }
        food.tap()
        XCTAssertFalse(app.switches["manualSplit"].exists)
        XCTAssertFalse(app.textFields["manualSplitPeople"].exists)
        XCTAssertFalse(app.textFields["manualPersonalShare"].exists)
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 800")
    }

    func testLedgerSearchSurvivesTabRoundTrip() {
        app.buttons["Ledger"].tap()
        let search = app.textFields["ledgerSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("coffee")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["Growth"].waitForNonExistence(timeout: 5))
        app.staticTexts["Ledger"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Growth"].waitForExistence(timeout: 5))
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
        let updated = NSPredicate(format: "label == %@", "Spent: Rs 5")
        expectation(for: updated, evaluatedWith: spent)
        waitForExpectations(timeout: 10)
    }

    func testShortcutImportAddsReceivedMessage() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-after-launch"]
        app.launch()

        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "Spent: Rs 5"), evaluatedWith: spent)
        waitForExpectations(timeout: 10)
    }

    func testShortcutImportRecoversMessagePlacedInSender() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-in-sender"]
        app.launch()

        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "Spent: Rs 5"), evaluatedWith: spent)
        waitForExpectations(timeout: 10)
    }

    func testImportedPersonalShareUpdatesHomeAndSurvivesRelaunch() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-after-launch"]
        app.launch()
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "Spent: Rs 5"), evaluatedWith: spent)
        waitForExpectations(timeout: 10)

        app.buttons["Ledger"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledgerEntry-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let food = app.buttons["transactionCategoryOption-Food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()
        app.swipeUp()
        let split = app.switches["splitTransaction"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        split.tap()
        let people = app.textFields["splitPeople"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        replaceText(in: people, with: "5")
        XCTAssertEqual(people.value as? String, "5")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["splitPeopleIncrement"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["splitPreview"].waitForExistence(timeout: 5))
        let save = app.buttons["saveImportedTransaction"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertFalse(app.staticTexts["transactionError"].exists)
        let daySummary = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "ledgerDaySummary-")
        ).firstMatch
        XCTAssertTrue(daySummary.waitForExistence(timeout: 5))
        XCTAssertEqual(daySummary.label, "Money in Rs 0 · spent Rs 1")
        tapTab("Home")
        XCTAssertEqual(spent.label, "Spent: Rs 1")

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 1")
    }

    func testImportedCustomShareUpdatesHomeAndSurvivesRelaunch() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-after-launch"]
        app.launch()
        let spent = app.descendants(matching: .any)["spent"]
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "Spent: Rs 5"), evaluatedWith: spent)
        waitForExpectations(timeout: 10)

        app.buttons["Ledger"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledgerEntry-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let food = app.buttons["transactionCategoryOption-Food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()
        app.swipeUp()

        let split = app.switches["splitTransaction"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        split.tap()
        let customMode = app.buttons["splitMethodCustom"]
        XCTAssertTrue(customMode.waitForExistence(timeout: 5))
        if !customMode.isHittable { app.swipeUp() }
        customMode.tap()

        let customShare = app.textFields["customShare"]
        XCTAssertTrue(customShare.waitForExistence(timeout: 5))
        customShare.tap()
        let save = app.buttons["saveImportedTransaction"]
        customShare.typeText("6")
        let error = app.staticTexts["customShareError"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Your share cannot exceed the original amount.")
        XCTAssertFalse(save.isEnabled)

        replaceText(in: customShare, with: "1.234")
        XCTAssertEqual(error.label, "Enter an amount with up to two decimal places.")
        XCTAssertFalse(save.isEnabled)

        replaceText(in: customShare, with: "1.25")
        XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["splitPreview"].exists)
        XCTAssertTrue(save.isEnabled)
        if !save.isHittable { app.swipeUp() }
        save.tap()
        tapTab("Home")
        XCTAssertEqual(spent.label, "Spent: Rs 1.25")

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(spent.waitForExistence(timeout: 5))
        XCTAssertEqual(spent.label, "Spent: Rs 1.25")
    }

    func testImportedSplitRejectsParticipantCountAboveMaximum() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-after-launch"]
        app.launch()
        app.buttons["Ledger"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledgerEntry-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.swipeUp()
        app.switches["splitTransaction"].tap()

        let people = app.textFields["splitPeople"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["splitPeopleDecrement"].isEnabled)
        replaceText(in: people, with: "6")
        XCTAssertEqual(people.value as? String, "6")
        XCTAssertTrue(app.staticTexts["splitPeopleError"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["splitPeopleError"].label, "Each person's share must be at least Rs 1.")
        XCTAssertFalse(app.buttons["saveImportedTransaction"].isEnabled)
    }

    func testManualEditorShowsEditableDateWithoutCaptureMetadata() {
        app.buttons["Add"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Lunch")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("50")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()

        app.buttons["Ledger"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledgerEntry-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertFalse(app.staticTexts["Captured at"].exists)
        XCTAssertTrue(app.datePickers["editEntryDate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Edit manual entry"].exists)
        XCTAssertFalse(app.staticTexts["Captured at"].exists)
        let editSave = app.buttons["saveManualTransaction"]
        XCTAssertTrue(editSave.exists)
        XCTAssertFalse(app.navigationBars.buttons["Save"].exists)
        XCTAssertGreaterThan(editSave.frame.midY, app.buttons["deleteManualTransaction"].frame.midY)
        XCTAssertLessThan(app.buttons["editEntryCategoryOption-Food"].frame.width, app.frame.width / 2)

        let amount = app.textFields["editEntryAmount"]
        replaceText(in: amount, with: "")
        if !editSave.isHittable { app.swipeUp() }
        editSave.tap()
        XCTAssertTrue(app.staticTexts["editEntryAmountError"].waitForExistence(timeout: 5))
        if !amount.isHittable { app.swipeDown() }
        amount.tap()
        amount.typeText("123456.78")
        XCTAssertEqual(amount.value as? String, "1,23,456.78")
        XCTAssertTrue(app.staticTexts["editEntryAmountError"].waitForNonExistence(timeout: 5))
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        XCTAssertEqual(amount.value as? String, "12")
        amount.typeText("3456")
        XCTAssertEqual(amount.value as? String, "1,23,456")
    }

    func testManualEditorFormatsZerosAppendedToExistingAmount() {
        app.buttons["Add"].tap()
        app.textFields["entryName"].tap()
        app.textFields["entryName"].typeText("Laptop")
        app.textFields["entryAmount"].tap()
        app.textFields["entryAmount"].typeText("2000")
        let save = app.buttons["saveEntry"]
        if !save.isHittable { app.swipeUp() }
        save.tap()

        app.buttons["Ledger"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledgerEntry-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let amount = app.textFields["editEntryAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "2,000")
        amount.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        amount.typeText("000")
        XCTAssertEqual(amount.value as? String, "20,00,000")

        let editSave = app.buttons["saveManualTransaction"]
        if !editSave.isHittable { app.swipeUp() }
        editSave.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
    }

    func testImportedTransactionCanBeDeletedAfterConfirmation() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data", "--simulate-sms-after-launch"]
        app.launch()
        app.buttons["Ledger"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ledgerEntry-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["Captured at"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Source"].exists)

        app.buttons["deleteImportedTransaction"].tap()
        let confirmDelete = app.buttons["confirmDeleteImportedTransaction"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["deleteTransactionMessage"].exists)
        XCTAssertEqual(
            app.staticTexts["deleteTransactionMessage"].label,
            "This transaction will be removed from the Ledger and from all calculations."
        )
        XCTAssertLessThan(abs(confirmDelete.frame.midY - app.frame.midY), app.frame.height / 4)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap()
        XCTAssertTrue(confirmDelete.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["deleteImportedTransaction"].exists)

        app.buttons["deleteImportedTransaction"].tap()
        app.buttons["confirmDeleteImportedTransaction"].tap()
        XCTAssertTrue(app.staticTexts["No transactions this cycle"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["Ledger"].tap()
        XCTAssertTrue(app.staticTexts["No transactions this cycle"].waitForExistence(timeout: 5))
    }

    func testDarkModeScreensAndSettingsRemainUsable() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previousAppearance }
        XCUIDevice.shared.appearance = .dark
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-test-data"]
        app.launch()

        for tab in ["Home", "Growth", "Ledger"] {
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
