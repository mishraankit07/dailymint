package com.ankit.dailymint.core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.*

class ImportPersistenceTest {
    private val raw = SmsFixtures.values.first { it.id == "hdfc-upi-sent-001" }.sms
    @Test fun stagingDoesNotChangeTotalsUntilSaveAndClearsAfterSave() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.stageWal("current_date:13 Sep 2026 at 9:00:00 AM IST\n$raw", "13 Sep.txt").success)
        assertEquals(0L, engine.totals().spent)
        val restored = LedgerEngine(store)
        assertEquals(1, restored.reviewRows().size)
        val originalAmount = restored.reviewRows().single().entry!!.paise
        assertFalse(restored.editReview("row-0", "Travel", Money.display(originalAmount + 1), "Fun").success)
        assertTrue(restored.editReview("row-0", "Travel", Money.display(originalAmount), "Fun").success)
        assertTrue(restored.saveReview().success)
        assertEquals(originalAmount, restored.totals().spent)
        assertTrue(restored.reviewRows().isEmpty())
        assertTrue(restored.stageWal("current_date:13 Sep 2026 at 9:02:00 AM IST\n$raw", "repeat.txt").success)
        assertEquals("already-recorded", restored.reviewRows().first().status)
        assertFalse(restored.editReview("row-0", "Travel", "99", "Food").success)
        assertTrue(restored.saveReview().success)
        assertEquals(originalAmount, restored.totals().spent)
    }
    @Test fun failedReviewSaveKeepsQueueAndOldTotals() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        engine.stageWal("current_date:13 Sep 2026 at 9:00:00 AM IST\n$raw", "file.txt")
        store.fail = true
        assertFalse(engine.saveReview().success)
        assertEquals(0L, engine.totals().spent)
        assertEquals(1, engine.reviewRows().size)
    }
    @Test fun automaticSmsImportIsIdempotentAndCreditsStayIncome() {
        val engine = LedgerEngine(MemoryStore())
        val credit = SmsFixtures.values.first { it.id == "bob-upi-credit-001" }.sms
        val json = Json.encodeToString(listOf(IncomingSms("1", raw, "HDFC", 1789299000000), IncomingSms("2", credit, "BOB", 1789299001000)))
        assertTrue(engine.importMessages(json).success)
        assertTrue(engine.importMessages(json).success)
        assertEquals(2, engine.entries().size)
        assertEquals(1, engine.entries().count { it.type == "income" })
        assertTrue(engine.reviewRows().isEmpty())
        assertEquals(1789299001000, engine.smsWatermark())
    }
    @Test fun automaticImportFailureDoesNotAdvanceWatermark() {
        val store = MemoryStore().apply { fail = true }
        val engine = LedgerEngine(store)
        assertFalse(engine.importMessages(Json.encodeToString(listOf(IncomingSms("1", raw, "HDFC", 1789299000000)))).success)
        assertEquals(0, engine.smsWatermark())
        assertTrue(engine.entries().isEmpty())
    }
    @Test fun singleMessageImportUsesSamePipelineAsBatchImport() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.importSingleMessage("shortcut-1", raw, "HDFC", 1789299000000).success)
        assertTrue(engine.importSingleMessage("shortcut-2", raw, "HDFC", 1789299005000).success)
        assertEquals(1, engine.entries().size)
        assertEquals(1789299005000, engine.smsWatermark())
        assertEquals(0, engine.reviewRows().size)
        assertEquals(0, engine.unrecognizedMessages().size)
    }
    @Test fun automaticImportKeepsUnrecognizedTransactionMessagesForDiagnostics() {
        val engine = LedgerEngine(MemoryStore())
        val unknown = "Rs.10.00 debited."
        val promo = "Get 25 Reward points on every Rs.100 spent with SBI Credit Card."
        assertTrue(engine.importSingleMessage("unknown-1", unknown, "BANK", 1789299000000).success)
        assertTrue(engine.importSingleMessage("promo-1", promo, "SBI", 1789299001000).success)
        assertTrue(engine.entries().isEmpty())
        assertEquals(1, engine.unrecognizedMessages().size)
        assertEquals("unknown-1", engine.unrecognizedMessages().first().id)
        assertEquals(unknown, engine.unrecognizedMessages().first().rawText)
    }
}
