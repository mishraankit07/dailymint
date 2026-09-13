package com.ankit.dailymint.core

import kotlin.test.*

class LedgerParityTest {
    private fun entry(id: String, date: String, amount: Long, type: String, category: String = "Food") =
        Entry(id, id, amount, category, date, type)
    @Test fun salaryCycleClampsAndChangesWithoutChangingRecords() {
        val entries = listOf(entry("before", "2026-08-26", 10, "expense"),
            entry("pay", "2026-08-27", 10000, "income", "Salary"),
            entry("out", "2026-09-13", 1000, "expense"), entry("end", "2026-09-27", 20, "expense"))
        val cycle = LedgerAnalytics.month(entries, "2026-09-13", 27)
        assertEquals("2026-08-27", cycle.start)
        assertEquals("2026-09-27", cycle.endExclusive)
        assertEquals(10000, cycle.moneyIn)
        assertEquals(1000, cycle.spent)
        assertEquals(0, LedgerAnalytics.month(entries, "2026-09-13", 1).moneyIn)
        assertEquals("2026-02-28", LedgerAnalytics.month(entries, "2026-03-01", 31).start)
    }
    @Test fun reportIncludesCreditsButTopFiveDoesNotAndPercentsAddUp() {
        val entries = listOf(entry("pay", "2026-09-01", 10000, "income", "Salary"),
            entry("food", "2026-09-13", 1000, "expense"), entry("sip", "2026-09-13", 2000, "investment", "Investments"),
            entry("misc", "2026-09-13", 3000, "expense", "Miscellaneous"))
        val summary = LedgerAnalytics.month(entries, "2026-09-13", 1)
        assertEquals(6000, summary.todaySpend)
        assertEquals(100.0, summary.spentPercent!! + summary.savedInvestedPercent!!)
        assertTrue(summary.topFive.none { it.type == "income" })
        assertTrue(summary.days.flatMap { it.entries }.any { it.type == "income" })
        assertEquals("Miscellaneous", summary.categories.last().name)
        assertEquals(100.0, summary.categories.sumOf { it.percent }, 0.0001)
    }
    @Test fun editAndCategoryDeletePreserveAccountingIdentity() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.addEntry("1", "Fund", "200", "Investments", "2026-09-13", false).success)
        val captured = engine.entries().first().capturedAtMillis
        assertTrue(engine.editEntry("1", "Fund", "62.88", "Food", "2026-09-12", "ios", captured).success)
        assertEquals(6288, engine.totals().spent)
        assertEquals(0, engine.totals().invested)
        assertFalse(engine.editEntry("1", "Fund", "100", "Food", "2026-09-12", "ios", captured + 86_400_001).success)
        assertTrue(engine.deleteCategory("Food").success)
        assertEquals("Miscellaneous", engine.entries().first().category)
        assertEquals(6288, engine.totals().spent)
        assertFalse(engine.deleteCategory("Miscellaneous").success)
        assertTrue(engine.deleteEntry("1", "ios", captured).success)
        assertEquals(0, engine.totals().spent)
    }
    @Test fun trendsUseCalendarMonthsAndExcludeInvestmentFromWealthReduction() {
        val entries = listOf(entry("pay", "2026-08-27", 10000, "income"), entry("out", "2026-09-01", 1000, "expense"),
            entry("sip", "2026-09-01", 2000, "investment"))
        val buckets = LedgerAnalytics.trends(entries, "2026-09-13", false, 3)
        assertEquals(3, buckets.size)
        assertEquals(9000, buckets.last().wealth)
        assertEquals(2000, buckets.last().invested)
        assertEquals(1, LedgerAnalytics.trends(entries, "2026-09-13", true, 1).size)
    }
    @Test fun importEnvelopeUsesIndiaTimeAndDedupesRepeatTriggers() {
        val sms = SmsFixtures.values.first { it.id == "hdfc-upi-sent-001" }.sms
        val text = "current_date:13 Sep 2026 at 12:01:00 AM IST\n$sms\ncurrent_date:13 Sep 2026 at 12:02:00 AM IST\n$sms"
        val rows = TransactionImport.rows(text, Snapshot(), 1000)
        assertEquals(listOf("new", "repeated"), rows.map { it.status })
        assertEquals("2026-09-12T18:31:00Z", rows[0].entry!!.date)
        assertEquals("2026-09-13", LedgerDates.date(rows[0].entry!!.date).toString())
    }
}

