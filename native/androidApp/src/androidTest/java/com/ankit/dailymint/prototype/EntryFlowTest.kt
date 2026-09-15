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
    private fun launch() { compose.setContent { MaterialTheme { DailyMint(engine) } } }
    @Test fun addCategoryWithKeyboardAndReload() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithTag("addCategory").performClick()
        compose.onNodeWithTag("categoryName").performTextInput("Travel")
        compose.onNodeWithTag("saveCategory").performClick()
        compose.onNodeWithTag("categoryName").assertDoesNotExist()
        compose.onNodeWithText("Travel").assertExists()
        assertTrue(LedgerEngine(store).categories().contains("Travel"))
    }
    @Test fun cancelDoesNotSave() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithTag("addCategory").performClick()
        compose.onNodeWithTag("categoryName").performTextInput("Travel")
        compose.onNodeWithTag("cancelCategory").performClick()
        compose.onNodeWithTag("categoryName").assertDoesNotExist()
        assertFalse(engine.categories().contains("Travel"))
    }
    @Test fun invalidCategoryStaysOpen() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithTag("addCategory").performClick()
        compose.onNodeWithTag("saveCategory").performClick()
        compose.onNodeWithTag("categoryError").assertExists()
        compose.onNodeWithTag("categoryName").assertExists()
    }
    @Test fun reminderSettingsPersist() {
        launch()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithTag("reminderToggle").performClick()
        assertTrue(engine.reminderEnabled())
        compose.onNodeWithTag("reminderTime").performClick()
        compose.onNodeWithText("20:30").performClick()
        assertEquals("20:30", LedgerEngine(store).reminderTime())
    }
    @Test fun decimalExpenseUpdatesLedgerAndResetsForm() {
        launch()
        compose.onNodeWithText("Manual").performClick()
        compose.onNodeWithTag("entryName").performTextInput("Lunch")
        compose.onNodeWithTag("entryAmount").performTextInput("62.88")
        compose.onNodeWithTag("saveEntry").performScrollTo().performClick()
        compose.onNodeWithText("Transaction saved").assertExists()
        compose.onNodeWithText("OK").performClick()
        assertEquals("", compose.onNodeWithTag("entryAmount").fetchSemanticsNode().config[SemanticsProperties.EditableText].text)
        compose.onNodeWithText("Month").performClick()
        compose.onNodeWithTag("spent").assertTextEquals("Spent: Rs 62.88")
        assertEquals(6288L, LedgerEngine(store).totals().spent)
    }
    @Test fun incomeEntryUpdatesMoneyInOnly() {
        launch()
        compose.onNodeWithText("Manual").performClick()
        compose.onNodeWithText("Income").performClick()
        compose.onNodeWithTag("entryName").performTextInput("Salary")
        compose.onNodeWithTag("entryAmount").performTextInput("1234.00")
        compose.onNodeWithTag("saveEntry").performScrollTo().performClick()
        compose.onNodeWithText("Transaction saved").assertExists()
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithText("Month").performClick()
        compose.onNodeWithTag("moneyIn").assertTextEquals("Money in: Rs 1234")
        compose.onNodeWithTag("spent").assertTextEquals("Spent: Rs 0")
        val totals = LedgerEngine(store).totals()
        assertEquals(123400L, totals.moneyIn)
        assertEquals(0L, totals.spent)
    }
}
