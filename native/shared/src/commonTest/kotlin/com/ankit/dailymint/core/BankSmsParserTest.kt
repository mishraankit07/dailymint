package com.ankit.dailymint.core

import kotlin.test.*

data class SmsFixture(val id: String, val sms: String, val parsed: Boolean, val paise: Long?,
    val direction: String?, val from: String?, val to: String?, val bank: String?, val reason: String?)

class BankSmsParserTest {
    @Test fun allExistingBankFixturesHaveIdenticalOutputs() {
        for (fixture in SmsFixtures.values) {
            val result = BankSmsParser.parse(fixture.sms)
            assertEquals(fixture.parsed, result.parsed, fixture.id)
            if (fixture.parsed) {
                assertEquals(fixture.paise, result.paise, fixture.id + " amount")
                assertEquals(fixture.direction, result.direction, fixture.id + " direction")
                assertEquals(fixture.from, result.from, fixture.id + " from")
                assertEquals(fixture.to, result.to, fixture.id + " to")
                assertEquals(fixture.bank, result.bank, fixture.id + " bank")
            } else assertEquals(fixture.reason, result.reason, fixture.id)
        }
    }
    @Test fun taggingPreservesCreditDirection() {
        val categories = Snapshot().categories
        assertEquals("Settlement", MerchantTagger.category("Zomato refund", true, emptyMap(), categories))
        assertEquals("Income", MerchantTagger.category("Employer payroll", true, emptyMap(), categories))
        assertEquals("Own account transfer", MerchantTagger.category("Own account transfer", true, emptyMap(), categories))
        assertEquals("Groceries", MerchantTagger.category("cf.zepto12@bank", false, emptyMap(), categories))
        assertEquals("Self", MerchantTagger.category("yesmadam", false, emptyMap(), categories))
        assertEquals("Home", MerchantTagger.category("urban company", false, emptyMap(), categories))
        assertEquals("Travel", MerchantTagger.category("merchant123", false, mapOf("merchant" to "Travel"), categories + "Travel"))
        assertEquals("Miscellaneous", MerchantTagger.category("merchant123", false, mapOf("merchant" to "Travel"), categories))
        assertEquals("merchant", MerchantTagger.learningKey("merchant.123@bank"))
    }
}
