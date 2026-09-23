package com.ankit.dailymint.core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.*

class PersonalExpenseTest {
    private fun imported(id: String, paise: Long, type: String = "expense", category: String = "Food", date: String = "2026-09-10") =
        Entry(id, "Original merchant", paise, category, date, type, "bank-wal", 1, "Bank SMS", "BANK", "RRN-1", "Bank",
            originalName = "Original merchant", originalCategory = category)

    @Test fun personalShareRecalculatesWithoutChangingBankEvidence() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(imported("bank-1", 30000)))).success)
        assertTrue(engine.setPersonalExpense("bank-1", "100").success)
        val entry = engine.entries().single()
        assertEquals(30000, entry.paise)
        assertEquals(10000, entry.personalSpent)
        assertEquals("Bank SMS", entry.rawSms)
        assertEquals("RRN-1", entry.referenceId)
        val summary = engine.monthSummary("2026-09-15")
        assertEquals(10000, summary.spent)
        assertEquals(10000, summary.categories.single().paise)
        assertEquals("bank-1", summary.topFive.single().id)
        assertEquals(10000, LedgerEngine(store).entries().single().personalSpent)
        assertTrue(engine.setPersonalExpense("bank-1", "300").success)
        assertEquals(30000, engine.totals().spent)
        assertNull(engine.entries().single().personalExpensePaise)
    }

    @Test fun invalidShareAndFailedSaveDoNotMutateLedger() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(imported("bank-1", 30000)))).success)
        listOf("-1", "300.01", "1.234", "not money").forEach {
            assertFalse(engine.setPersonalExpense("bank-1", it).success, it)
        }
        assertEquals(30000, engine.totals().spent)
        store.fail = true
        assertFalse(engine.setPersonalExpense("bank-1", "100").success)
        assertEquals(30000, engine.totals().spent)
        store.fail = false
        assertTrue(engine.setPersonalExpense("bank-1", "0").success)
        assertEquals(0, engine.totals().spent)
        assertTrue(engine.monthSummary("2026-09-15").topFive.isEmpty())
    }

    @Test fun ledgerDaysKeepGrossTotalsAcrossMonthsAndExcludeIgnoredFromTotals() {
        val engine = LedgerEngine(MemoryStore())
        val expense = imported("expense", 30000)
        val olderCredit = imported("credit", 20000, type = "income", category = "Received", date = "2026-08-20")
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(expense, olderCredit))).success)
        assertTrue(engine.setPersonalExpense("expense", "100").success)
        val days = engine.ledgerDays()
        assertEquals(listOf("2026-09-10", "2026-08-20"), days.map { it.date })
        assertEquals(30000, days.first().moneyOut)
        assertEquals(10000, days.first().entries.single().personalSpent)
        assertEquals(20000, days.last().moneyIn)
        assertTrue(engine.setIgnored("expense", true).success)
        assertEquals(0, engine.ledgerDays().first().moneyOut)
        assertEquals(1, engine.ledgerDays().first().entries.size)
    }

    @Test fun neutralCreditsRemainGrossHistoryWithoutEarnedIncome() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(
            imported("expense", 30000),
            imported("credit", 20000, "income", "Received", "2026-09-12")
        ))).success)
        assertTrue(engine.classifyCredit("credit", CreditKind.REIMBURSEMENT).success)
        assertEquals(0, engine.totals().moneyIn)
        assertEquals(20000, engine.totals().neutralCredits)
        assertEquals(30000, engine.totals().spent)
        assertEquals(20000, engine.monthSummary("2026-09-15").days.sumOf { it.moneyIn })
        assertTrue(engine.classifyCredit("credit", CreditKind.REFUND).success)
        assertEquals(0, engine.totals().moneyIn)
        assertTrue(engine.classifyCredit("credit", CreditKind.OWN_TRANSFER).success)
        assertEquals(0, engine.totals().moneyIn)
        assertTrue(engine.classifyCredit("credit", CreditKind.OTHER_INCOME).success)
        assertEquals(20000, engine.totals().moneyIn)
        assertTrue(engine.classifyCredit("credit", CreditKind.SALARY).success)
        assertEquals(20000, engine.totals().moneyIn)
    }

    @Test fun migrationKeepsOldIdentityAndReceivedIncome() {
        val old = Snapshot(schemaVersion = 1, entries = listOf(
            imported("expense", 30000), imported("old-credit", 20000, "income", "Received")
        ), smsWatermark = 1234)
        val store = MemoryStore().apply { value = Json.encodeToString(old) }
        val engine = LedgerEngine(store)
        assertNull(engine.loadError)
        assertEquals(3, engine.snapshot.schemaVersion)
        assertEquals(20000, engine.totals().moneyIn)
        assertEquals(CreditKind.OTHER_INCOME, engine.entries().last().effectiveCreditKind())
        assertEquals(1234, engine.smsWatermark())
        assertEquals("Bank SMS", engine.entries().first().rawSms)
        assertTrue(engine.addCategory("Travel").success)
        assertEquals(3, Json.decodeFromString<Snapshot>(store.value!!).schemaVersion)
    }

    @Test fun correctionAndIgnorePreserveGrossAndDedupIdentity() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(imported("bank-1", 30000)))).success)
        assertTrue(engine.correctImported("bank-1", "Corrected", "Groceries").success)
        assertTrue(engine.setPersonalExpense("bank-1", "100").success)
        assertEquals(10000, engine.monthSummary("2026-09-15").spent)
        val corrected = engine.entries().single()
        assertEquals("bank-1", corrected.id)
        assertEquals(30000, corrected.paise)
        assertEquals("Original merchant", corrected.originalName)
        assertEquals("Food", corrected.originalCategory)
        assertFalse(engine.canEdit("bank-1", "android", 1))
        assertTrue(engine.setIgnored("bank-1", true).success)
        assertEquals(0, engine.totals().spent)
        assertTrue(engine.setIgnored("bank-1", false).success)
        assertEquals(10000, engine.totals().spent)
        assertTrue(engine.deleteCategory("Groceries").success)
        assertEquals("Miscellaneous", engine.entries().single().category)
        assertEquals(10000, engine.totals().spent)
    }

    @Test fun trackingCycleAndCalendarTrendUseDifferentWindows() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(
            imported("aug", 10000, date = "2026-08-27"), imported("sep", 20000, date = "2026-09-02")
        ))).success)
        assertTrue(engine.setMonthStartDay(27).success)
        assertEquals(30000, engine.monthSummary("2026-09-15").spent)
        val buckets = engine.trendBuckets("2026-09-15", false, 3)
        assertEquals(10000, buckets[1].spent)
        assertEquals(20000, buckets[2].spent)
        val transientToggleBuckets = engine.trendBuckets("2026-09-15", true, 6)
        assertEquals(1, transientToggleBuckets.size)
        assertEquals(30000, transientToggleBuckets.single().spent)
    }

    @Test fun equalSplitUsesWholeRupeeCeilingAndSurvivesReload() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(
            imported("eight", 80000), imported("three", 30000), imported("small", 89)
        ))).success)

        assertEquals(26700, engine.equalShare("eight", 3))
        assertEquals(10000, engine.equalShare("three", 3))
        assertEquals(89, engine.equalShare("small", 2))
        assertEquals(-1, engine.equalShare("eight", 1))
        assertTrue(engine.updateImportedTransaction("eight", "Dinner", "Food", "", SplitMethod.EQUAL, 3, "").success)

        val saved = LedgerEngine(store).entries().first { it.id == "eight" }
        assertEquals(80000, saved.paise)
        assertEquals(26700, saved.personalSpent)
        assertEquals(SplitMethod.EQUAL, saved.splitMethod)
        assertEquals(3, saved.splitPeopleCount)
    }

    @Test fun importedEditorCommitsAtomicallyAndPreservesEvidence() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(imported("bank-1", 30000)))).success)

        assertFalse(engine.updateImportedTransaction(
            "bank-1", "Changed", "Groceries", "301", SplitMethod.CUSTOM, 0, ""
        ).success)
        var entry = engine.entries().single()
        assertEquals("Original merchant", entry.name)
        assertEquals("Food", entry.category)
        assertEquals(30000, entry.personalSpent)

        assertTrue(engine.updateImportedTransaction(
            "bank-1", "Changed", "Groceries", "100", SplitMethod.CUSTOM, 0, ""
        ).success)
        entry = engine.entries().single()
        assertEquals("Changed", entry.name)
        assertEquals("Groceries", entry.category)
        assertEquals(10000, entry.personalSpent)
        assertEquals(30000, entry.paise)
        assertEquals("Bank SMS", entry.rawSms)
        assertEquals("BANK", entry.sender)
        assertEquals("RRN-1", entry.referenceId)

        store.fail = true
        assertFalse(engine.updateImportedTransaction(
            "bank-1", "Not saved", "Home", "50", SplitMethod.CUSTOM, 0, ""
        ).success)
        entry = engine.entries().single()
        assertEquals("Changed", entry.name)
        assertEquals("Groceries", entry.category)
        assertEquals(10000, entry.personalSpent)
    }

    @Test fun schemaTwoReducedExpenseMigratesAsCustomSplit() {
        val old = Snapshot(schemaVersion = 2, entries = listOf(imported("bank-1", 30000).copy(personalExpensePaise = 10000)))
        val store = MemoryStore().apply { value = Json.encodeToString(old) }
        val entry = LedgerEngine(store).entries().single()
        assertEquals(SplitMethod.CUSTOM, entry.splitMethod)
        assertNull(entry.splitPeopleCount)
        assertEquals(10000, entry.personalSpent)
    }

    @Test fun manualExpenseSplitUsesSameSharedRules() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.addEntryWithSplit(
            "manual", "Dinner", "800", "Food", "2026-09-15", false, SplitMethod.EQUAL, 3, ""
        ).success)
        var entry = engine.entries().single()
        assertEquals(80000, entry.paise)
        assertEquals(26700, entry.personalSpent)
        assertEquals(26700, engine.totals().spent)

        assertFalse(engine.addEntryWithSplit(
            "bad", "Dinner", "300", "Food", "2026-09-15", false, SplitMethod.CUSTOM, 0, "301"
        ).success)
        assertEquals(1, engine.entries().size)
        entry = LedgerEngine(store).entries().single()
        assertEquals(SplitMethod.EQUAL, entry.splitMethod)
        assertEquals(3, entry.splitPeopleCount)
    }
}
