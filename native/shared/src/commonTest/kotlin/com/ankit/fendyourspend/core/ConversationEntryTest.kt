package com.ankit.fendyourspend.core

import kotlin.test.*

class ConversationEntryTest {
    @Test fun explicitCommandsExtractAmountAndMerchant() {
        for (verb in listOf("Spent", "spend", "Paid", "gave")) {
            val draft = ConversationParser.parse("$verb Rs 1,234.56 at Cafe", "2026-11-23").draft!!
            assertEquals("1,234.56", draft.amount)
            assertEquals("Cafe", draft.name)
            assertFalse(draft.income)
        }
        assertEquals("Starbucks", ConversationParser.parse("Paid 150 for coffee at Starbucks", "2026-11-23").draft!!.name)
        assertEquals("2 coffees", ConversationParser.parse("Paid 200 for 2 coffees", "2026-11-23").draft!!.name)
        assertEquals("2026-11-22", ConversationParser.parse("Received 5000 from Rahul yesterday", "2026-11-23").draft!!.date)
        assertTrue(ConversationParser.parse("Got 500 from Rahul", "2026-11-23").draft!!.income)
    }

    @Test fun ambiguousOrUnsupportedMessagesAreNotSaved() {
        val engine = LedgerEngine(MemoryStore())
        for (message in listOf("got coffee for 150", "paid 200 got 50 back", "paid 200 at Cafe and 50 at Shop",
            "paid 200 at Cafe on 12/11/2026", "paid 20 at Cafe tomorrow", "paid 200", "", "a".repeat(501))) {
            assertFalse(engine.addConversationEntry("id", message).success, message)
        }
        assertTrue(engine.entries().isEmpty())
        assertTrue(engine.journalMessages().isEmpty())
    }

    @Test fun existingAmountAndNameGuardrailsApplyToBothTypes() {
        val engine = LedgerEngine(MemoryStore())
        for (prefix in listOf("Paid", "Received")) {
            val connector = if (prefix == "Paid") "at" else "from"
            for (amount in listOf("0", "-1", "1.234", "10,00,000.01", "1,23", "999999999999999999999")) {
                assertFalse(engine.addConversationEntry("id", "$prefix $amount $connector Cafe").success, amount)
            }
            assertFalse(engine.addConversationEntry("id", "$prefix 20 $connector ${"A".repeat(121)}").success)
        }
        assertTrue(engine.addConversationEntry("max", "Paid 10,00,000 at Cafe").success)
        assertEquals(100_000_000L, engine.entries().single().paise)
    }

