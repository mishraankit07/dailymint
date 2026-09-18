package com.ankit.dailymint.prototype

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.semantics.SemanticsProperties
import com.ankit.dailymint.core.*
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import androidx.test.ext.junit.runners.AndroidJUnit4

@RunWith(AndroidJUnit4::class)
class EntryFlowTest {
    @get:Rule val compose = createComposeRule()
    private class Store : LedgerStore {
        var json: String? = null
        override fun load() = LedgerRead(json)
        override fun save(snapshot: String) { json = snapshot }
    }
    private val store = Store()
    private val engine = LedgerEngine(store)
    private fun launch() { compose.setContent { DailyMintTheme { DailyMint(engine) } } }
    @Test fun smsOnboardingExplainsPermissionAndAllowsManualUse() {
        var continued = false
        compose.setContent {
            DailyMintTheme {
                AndroidSMSOnboarding(onAllow = {}, onOpenSettings = {}, showSettings = false, onContinue = { continued = true })
            }
        }
        compose.onNodeWithText("Your messages stay on this device").assertExists()
        compose.onNodeWithTag("allowSms").assertExists()
        compose.onNodeWithTag("skipSms").performClick()
        assertTrue(continued)
    }
    @Test fun addCategoryWithKeyboardAndReload() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithTag("addCategory").performScrollTo().performClick()
        compose.onNodeWithTag("categoryName").performTextInput("Travel")
        compose.onNodeWithTag("saveCategory").performClick()
        compose.onNodeWithTag("categoryName").assertDoesNotExist()
        compose.onNodeWithText("Travel").assertExists()
        assertTrue(LedgerEngine(store).categories().contains("Travel"))
    }
    @Test fun cancelDoesNotSave() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithTag("addCategory").performScrollTo().performClick()
        compose.onNodeWithTag("categoryName").performTextInput("Travel")
        compose.onNodeWithTag("cancelCategory").performClick()
        compose.onNodeWithTag("categoryName").assertDoesNotExist()
        assertFalse(engine.categories().contains("Travel"))
    }
    @Test fun invalidCategoryStaysOpen() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithTag("addCategory").performScrollTo().performClick()
        compose.onNodeWithTag("saveCategory").performClick()
        compose.onNodeWithTag("categoryError").assertExists()
        compose.onNodeWithTag("categoryName").assertExists()
    }
    @Test fun reminderSettingsPersist() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithTag("reminderToggle").performClick()
        assertTrue(engine.reminderEnabled())
        compose.onNodeWithTag("reminderH2").performTextClearance()
        compose.onNodeWithTag("reminderH2").performTextInput("8")
        assertEquals("20:30", LedgerEngine(store).reminderTime())
        compose.onNodeWithText("AM").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("PM").performScrollTo().assertIsDisplayed()
    }
    @Test fun decimalExpenseUpdatesLedgerAndResetsForm() {
        launch()
        compose.onNodeWithText("Add").performClick()
        compose.onNodeWithTag("entryName").performTextInput("Lunch")
        compose.onNodeWithTag("entryAmount").performTextInput("62.88")
        compose.onNodeWithTag("saveEntry").performScrollTo().performClick()
        compose.onNodeWithContentDescription("Home", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("spent").assertTextContains("Rs 62.88", substring = true)
        assertEquals(6288L, LedgerEngine(store).totals().spent)
    }
    @Test fun incomeEntryUpdatesMoneyInOnly() {
        launch()
        compose.onNodeWithText("Add").performClick()
        compose.onNodeWithText("Income").performClick()
        compose.onNodeWithTag("entryName").performTextInput("Salary")
        compose.onNodeWithTag("entryAmount").performTextInput("1234.00")
        compose.onNodeWithTag("saveEntry").performScrollTo().performClick()
        compose.onNodeWithContentDescription("Home", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("moneyIn").assertTextContains("Rs 1234", substring = true)
        compose.onNodeWithTag("spent").assertTextContains("Rs 0", substring = true)
        val totals = LedgerEngine(store).totals()
        assertEquals(123400L, totals.moneyIn)
        assertEquals(0L, totals.spent)
    }
    @Test fun fiveDestinationsAndSettingsReturnToGrowth() {
        launch()
        listOf("Home", "Growth", "Add", "Ledger", "Plan").forEach { compose.onNodeWithContentDescription(it, useUnmergedTree = true).assertExists() }
        compose.onNodeWithTag("navGrowth").performClick()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithText("Tracking cycle").assertExists()
        compose.onNodeWithContentDescription("Close settings").performClick()
        compose.onNodeWithText("Spending trend").assertExists()
    }
    @Test fun addCancelReturnsWithoutSaving() {
        launch()
        compose.onNodeWithTag("navGrowth").performClick()
        compose.onNodeWithTag("navAdd").performClick()
        compose.onNodeWithTag("entryName").performTextInput("Draft")
        compose.onNodeWithTag("entryAmount").performTextInput("10")
        compose.onNodeWithTag("cancelEntry").performScrollTo().performClick()
        compose.onNodeWithText("Spending trend").assertExists()
        assertTrue(engine.entries().isEmpty())
    }
    @Test fun homeRoutesToLedgerAndSearchFindsOlderHistory() {
        assertTrue(engine.addEntry("older", "Older lunch", "42", "Food", "2026-01-10", false).success)
        launch()
        compose.onNodeWithTag("seeAllTransactions").performScrollTo().performClick()
        compose.onNodeWithTag("ledgerSearch").performTextInput("Older lunch")
        compose.onNodeWithTag("ledgerRow-older").assertExists()
        compose.onNodeWithText("2026-01-10").assertExists()
    }
    @Test fun importedExpenseShareChangesHomeButNotOriginalAmount() {
        val sms = "Sent Rs.300.00 From HDFC Bank A/C *5678 To SAMPLE SHOP On 10/08/26 Ref 900000000016 Not You? Call 18002586161"
        assertTrue(engine.importSingleMessage("fixture", sms, "HDFC", 1789299000000).success)
        val imported = engine.entries().single()
        assertEquals(30000L, imported.paise)
        launch()
        compose.onNodeWithTag("navLedger").performClick()
        compose.onNodeWithTag("ledgerRow-${imported.id}").performScrollTo().performClick()
        compose.onNodeWithTag("originalAmount").assertTextContains("Rs 300", substring = true)
        compose.onNodeWithTag("personalShare").performTextClearance()
        compose.onNodeWithTag("personalShare").performTextInput("100")
        compose.onNodeWithTag("savePersonalShare").performScrollTo().performClick()
        assertEquals(30000L, engine.entries().single().paise)
        assertEquals(10000L, engine.totals().spent)
        compose.onNodeWithTag("personalAmount").assertTextContains("Rs 100", substring = true)
    }
    @Test fun reimbursementCreditStaysInLedgerButNotMoneyIn() {
        assertTrue(engine.addEntry("credit-1", "Roommate paid back", "200", "Other income", "2026-09-14", true).success)
        launch()
        compose.onNodeWithTag("moneyIn").assertTextContains("Rs 200", substring = true)
        compose.onNodeWithTag("navLedger").performClick()
        compose.onNodeWithTag("ledgerRow-credit-1").performScrollTo().performClick()
        compose.onNodeWithTag("creditKind-${CreditKind.REIMBURSEMENT}").performScrollTo().performClick()
        assertEquals(0L, engine.totals().moneyIn)
        assertEquals(20000L, engine.totals().neutralCredits)
        compose.onNodeWithTag("personalAmount").assertDoesNotExist()
        compose.onNodeWithText("Reimbursement").assertExists()
        compose.onNodeWithText("Close").performClick()
        compose.onNodeWithTag("navHome").performClick()
        compose.onNodeWithTag("moneyIn").assertDoesNotExist()
        compose.onNodeWithTag("spent").assertTextContains("Rs 0", substring = true)
    }
    @Test fun ignoredImportedTransactionLeavesAnalyticsAndCanBeRestored() {
        val sms = "Sent Rs.500.00 From HDFC Bank A/C *5678 To PROMO SHOP On 10/08/26 Ref 900000000017 Not You? Call 18002586161"
        assertTrue(engine.importSingleMessage("fixture-ignore", sms, "HDFC", 1789299000000).success)
        val imported = engine.entries().single()
        launch()
        compose.onNodeWithTag("spent").assertTextContains("Rs 500", substring = true)
        compose.onNodeWithTag("navLedger").performClick()
        compose.onNodeWithTag("ledgerRow-${imported.id}").performScrollTo().performClick()
        compose.onNodeWithTag("toggleIgnored").performScrollTo().performClick()
        assertEquals(0L, engine.totals().spent)
        assertTrue(engine.entries().single().ignored)
        compose.onNodeWithText("Ignored: excluded from all totals").assertExists()
        compose.onNodeWithText("Close").performClick()
        compose.onNodeWithTag("navHome").performClick()
        compose.onNodeWithTag("spent").assertTextContains("Rs 0", substring = true)
        compose.onNodeWithTag("navLedger").performClick()
        compose.onNodeWithTag("ledgerRow-${imported.id}").performScrollTo().performClick()
        compose.onNodeWithTag("toggleIgnored").performScrollTo().performClick()
        assertEquals(50000L, engine.totals().spent)
        assertFalse(engine.entries().single().ignored)
    }
}
