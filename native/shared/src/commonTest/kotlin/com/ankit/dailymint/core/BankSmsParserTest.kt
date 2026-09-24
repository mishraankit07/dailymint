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

    @Test fun indusIndMaskedFormatsKeepReferencesAndSafeLedgerNames() {
        val debitSms = "Your IndusInd Account 15XXXXX1234 has been debited for INR 501 towards IMPS/900000000023. Call 18602677777 to report issue-IndusInd Bank"
        val creditSms = "IndusInd A/C Credited; INR 500.00 Ref-SAOAO900000000000000001.Bal INR 500.00.Dispute-Call 18602677777-IndusInd Bank"

        val debit = BankSmsParser.parse(debitSms)
        assertTrue(debit.parsed)
        assertEquals("IndusInd Account 15XXXXX1234", debit.from)
        assertEquals("IMPS", debit.to)
        assertEquals("900000000023", debit.referenceId)

        val credit = BankSmsParser.parse(creditSms)
        assertTrue(credit.parsed)
        assertNull(credit.from)
        assertNull(credit.to)
        assertEquals("SAOAO900000000000000001", credit.referenceId)

        val debitEntry = TransactionImport.sms(
            debitSms, "", "2026-09-24T10:00:00Z", 1, Snapshot()
        ).entry!!
        val creditEntry = TransactionImport.sms(
            creditSms, "", "2026-09-24T10:01:00Z", 2, Snapshot()
        ).entry!!
        assertEquals("IMPS", debitEntry.name)
        assertEquals("UPI credit", creditEntry.name)
        assertEquals(50100, debitEntry.paise)
        assertEquals(50000, creditEntry.paise)
    }
}
