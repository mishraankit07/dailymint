package com.ankit.fendyourspend.core

import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.minus
import kotlinx.serialization.Serializable

@Serializable
data class JournalMessage(val entryId: String, val text: String, val originalEntry: Entry? = null,
    val error: String = "", val createdAtMillis: Long = 0)

data class ConversationSubmitResult(val recorded: Boolean, val retryable: Boolean, val error: String)

data class ConversationDraft(val name: String, val amount: String, val income: Boolean, val date: String)
data class ConversationParseResult(val draft: ConversationDraft? = null, val error: String? = null)

/** Deliberately separate from bank-SMS recognition: only explicit single-entry commands are accepted. */
object ConversationParser {
    fun parse(message: String, today: String): ConversationParseResult {
        fun failure(text: String) = ConversationParseResult(error = text)
        if (message.length > 500) return failure("Keep your message within 500 characters.")
        var text = message.trim().replace(Regex("\\s+"), " ")
        val date = LedgerDates.dateOrNull(today) ?: return failure("Choose a valid transaction date.")
        val yesterday = Regex("\\s+yesterday$", RegexOption.IGNORE_CASE).containsMatchIn(text)
        text = text.replace(Regex("\\s+(today|yesterday)$", RegexOption.IGNORE_CASE), "")
        val pattern = Regex(
            "^(?:I )?(spent|spend|paid|pay|gave|received|receive|got)\\s+(?:(?:Rs\\.?|INR|₹)\\s*)?([+-]?[0-9][0-9,.]*)(?:\\s+(?:rupees|Rs\\.?|INR))?\\s+(at|to|from|for)\\s+(.+)$",
            RegexOption.IGNORE_CASE
        )
        val match = pattern.matchEntire(text)
            ?: return failure("Try 'Paid 150 at Starbucks' or 'Received 5000 from Rahul'.")
        val (verb, amount, connector, remainder) = match.destructured
        val income = verb.lowercase() in setOf("received", "receive", "got")
        if ((income && !connector.equals("from", true)) || (!income && connector.equals("from", true))) {
            return failure("Use 'received ... from' for credits, or 'paid ... at/to/for' for expenses.")
        }
        if (Regex("\\b(spent|spend|paid|pay|gave|received|receive|got|tomorrow)\\b|\\b(?:and|plus|minus|on)\\s+[0-9]|[₹]|\\b(?:Rs|INR)\\b", RegexOption.IGNORE_CASE).containsMatchIn(remainder)) {
            return failure("Enter one transaction at a time. Use the form for other dates or complex entries.")
        }
        val merchant = if (!income && connector.equals("for", true))
            remainder.split(Regex("\\s+at\\s+", RegexOption.IGNORE_CASE)).last() else remainder
        return ConversationParseResult(draft = ConversationDraft(
            merchant.trim(), amount, income,
            (if (yesterday) date.minus(1, DateTimeUnit.DAY) else date).toString()
        ))
    }
}