    @Test fun transactionAndHistoryAreAtomicAndSurviveReload() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        store.fail = true
        assertFalse(engine.addConversationEntry("id", "Paid 150 at Cafe").success)
        assertTrue(engine.entries().isEmpty())
        assertTrue(engine.journalMessages().isEmpty())
        store.fail = false
        assertTrue(engine.addConversationEntry("id", "Paid 150 at Cafe").success)
        assertFalse(engine.addConversationEntry("id", "Paid 150 at Cafe").success)
        val reloaded = LedgerEngine(store)
        assertNull(reloaded.loadError)
        assertEquals("Paid 150 at Cafe", reloaded.journalMessages().single().text)
        assertEquals(reloaded.entries().single(), reloaded.journalMessages().single().originalEntry)
        assertTrue(reloaded.editEntry("id", "Coffee", "200", "Food", reloaded.today(), "ios", reloaded.entries().single().capturedAtMillis).success)
        assertEquals("Coffee", reloaded.entries().single().name)
        assertEquals("Cafe", reloaded.journalMessages().single().originalEntry!!.name)
        assertTrue(reloaded.deleteEntry("id").success)
        assertTrue(reloaded.entries().isEmpty())
        assertEquals("id", LedgerEngine(store).journalMessages().single().entryId)
        assertFalse(reloaded.addConversationEntry("id", "Paid 20 at Cafe").success)
    }

    @Test fun manualFormEntriesHaveHistoryWithoutFabricatedMessage() {
        val engine = LedgerEngine(MemoryStore())
        assertTrue(engine.addEntry("manual", "Salary", "100", "Income", engine.today(), true).success)
        assertEquals("", engine.journalMessages().single().text)
        assertEquals("manual", engine.journalMessages().single().entryId)
    }

    @Test fun liveValidationDoesNotRejectIncompleteSentences() {
        val engine = LedgerEngine(MemoryStore())
        assertNull(engine.conversationInputValidationError("Paid"))
        assertEquals("Amount cannot exceed Rs 10,00,000.", engine.conversationInputValidationError("Paid 1000001 at Cafe"))
        assertNotNull(engine.conversationInputValidationError("Received 10.123 from Rahul"))
        assertNull(engine.conversationInputValidationError("Paid 150 at Cafe"))
    }

    @Test fun versionFiveMigratesWithoutChangingExistingEntries() {
        val store = MemoryStore().apply { value = """{"schemaVersion":5,"entries":[]}""" }
        val engine = LedgerEngine(store)
        assertNull(engine.loadError)
        assertTrue(engine.journalMessages().isEmpty())
        assertTrue(engine.addConversationEntry("id", "Received 100 from Rahul").success)
        assertEquals(6, LedgerEngine(store).snapshot.schemaVersion)
    }

    @Test fun rejectedSubmissionsPersistWithoutTransactions() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        val result = engine.submitConversationEntry("rejected", "Paid 1000001 at Cafe")
        assertTrue(result.recorded)
        assertFalse(result.retryable)
        assertEquals("Amount cannot exceed Rs 10,00,000.", result.error)
        assertTrue(engine.entries().isEmpty())
        val restored = LedgerEngine(store)
        assertNull(restored.loadError)
        assertEquals("Paid 1000001 at Cafe", restored.journalMessages().single().text)
        assertNull(restored.journalMessages().single().originalEntry)
        assertTrue(restored.submitConversationEntry("corrected", "Paid 150 at Cafe").recorded)
        assertEquals(2, restored.journalMessages().size)
        assertEquals(1, restored.entries().size)
    }

    @Test fun storageFailureCanRetryTheSameIdWithoutDuplicates() {
        val store = MemoryStore().apply { fail = true }
        val engine = LedgerEngine(store)
        val failed = engine.submitConversationEntry("retry", "Paid 150 at Cafe")
        assertFalse(failed.recorded)
        assertTrue(failed.retryable)
        assertTrue(engine.entries().isEmpty())
        assertTrue(engine.journalMessages().isEmpty())
        store.fail = false
        assertTrue(engine.submitConversationEntry("retry", "Paid 150 at Cafe").recorded)
        assertTrue(engine.submitConversationEntry("retry", "Paid 150 at Cafe").recorded)
        val restored = LedgerEngine(store)
        assertTrue(restored.submitConversationEntry("retry", "Paid 150 at Cafe").recorded)
        assertEquals(1, restored.entries().size)
        assertEquals(1, restored.journalMessages().size)
    }

    @Test fun rejectedMessageWriteFailureDoesNotPretendHistoryWasStored() {
        val store = MemoryStore().apply { fail = true }
        val engine = LedgerEngine(store)
        assertTrue(engine.submitConversationEntry("bad", "nonsense").retryable)
        assertTrue(engine.journalMessages().isEmpty())
        store.fail = false
        val result = engine.submitConversationEntry("bad", "nonsense")
        assertTrue(result.recorded)
        assertFalse(result.retryable)
        assertTrue(result.error.isNotBlank())
        assertTrue(engine.entries().isEmpty())
    }

    @Test fun tooLongInputIsRecordedAsRejectedAndSurvivesReload() {
        val store = MemoryStore()
        val engine = LedgerEngine(store)
        assertTrue(engine.submitConversationEntry("long", "A".repeat(501)).recorded)
        assertNull(LedgerEngine(store).loadError)
        assertTrue(engine.entries().isEmpty())
    }
}
