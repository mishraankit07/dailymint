package com.ankit.dailymint.core

import kotlin.test.*

class MemoryStore : LedgerStore {
    var value: String? = null
    var fail = false
    override fun load() = LedgerRead(value)
    override fun save(snapshot: String) { if (fail) error("disk full"); value = snapshot }
}

class LedgerEngineTest {
    @Test fun missingStorageAllowsFirstSave() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertNull(engine.loadError)
        assertTrue(engine.addCategory("Travel").success)
        assertNotNull(store.value)
    }
    @Test fun readFailureBlocksWritesRatherThanReplacingLedger() {
        var writes = 0
        val store = object : LedgerStore {
            override fun load(): LedgerRead = error("read denied")
            override fun save(snapshot: String) { writes++ }
        }
        val engine = LedgerEngine(store)
        assertNotNull(engine.loadError)
        assertFalse(engine.addCategory("Travel").success)
        assertEquals(0, writes)
    }
    @Test fun emptyExistingFileIsCorruptNotMissing() {
        val store = MemoryStore().apply { value = "" }
        val engine = LedgerEngine(store)
        assertNotNull(engine.loadError)
        assertFalse(engine.addCategory("Travel").success)
        assertEquals("", store.value)
    }
    @Test fun exactAmounts() {
        assertEquals(6288L, Money.parse("62.88"))
        assertEquals(123400L, Money.parse("1,234.00"))
        assertEquals(32015600L, Money.parse("3,20,156.00"))
        assertEquals("62", Money.display(6200))
        assertEquals("62.88", Money.display(6288))
        assertEquals("1,000", Money.display(100000))
        assertEquals("1,00,000", Money.display(10000000))
        assertEquals("12,50,000.50", Money.display(125000050))
        listOf("62,88", "1.234", "-1", "0", "", "NaN", "9999999999999999999").forEach { assertNull(Money.parse(it), it) }
    }
    @Test fun categoryValidationAndPersistence() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.addCategory("  Pet   care ").success)
        assertFalse(engine.addCategory("pet care").success)
        assertFalse(engine.addCategory("salary").success)
        assertFalse(engine.addCategory("").success)
        assertTrue("Pet care" in LedgerEngine(store).categories())
    }
    @Test fun totalsAndReload() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.addEntry("1", "Salary", "1000", "Salary", "2026-09-13", true).success)
        assertTrue(engine.addEntry("2", "Lunch", "62.88", "Food", "2026-09-13", false).success)
        assertTrue(engine.addEntry("3", "Fund", "200", "Investments", "2026-09-13", false).success)
        assertTrue(engine.addEntry("4", "Refund", "10", "Received", "2026-09-13", true).success)
        val totals = LedgerEngine(store).totals()
        assertEquals(101000L, totals.moneyIn)
        assertEquals(6288L, totals.spent)
        assertEquals(20000L, totals.invested)
        assertEquals(74712L, totals.remaining)
        assertEquals(totals.moneyIn, totals.spent + totals.invested + totals.remaining)
    }
    @Test fun failedSaveDoesNotPublishState() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        store.fail = true
        assertFalse(engine.addCategory("Travel").success)
        assertFalse(engine.addEntry("1", "Lunch", "10", "Food", "2026-09-13", false).success)
        assertFalse("Travel" in engine.categories())
        assertTrue(engine.entries().isEmpty())
        store.fail = false
        assertTrue(engine.addCategory("Travel").success)
    }
    @Test fun invalidEntryDoesNotChangeLedger() {
        val engine = LedgerEngine(MemoryStore())
        assertFalse(engine.addEntry("1", "Lunch", "10", "Food", "2026-02-30", false).success)
        assertFalse(engine.addEntry("1", "", "10", "Food", "2026-09-13", false).success)
        assertFalse(engine.addEntry("1", "Pay", "10", "Salary", "2026-09-13", false).success)
        assertTrue(engine.entries().isEmpty())
    }
    @Test fun duplicateIdentityCannotChangeTotals() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.addEntry("1", "Lunch", "10", "Food", "2026-09-13", false).success)
        assertFalse(engine.addEntry("1", "Lunch", "10", "Food", "2026-09-13", false).success)
        assertEquals(1000L, engine.totals().spent)
    }
    @Test fun deletingCategoryMovesEntriesToMiscellaneousWithoutChangingTotals() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.addCategory("Travel").success)
        assertTrue(engine.addEntry("1", "Metro", "125.50", "Travel", "2026-09-13", false).success)
        assertTrue(engine.addEntry("2", "Lunch", "62.88", "Food", "2026-09-13", false).success)
        val before = engine.totals()
        assertTrue(engine.deleteCategory("Travel").success)
        val after = engine.totals()
        assertEquals(before.moneyIn, after.moneyIn)
        assertEquals(before.spent, after.spent)
        assertEquals(before.invested, after.invested)
        assertEquals("Miscellaneous", engine.entries().first { it.id == "1" }.category)
        assertTrue(engine.monthSummary("2026-09-13").categories.any { it.name == "Miscellaneous" && it.paise == 12550L })
    }
    @Test fun recentManualEditAndDeleteRecalculateTotals() {
        val engine = LedgerEngine(MemoryStore())
        val now = 1_000_000_000L
        assertTrue(engine.addEntry("1", "Lunch", "100", "Food", "2026-09-13", false).success)
        val saved = engine.entries().first()
        engine.commit(engine.snapshot.copy(entries = listOf(saved.copy(capturedAtMillis = now))))
        assertTrue(engine.editEntry("1", "Fund", "250.25", "Investments", "2026-09-13", "ios", now + 1_000).success)
        assertEquals(0L, engine.totals().spent)
        assertEquals(25025L, engine.totals().invested)
        assertTrue(engine.deleteEntry("1", "ios", now + 2_000).success)
        assertEquals(0L, engine.totals().spent)
        assertEquals(0L, engine.totals().invested)
    }
    @Test fun oldEntriesCannotBeEditedOrDeleted() {
        val engine = LedgerEngine(MemoryStore())
        val now = 2_000_000_000L
        assertTrue(engine.addEntry("1", "Lunch", "100", "Food", "2026-09-13", false).success)
        val saved = engine.entries().first()
        engine.commit(engine.snapshot.copy(entries = listOf(saved.copy(capturedAtMillis = now - 86_400_001L))))
        assertFalse(engine.editEntry("1", "Lunch", "99", "Food", "2026-09-13", "android", now).success)
        assertFalse(engine.deleteEntry("1", "android", now).success)
        assertEquals(10000L, engine.totals().spent)
    }
    @Test fun customTrackingCycleChangesMonthSummaryWindow() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.addEntry("1", "Old cycle", "10", "Food", "2026-08-24", false).success)
        assertTrue(engine.addEntry("2", "Current cycle", "20", "Food", "2026-08-25", false).success)
        assertTrue(engine.addEntry("3", "Salary", "100", "Salary", "2026-09-01", true).success)
        assertTrue(engine.setMonthStartDay(25).success)
        val summary = engine.monthSummary("2026-09-15")
        assertEquals("2026-08-25", summary.start)
        assertEquals("2026-09-25", summary.endExclusive)
        assertEquals(2000L, summary.spent)
        assertEquals(10000L, summary.moneyIn)
        assertEquals(listOf("2026-09-01", "2026-08-25"), engine.ledgerDays("2026-09-15").map { it.date })
    }
    @Test fun cycleStartDayClampsWithoutChangingPreference() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.setMonthStartDay(31).success)
        assertEquals("2027-01-31", engine.monthSummary("2027-01-31").start)
        assertEquals("2027-02-28", engine.monthSummary("2027-02-28").start)
        assertEquals(31, engine.monthStartDay())
        assertEquals("2027-03-31", engine.monthSummary("2027-03-31").start)
        assertEquals("2028-02-29", engine.monthSummary("2028-02-29").start)
        assertEquals(31, engine.monthStartDay())
    }
    @Test fun reminderSettingsValidateAndPersist() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertFalse(engine.setReminder(true, "9:30").success)
        assertTrue(engine.setReminder(true, "09:30").success)
        val reloaded = LedgerEngine(store)
        assertTrue(reloaded.reminderEnabled())
        assertEquals("09:30", reloaded.reminderTime())
        assertEquals("Tiny records become real clarity.", reloaded.reminderQuote(0))
        assertEquals("Small habits make money clearer.", reloaded.reminderQuote(-1))
    }
    @Test fun corruptStorageIsNotOverwritten() {
        val store = MemoryStore().apply { value = "bad json" }
        val engine = LedgerEngine(store)
        assertNotNull(engine.loadError)
        assertFalse(engine.addCategory("Travel").success)
        assertEquals("bad json", store.value)
    }
}
