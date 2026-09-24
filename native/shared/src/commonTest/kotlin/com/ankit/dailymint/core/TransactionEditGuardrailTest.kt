package com.ankit.dailymint.core

import kotlinx.datetime.Clock
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TransactionEditGuardrailTest {
    private fun imported(id: String, paise: Long) = Entry(
        id = id,
        name = "Imported expense",
        paise = paise,
        category = "Food",
        date = LedgerDates.today().toString(),
        type = "expense",
        source = "bank-sms",
        capturedAtMillis = Clock.System.now().toEpochMilliseconds()
    )

    @Test
    fun equalSplitRequiresAtLeastOneExactRupeePerPerson() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(
            imported("five-rupees", 500),
            imported("rounding-trap", 201),
            imported("too-small", 199)
        ))).success)

        assertEquals(5, engine.maximumSplitPeople("five-rupees"))
        assertEquals(100, engine.equalShare("five-rupees", 5))
        assertEquals(-1, engine.equalShare("five-rupees", 6))
        assertEquals(2, engine.maximumSplitPeople("rounding-trap"))
        assertEquals(200, engine.equalShare("rounding-trap", 2))
        assertEquals(-1, engine.equalShare("rounding-trap", 3))
        assertEquals(0, engine.maximumSplitPeople("too-small"))
        assertEquals(-1, engine.equalShare("too-small", 2))
        assertEquals(-1, engine.equalShareForAmount("", 2))
        assertEquals(-1, engine.equalShareForAmount("0", 2))
        assertEquals(-1, engine.equalShareForAmount("not money", 2))
    }

    @Test
    fun invalidDirectParticipantCountDoesNotPublishLedgerOrAnalyticsChanges() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(imported("expense", 500)))).success)
        val before = engine.monthSummary(engine.today())
        val beforeLedger = engine.ledgerDays(engine.today())
        val beforeGrowth = engine.trendBuckets(engine.today(), false, 3)

        val belowMinimum = engine.updateImportedTransaction(
            "expense", "Changed", "Groceries", "", SplitMethod.EQUAL, 1, ""
        )
        assertFalse(belowMinimum.success)
        assertEquals("Enter at least 2 people, including you.", belowMinimum.message)

        val aboveMaximum = engine.updateImportedTransaction(
            "expense", "Changed", "Groceries", "", SplitMethod.EQUAL, 6, ""
        )
        assertFalse(aboveMaximum.success)
        assertEquals("Each person's share must be at least Rs 1.", aboveMaximum.message)
        assertEquals(imported("expense", 500).copy(capturedAtMillis = engine.entries().single().capturedAtMillis), engine.entries().single())
        assertEquals(before.spent, engine.monthSummary(engine.today()).spent)
        assertEquals(beforeLedger, engine.ledgerDays(engine.today()))
        assertEquals(beforeGrowth, engine.trendBuckets(engine.today(), false, 3))

        assertTrue(engine.updateImportedTransaction(
            "expense", "Changed", "Groceries", "", SplitMethod.EQUAL, 5, ""
        ).success)
        assertEquals(100, engine.entries().single().personalSpent)
        assertEquals(5, engine.entries().single().splitPeopleCount)
    }

    @Test
    fun manualDateEditRejectsFutureWithoutChangingAnyPublishedView() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        val now = Clock.System.now().toEpochMilliseconds()
        val today = LedgerDates.today()
        val previousMonth = today.minus(DatePeriod(months = 1)).toString()
        val original = Entry("manual", "Lunch", 5000, "Food", previousMonth, "expense", capturedAtMillis = now)
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(original))).success)
        val beforeMonth = engine.monthSummary(today.toString())
        val beforeLedger = engine.ledgerDays(today.toString())
        val beforeGrowth = engine.trendBuckets(today.toString(), false, 3)

        val future = today.plus(DatePeriod(days = 1)).toString()
        val rejected = engine.editEntry("manual", "Changed", "50", "Groceries", future, "ios", now)
        assertFalse(rejected.success)
        assertEquals("Transaction date cannot be in the future.", rejected.message)
        assertEquals(original, engine.entries().single())
        assertEquals(beforeMonth, engine.monthSummary(today.toString()))
        assertEquals(beforeLedger, engine.ledgerDays(today.toString()))
        assertEquals(beforeGrowth, engine.trendBuckets(today.toString(), false, 3))
    }

    @Test
    fun manualDateEditAcceptsPastAndTodayAndMovesEveryView() {
        val engine = LedgerEngine(MemoryStore())
        val now = Clock.System.now().toEpochMilliseconds()
        val today = LedgerDates.today()
        val previousMonth = today.minus(DatePeriod(months = 1)).toString()
        val original = Entry("manual", "Lunch", 5000, "Food", previousMonth, "expense", capturedAtMillis = now)
        assertTrue(engine.commit(engine.snapshot.copy(entries = listOf(original))).success)

        val past = today.minus(DatePeriod(days = 1)).toString()
        assertTrue(engine.editEntry("manual", "Lunch", "50", "Food", past, "ios", now).success)
        assertEquals(past, engine.entries().single().date)
        assertTrue(engine.editEntry("manual", "Lunch", "50", "Food", today.toString(), "ios", now).success)

        val saved = engine.entries().single()
        assertEquals(today.toString(), saved.date)
        assertEquals(now, saved.capturedAtMillis)
        assertEquals(today.toString(), engine.ledgerDays(today.toString()).single().date)
        assertEquals(5000, engine.monthSummary(today.toString()).spent)
        assertEquals(5000, engine.trendBuckets(today.toString(), false, 3).last().spent)
        assertNull(saved.personalExpensePaise)
    }
}
