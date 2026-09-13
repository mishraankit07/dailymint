package com.ankit.dailymint.core

import kotlinx.datetime.*

object TransactionImport {
    private val envelope = Regex("""current_date:\s*(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})\s+at\s+(\d{1,2}):(\d{2})(?::(\d{2}))?[ \t]*(AM|PM)?(?:[ \t]+(IST|UTC|GMT))?""", RegexOption.IGNORE_CASE)
    private val months = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
    private fun date(match: MatchResult): String? = try {
        val g = match.groupValues
        val month = months.indexOf(g[2].lowercase().take(3)) + 1
        var hour = g[4].toInt()
        if (g[7].isNotEmpty()) {
            require(hour in 1..12)
            hour = hour % 12 + if (g[7].equals("PM", true)) 12 else 0
        }
        LocalDateTime(g[3].toInt(), month, g[1].toInt(), hour, g[5].toInt(), g[6].ifEmpty { "0" }.toInt())
            .toInstant(if (g[8].uppercase() in listOf("UTC", "GMT")) TimeZone.UTC else LedgerDates.zone).toString()
    } catch (_: Exception) { null }
    fun rows(text: String, snapshot: Snapshot, captureMillis: Long): List<ReviewRow> {
        val normalized = text.replace("\r\n", "\n").replace("\\r", "\n").trim()
        if (normalized.isEmpty()) return emptyList()
        val matches = envelope.findAll(normalized).toList()
        if (matches.isEmpty()) return listOf(ReviewRow("unrecognized", status = "unrecognized", rawText = normalized, reason = "missing_current_date"))
        val seen = snapshot.entries.map { it.id }.toMutableSet()
        return matches.mapIndexed { index, match ->
            val raw = normalized.substring(match.range.last + 1, matches.getOrNull(index + 1)?.range?.first ?: normalized.length).trim()
            val timestamp = date(match)
            if (timestamp == null) ReviewRow("invalid-$index", status = "unrecognized", rawText = raw, reason = "invalid_date")
            else {
                val row = sms(raw, "", timestamp, captureMillis, snapshot)
                if (row.entry == null) row.copy(id = "message-$index")
                else {
                    val existing = snapshot.entries.find { it.id == row.entry.id }
                    val status = if (existing != null) "already-recorded" else if (!seen.add(row.entry.id)) "repeated" else "new"
                    row.copy(id = "row-$index", entry = existing ?: row.entry, status = status)
                }
            }
        }
    }
    fun sms(raw: String, sender: String, date: String, capturedAt: Long, snapshot: Snapshot): ReviewRow {
        val parsed = BankSmsParser.parse(raw, sender, 75)
        if (!parsed.parsed) {
            val ignored = parsed.reason in listOf("otp", "future_debit", "card_payment_ack", "reward_offer", "no_transaction_keyword")
            return ReviewRow("", status = if (ignored) "ignored" else "unrecognized", rawText = raw, reason = parsed.reason ?: "not_parsed")
        }
        val income = parsed.direction == "credit"
        val counterparty = if (income) parsed.from ?: parsed.to else parsed.to ?: parsed.from
        val name = MerchantTagger.cleanName(counterparty ?: if (income) "UPI credit" else parsed.bank ?: "Unknown")
        val category = MerchantTagger.category(name, income, snapshot.learnedRules, snapshot.categories)
        val account = if (income) parsed.to else parsed.from
        val tail = Regex("""(\d{3,4})\b""").find(account.orEmpty())?.value.orEmpty()
        // Reference identity does not depend on automation execution time or editable merchant/category.
        val identity = listOf(parsed.bank.orEmpty(), tail, parsed.direction.orEmpty(),
            parsed.referenceId ?: (date + "|" + raw.replace(Regex("""\s+"""), " ").trim())).joinToString("|")
        val id = "bank-" + stableHash(identity)
        val entry = Entry(id, name, parsed.paise!!, category, date,
            if (income) "income" else if (category == "Investments") "investment" else "expense",
            "bank-wal", capturedAt, raw, sender, parsed.referenceId.orEmpty(), parsed.bank.orEmpty())
        return ReviewRow(id, entry, "new", raw)
    }
    private fun stableHash(text: String): String {
        // Two independent 32-bit FNV passes make the identifier deterministic on Kotlin/JVM and Native.
        fun hash(seed: UInt): String {
            var value = seed
            text.forEach { value = (value xor it.code.toUInt()) * 16777619u }
            return value.toString(16).padStart(8, '0')
        }
        return hash(2166136261u) + hash(2246822519u)
    }
}

