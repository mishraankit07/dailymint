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

    @Test fun ledgerDaysUseCurrentCycleAndKeepGrossAmounts() {
        val engine = LedgerEngine(MemoryStore())
        val expense = imported("expense", 30000)
        val olderCredit = imported("credit", 20000, type = "income", category = "Income", date = "2026-08-20")
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(expense, olderCredit))).success)
        assertTrue(engine.setPersonalExpense("expense", "100").success)
        val days = engine.ledgerDays("2026-09-15")
        assertEquals(listOf("2026-09-10"), days.map { it.date })
        assertEquals(30000, days.first().moneyOut)
        assertEquals(10000, days.first().entries.single().personalSpent)
    }

    @Test fun neutralCreditsRemainGrossHistoryWithoutEarnedIncome() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(
            imported("expense", 30000),
            imported("credit", 20000, "income", "Income", "2026-09-12")
        ))).success)
        assertTrue(engine.classifyCredit("credit", CreditKind.SETTLEMENT).success)
        assertEquals(0, engine.totals().moneyIn)
        assertEquals(20000, engine.totals().neutralCredits)
        assertEquals(30000, engine.totals().spent)
        assertEquals(20000, engine.monthSummary("2026-09-15").days.sumOf { it.moneyIn })
        assertTrue(engine.classifyCredit("credit", CreditKind.OWN_TRANSFER).success)
        assertEquals(0, engine.totals().moneyIn)
        assertTrue(engine.classifyCredit("credit", CreditKind.INCOME).success)
        assertEquals(20000, engine.totals().moneyIn)
    }

    @Test fun migrationKeepsOldIdentityAndReceivedIncome() {
        val old = Snapshot(schemaVersion = 1, entries = listOf(
            imported("expense", 30000), imported("old-credit", 20000, "income", "Received")
        ), smsWatermark = 1234)
        val store = MemoryStore().apply { value = Json.encodeToString(old) }
        val engine = LedgerEngine(store)
        assertNull(engine.loadError)
        assertEquals(5, engine.snapshot.schemaVersion)
        assertEquals(20000, engine.totals().moneyIn)
        assertEquals(CreditKind.INCOME, engine.entries().last().effectiveCreditKind())
        assertEquals("Income", engine.entries().last().category)
        assertEquals(1234, engine.smsWatermark())
        assertEquals("Bank SMS", engine.entries().first().rawSms)
        assertTrue(engine.addCategory("Travel").success)
        assertEquals(5, Json.decodeFromString<Snapshot>(store.value!!).schemaVersion)
    }

    @Test fun correctionAndDeletionPreserveIdentityContract() {
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
        assertTrue(engine.deleteCategory("Groceries").success)
        assertEquals("Miscellaneous", engine.entries().single().category)
        assertEquals(10000, engine.totals().spent)
        assertTrue(engine.deleteEntry("bank-1").success)
        assertTrue(engine.entries().isEmpty())
        assertEquals(0, engine.totals().spent)
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
        assertEquals(-1, engine.equalShare("small", 2))
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

    @Test fun schemaFourCreditsMigrateToSimplifiedKindsWithoutChangingIdentityOrAmount() {
        val old = Snapshot(schemaVersion = 4, entries = listOf(
            imported("salary", 10000, "income", "Salary").copy(creditKind = "salary"),
            imported("other", 20000, "income", "Other income").copy(creditKind = "other_income"),
            imported("refund", 30000, "income", "Refund").copy(creditKind = "refund"),
            imported("reimbursement", 40000, "income", "Reimbursement").copy(creditKind = "reimbursement"),
            imported("transfer", 50000, "income", "Own-account transfer").copy(creditKind = "own_transfer")
        ))
        val engine = LedgerEngine(MemoryStore().apply { value = Json.encodeToString(old) })

        assertNull(engine.loadError)
        assertEquals(5, engine.snapshot.schemaVersion)
        assertEquals(listOf("salary", "other", "refund", "reimbursement", "transfer"), engine.entries().map { it.id })
        assertEquals(listOf(10000L, 20000L, 30000L, 40000L, 50000L), engine.entries().map { it.paise })
        assertEquals(listOf("Income", "Income", "Settlement", "Settlement", "Own account transfer"),
            engine.entries().map { it.category })
        assertEquals(30000, engine.totals().moneyIn)
        assertEquals(120000, engine.totals().neutralCredits)
    }

    @Test fun schemaFiveLegacyCreditKindIsNormalizedBeforeValidation() {
        val saved = Snapshot(schemaVersion = 5, entries = listOf(
            imported("income", 10000, "income", "Income").copy(creditKind = null),
            imported("other", 20000, "income", "Other income").copy(creditKind = null),
            imported("transfer", 30000, "income", "Self account transfer").copy(creditKind = null),
            imported("refund", 40000, "income", "Refund").copy(creditKind = null)
        ))
        val engine = LedgerEngine(MemoryStore().apply { value = Json.encodeToString(saved) })

        assertNull(engine.loadError)
        assertEquals(listOf(CreditKind.INCOME, CreditKind.INCOME, CreditKind.OWN_TRANSFER, CreditKind.SETTLEMENT),
            engine.entries().map { it.creditKind })
        assertEquals(listOf("Income", "Income", "Own account transfer", "Settlement"),
            engine.entries().map { it.category })
    }

    @Test fun obsoleteIgnoredAndSplitMetadataDoesNotBlockTheSavedLedger() {
        val saved = Snapshot(schemaVersion = 5, entries = listOf(
            imported("kept", 10000).copy(splitMethod = "legacy", splitPeopleCount = 4),
            imported("ignored", 20000).copy(ignored = true)
        ))
        val engine = LedgerEngine(MemoryStore().apply { value = Json.encodeToString(saved) })

        assertNull(engine.loadError)
        assertEquals(listOf("kept"), engine.entries().map { it.id })
        assertEquals(SplitMethod.NONE, engine.entries().single().splitMethod)
        assertNull(engine.entries().single().splitPeopleCount)
    }

    @Test fun pendingLegacyCreditIsMigratedBeforeItCanBeSavedIntoSchemaFive() {
        val pending = imported("refund", 30000, "income", "Refund").copy(creditKind = "refund")
        val store = MemoryStore().apply {
            value = Json.encodeToString(Snapshot(schemaVersion = 4,
                review = listOf(ReviewRow("row-refund", pending, "new"))))
        }
        val engine = LedgerEngine(store)

        assertNull(engine.loadError)
        assertTrue(engine.saveReview().success)
        val reloaded = LedgerEngine(store)
        assertNull(reloaded.loadError)
        assertEquals(CreditKind.SETTLEMENT, reloaded.entries().single().creditKind)
        assertEquals("Settlement", reloaded.entries().single().category)
    }

    @Test fun manualExpenseCountsEnteredAmountWithoutSplitMetadata() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.addEntry("manual", "My share", "1000", "Food", "2026-09-15", false).success)
        val entry = LedgerEngine(store).entries().single()
        assertEquals(100000, entry.paise)
        assertEquals(100000, entry.personalSpent)
        assertNull(entry.personalExpensePaise)
        assertEquals(SplitMethod.NONE, entry.splitMethod)
        assertNull(entry.splitPeopleCount)
        assertFalse(engine.addEntryWithSplit(
            "split-manual", "Full bill", "2400", "Food", "2026-09-15", false,
            SplitMethod.CUSTOM, 0, "1000"
        ).success)
    }

    @Test fun schemaThreeDropsPreviouslyIgnoredEntriesWithoutChangingKeptIds() {
        val old = Snapshot(schemaVersion = 3, entries = listOf(
            imported("kept", 10000), imported("ignored", 20000).copy(ignored = true)
        ))
        val store = MemoryStore().apply { value = Json.encodeToString(old) }
        val engine = LedgerEngine(store)
        assertNull(engine.loadError)
        assertEquals(5, engine.snapshot.schemaVersion)
        assertEquals(listOf("kept"), engine.entries().map { it.id })
        assertEquals(10000, engine.totals().spent)
    }

    @Test fun deletionFailurePublishesNoStateOrAnalyticsChange() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(imported("bank-1", 30000)))).success)
        val before = engine.monthSummary("2026-09-15")
        store.fail = true
        assertFalse(engine.deleteEntry("bank-1").success)
        assertEquals(listOf("bank-1"), engine.entries().map { it.id })
        assertEquals(before.spent, engine.monthSummary("2026-09-15").spent)
    }

    @Test fun homeBreakdownAndAllocationIncludeInvestments() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(
            imported("salary", 100000, "income", "Income").copy(creditKind = CreditKind.INCOME),
            imported("food", 30000),
            imported("fund", 20000, "investment", "Investments")
        ))).success)
        val summary = engine.monthSummary("2026-09-15")
        assertEquals(100000, summary.moneyIn)
        assertEquals(30000, summary.spent)
        assertEquals(20000, summary.invested)
        assertEquals(20, summary.allocationInvestedPercent)
        assertEquals(30, summary.allocationSpentPercent)
        assertEquals(50, summary.allocationLeftPercent)
        assertEquals(listOf("Food", "Investments"), summary.categories.map { it.name }.sorted())
        assertEquals(60.0, summary.categories.first { it.name == "Food" }.percent)
        assertEquals(40.0, summary.categories.first { it.name == "Investments" }.percent)

        val noIncome = LedgerEngine(MemoryStore())
        assertTrue(noIncome.commit(noIncome.snapshot.copy(entries = listOf(imported("food", 30000)))).success)
        assertEquals(-1, noIncome.monthSummary("2026-09-15").allocationSpentPercent)

        val overIncome = LedgerEngine(MemoryStore())
        assertTrue(overIncome.commit(overIncome.snapshot.copy(entries = listOf(
            imported("salary", 10000, "income", "Income").copy(creditKind = CreditKind.INCOME),
            imported("food", 15000)
        ))).success)
        val overSummary = overIncome.monthSummary("2026-09-15")
        assertTrue(overSummary.allocationExceedsIncome)
        assertEquals(150, overSummary.allocationSpentPercent)
        assertEquals(0, overSummary.allocationLeftPercent)
    }

    @Test fun deletingOneRecordRemovesItFromEveryCalculationAndSurvivesReload() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(
            imported("salary", 100000, "income", "Income").copy(creditKind = CreditKind.INCOME),
            imported("food", 30000),
            imported("fund", 20000, "investment", "Investments")
        ))).success)

        assertTrue(engine.deleteEntry("food").success)
        assertEquals(0, engine.totals().spent)
        assertEquals(100000, engine.totals().moneyIn)
        assertEquals(20000, engine.totals().invested)
        assertTrue(engine.monthSummary("2026-09-15").topFive.isEmpty())
        assertFalse(engine.monthSummary("2026-09-15").categories.any { it.name == "Food" })
        assertEquals(0, engine.trendBuckets("2026-09-15", false, 3).last().spent)
        assertFalse(engine.ledgerDays("2026-09-15").flatMap { it.entries }.any { it.id == "food" })
        assertEquals(listOf("salary", "fund"), LedgerEngine(store).entries().map { it.id })
    }
}
