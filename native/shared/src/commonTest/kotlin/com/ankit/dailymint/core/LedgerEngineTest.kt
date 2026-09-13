package com.ankit.dailymint.core

import kotlin.test.*

class MemoryStore : LedgerStore {
    var value: String? = null
    var fail = false
    override fun load() = value
    override fun save(snapshot: String) { if (fail) error("disk full"); value = snapshot }
}

class LedgerEngineTest {
    @Test fun exactAmounts() {
        assertEquals(6288L, Money.parse("62.88"))
        assertEquals(123400L, Money.parse("1,234.00"))
        assertEquals(32015600L, Money.parse("3,20,156.00"))
        assertEquals("62", Money.display(6200))
        assertEquals("62.88", Money.display(6288))
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
    @Test fun corruptStorageIsNotOverwritten() {
        val store = MemoryStore().apply { value = "bad json" }
        val engine = LedgerEngine(store)
        assertNotNull(engine.loadError)
        assertFalse(engine.addCategory("Travel").success)
        assertEquals("bad json", store.value)
    }
}
