package com.ankit.dailymint.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.datetime.Clock

// A non-null result lets Swift implement the throwing Objective-C protocol method.
// A null snapshot means no saved file; read failures must still throw.
data class LedgerRead(val snapshot: String?)

interface LedgerStore {
    @Throws(Exception::class) fun load(): LedgerRead
    @Throws(Exception::class) fun save(snapshot: String)
}

@Serializable
data class Entry(val id: String, val name: String, val paise: Long, val category: String, val date: String, val type: String,
    val source: String = "manual", val capturedAtMillis: Long = 0,
    val rawSms: String = "", val sender: String = "", val referenceId: String = "", val bank: String = "")

@Serializable
data class ReviewRow(val id: String, val entry: Entry? = null, val status: String, val rawText: String = "", val reason: String = "")

@Serializable
data class IncomingSms(val id: String, val body: String, val sender: String, val timestamp: Long)

@Serializable
data class Snapshot(
    val schemaVersion: Int = 1,
    val categories: List<String> = listOf("Home", "Groceries", "Food", "Fun", "Gym", "Self", "Investments", "Miscellaneous"),
    val entries: List<Entry> = emptyList(),
    val learnedRules: Map<String, String> = emptyMap(),
    val monthStartDay: Int = 1,
    val reminderEnabled: Boolean = false,
    val reminderTime: String = "21:30",
    val review: List<ReviewRow> = emptyList(),
    val reviewFile: String = "",
    val smsWatermark: Long = 0,
    val unrecognized: List<ReviewRow> = emptyList()
)

data class SaveResult(val success: Boolean, val message: String)
data class Totals(val moneyIn: Long, val spent: Long, val invested: Long) {
    val remaining: Long get() = moneyIn - spent - invested
}

object Money {
    // Integer paise avoids floating-point rounding; bounded values keep aggregate arithmetic safe.
    private const val MAX_PAISE = 100_000_000_000L
    fun parse(value: String): Long? {
        val text = value.trim()
        if (!Regex("^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+|[0-9]{1,2}(?:,[0-9]{2})*,[0-9]{3})(?:\\.[0-9]{1,2})?$").matches(text)) return null
        val parts = text.replace(",", "").split('.')
        val whole = parts[0].toLongOrNull() ?: return null
        if (whole > MAX_PAISE / 100) return null
        val result = whole * 100 + (parts.getOrNull(1)?.padEnd(2, '0')?.toLongOrNull() ?: 0)
        return result.takeIf { it in 1..MAX_PAISE }
    }
    fun display(paise: Long): String {
        val absolute = if (paise < 0) -paise else paise
        val fraction = absolute % 100
        return (if (paise < 0) "-" else "") + (absolute / 100) +
            (if (fraction == 0L) "" else "." + fraction.toString().padStart(2, '0'))
    }
}

object ReminderCopy {
    private val quotes = listOf(
        "Tiny records become real clarity.",
        "A two-minute check-in keeps the month honest.",
        "What gets noticed gets easier to improve.",
        "Keep the habit small enough to keep.",
        "Small habits make money clearer."
    )
    fun quoteForDay(daySeed: Int): String = quotes[((daySeed % quotes.size) + quotes.size) % quotes.size]
}

class LedgerEngine(private val store: LedgerStore) {
    internal var snapshot = Snapshot()
        private set
    var loadError: String? = null
        private set
    init {
        try {
            store.load().snapshot?.let {
                val loaded = Json.decodeFromString<Snapshot>(it)
                require(loaded.schemaVersion == 1)
                require(loaded.categories.contains("Miscellaneous"))
                require(loaded.categories.map(String::lowercase).distinct().size == loaded.categories.size)
                require(loaded.entries.size <= 100_000)
                require(loaded.entries.map { entry -> entry.id }.distinct().size == loaded.entries.size)
                require(loaded.entries.all { entry ->
                    entry.paise in 1..100_000_000_000L && validDate(entry.date) &&
                        entry.type in listOf("income", "expense", "investment")
                })
                snapshot = loaded
            }
        } catch (_: Exception) {
            loadError = "Could not read your saved ledger. Your data has not been replaced."
        }
    }
    fun categories(): List<String> = snapshot.categories
    fun entries(): List<Entry> = snapshot.entries
    fun reviewRows(): List<ReviewRow> = snapshot.review
    fun reviewFile(): String = snapshot.reviewFile
    fun monthStartDay(): Int = snapshot.monthStartDay
    fun reminderEnabled(): Boolean = snapshot.reminderEnabled
    fun reminderTime(): String = snapshot.reminderTime
    fun reminderQuote(daySeed: Int): String = ReminderCopy.quoteForDay(daySeed)
    fun smsWatermark(): Long = snapshot.smsWatermark
    fun unrecognizedMessages(): List<ReviewRow> = snapshot.unrecognized
    fun stageWal(text: String, fileName: String): SaveResult {
        if (snapshot.review.any { it.status == "new" }) return SaveResult(false, "Save or discard the current import first.")
        if (text.length > 5_000_000) return SaveResult(false, "This file is too large. Import a daily transaction file.")
        val rows = TransactionImport.rows(text, snapshot, Clock.System.now().toEpochMilliseconds())
        return commit(snapshot.copy(review = rows, reviewFile = fileName))
    }
    fun discardReview(): SaveResult = commit(snapshot.copy(review = emptyList(), reviewFile = ""))
    fun saveReview(): SaveResult {
        val ids = snapshot.entries.map { it.id }.toMutableSet()
        val newEntries = snapshot.review.filter { it.status == "new" }.mapNotNull { it.entry }.filter { ids.add(it.id) }
        return commit(snapshot.copy(entries = snapshot.entries + newEntries, review = emptyList(), reviewFile = ""))
    }
    fun editReview(id: String, name: String, amount: String, category: String): SaveResult {
        val row = snapshot.review.find { it.id == id && it.status == "new" } ?: return SaveResult(false, "This record is already recorded.")
        val entry = row.entry ?: return SaveResult(false, "This message could not be parsed.")
        val error = validateEntry(name, amount, category, entry.date, entry.type == "income")
        if (error != null) return SaveResult(false, error)
        val updated = entry.copy(name = name.trim(), paise = Money.parse(amount)!!, category = category, type = entryType(entry.type == "income", category))
        return commit(snapshot.copy(review = snapshot.review.map { if (it.id == id) it.copy(entry = updated) else it }, learnedRules = learn(name, category)))
    }
    fun importMessages(json: String): SaveResult {
        val messages = try { Json.decodeFromString<List<IncomingSms>>(json) } catch (_: Exception) { return SaveResult(false, "Could not read incoming messages.") }
        return importMessages(messages)
    }
    fun importSingleMessage(id: String, body: String, sender: String, timestamp: Long): SaveResult =
        importMessages(listOf(IncomingSms(id, body, sender, timestamp)))
    private fun importMessages(messages: List<IncomingSms>): SaveResult {
        val ids = snapshot.entries.map { it.id }.toMutableSet()
        val entries = snapshot.entries.toMutableList()
        val unknown = snapshot.unrecognized.toMutableList()
        var watermark = snapshot.smsWatermark
        for (message in messages.sortedBy { it.timestamp }) {
            val date = try { kotlinx.datetime.Instant.fromEpochMilliseconds(message.timestamp).toString() } catch (_: Exception) { return SaveResult(false, "Invalid message date.") }
            val row = TransactionImport.sms(message.body, message.sender, date, Clock.System.now().toEpochMilliseconds(), snapshot)
            row.entry?.let { if (ids.add(it.id)) entries.add(it) }
            if (row.status == "unrecognized" && unknown.none { it.id == message.id }) unknown.add(row.copy(id = message.id))
            watermark = maxOf(watermark, message.timestamp)
        }
        return commit(snapshot.copy(entries = entries, smsWatermark = watermark, unrecognized = unknown.takeLast(50)))
    }
    fun today(): String = LedgerDates.today().toString()
    fun suggestCategory(name: String, income: Boolean): String = MerchantTagger.category(name, income, snapshot.learnedRules, snapshot.categories)
    fun monthSummary(today: String): MonthSummary = LedgerAnalytics.month(snapshot.entries, today, snapshot.monthStartDay)
    fun trendBuckets(today: String, years: Boolean, count: Int): List<TrendBucket> = LedgerAnalytics.trends(snapshot.entries, today, years, count)
    fun canEdit(id: String, platform: String, nowMillis: Long): Boolean {
        val entry = snapshot.entries.find { it.id == id } ?: return false
        return (entry.source == "manual" || platform == "android") && entry.capturedAtMillis > 0 &&
            nowMillis - entry.capturedAtMillis in 0..86_400_000L
    }
    fun setMonthStartDay(day: Int): SaveResult = if (day in 1..31) commit(snapshot.copy(monthStartDay = day)) else SaveResult(false, "Choose a day from 1 to 31.")
    fun setReminder(enabled: Boolean, time: String): SaveResult {
        if (!Regex("^([01][0-9]|2[0-3]):[0-5][0-9]$").matches(time)) return SaveResult(false, "Choose a valid reminder time.")
        return commit(snapshot.copy(reminderEnabled = enabled, reminderTime = time))
    }
    fun deleteCategory(name: String): SaveResult {
        if (name == "Miscellaneous" || name !in snapshot.categories) return SaveResult(false, "This category cannot be deleted.")
        fun remap(entry: Entry): Entry = if (entry.category == name) entry.copy(category = "Miscellaneous", type = if (entry.type == "income") "income" else "expense") else entry
        return commit(snapshot.copy(categories = snapshot.categories - name,
            entries = snapshot.entries.map(::remap), learnedRules = snapshot.learnedRules.filterValues { it != name },
            review = snapshot.review.map { it.copy(entry = it.entry?.let(::remap)) }))
    }
    fun editEntry(id: String, name: String, amount: String, category: String, date: String, platform: String, nowMillis: Long): SaveResult {
        if (!canEdit(id, platform, nowMillis)) return SaveResult(false, "This transaction is no longer editable.")
        val old = snapshot.entries.first { it.id == id }
        val error = validateEntry(name, amount, category, date, old.type == "income")
        if (error != null) return SaveResult(false, error)
        val updated = old.copy(name = name.trim(), paise = Money.parse(amount)!!, category = category, date = date, type = entryType(old.type == "income", category))
        return commit(snapshot.copy(entries = snapshot.entries.map { if (it.id == id) updated else it }, learnedRules = learn(name, category)))
    }
    fun deleteEntry(id: String, platform: String, nowMillis: Long): SaveResult {
        if (!canEdit(id, platform, nowMillis)) return SaveResult(false, "This transaction is no longer editable.")
        return commit(snapshot.copy(entries = snapshot.entries.filter { it.id != id }))
    }
    private fun learn(name: String, category: String): Map<String, String> {
        val key = MerchantTagger.learningKey(name)
        return if (key.isNotEmpty() && category in snapshot.categories && category != "Miscellaneous") snapshot.learnedRules + (key to category) else snapshot.learnedRules
    }
    private fun entryType(income: Boolean, category: String): String = if (income) "income" else if (category == "Investments") "investment" else "expense"
    private fun validateEntry(name: String, amount: String, category: String, date: String, income: Boolean): String? {
        if (Money.parse(amount) == null) return "Enter a positive amount with up to two decimal places."
        if (name.trim().isEmpty() || name.trim().length > 120) return "Enter a name between 1 and 120 characters."
        if (!validDate(date)) return "Choose a valid transaction date."
        if (category !in (if (income) listOf("Salary", "Received") else snapshot.categories)) return "Choose a valid category."
        return null
    }
    fun formatAmount(paise: Long): String = Money.display(paise)
    fun totals(): Totals = Totals(
        snapshot.entries.filter { it.type == "income" }.sumOf { it.paise },
        snapshot.entries.filter { it.type == "expense" }.sumOf { it.paise },
        snapshot.entries.filter { it.type == "investment" }.sumOf { it.paise }
    )
    fun addCategory(rawName: String): SaveResult {
        val name = rawName.trim().replace(Regex("\\s+"), " ")
        if (name.isBlank() || name.length > 40) return SaveResult(false, "Enter a category name between 1 and 40 characters.")
        if ((snapshot.categories + listOf("Salary", "Received")).any { it.equals(name, true) })
            return SaveResult(false, "This category already exists.")
        return commit(snapshot.copy(categories = snapshot.categories + name))
    }
    fun addEntry(id: String, name: String, amount: String, category: String, date: String, income: Boolean): SaveResult {
        val paise = Money.parse(amount) ?: return SaveResult(false, "Enter a positive amount with up to two decimal places.")
        if (id.isBlank() || snapshot.entries.any { it.id == id }) return SaveResult(false, "This record already exists.")
        if (name.trim().isEmpty() || name.trim().length > 120) return SaveResult(false, "Enter a name between 1 and 120 characters.")
        if (!validDate(date)) return SaveResult(false, "Choose a valid transaction date.")
        val allowed = if (income) listOf("Salary", "Received") else snapshot.categories
        if (category !in allowed) return SaveResult(false, "Choose a valid category.")
        if (snapshot.entries.size >= 100_000) return SaveResult(false, "Ledger capacity reached.")
        val type = if (income) "income" else if (category == "Investments") "investment" else "expense"
        return commit(snapshot.copy(entries = snapshot.entries + Entry(id, name.trim(), paise, category, date, type, capturedAtMillis = Clock.System.now().toEpochMilliseconds()), learnedRules = learn(name, category)))
    }
    internal fun commit(next: Snapshot): SaveResult {
        loadError?.let { return SaveResult(false, it) }
        if (next.entries.size > 100_000) return SaveResult(false, "Ledger capacity reached.")
        return try {
            store.save(Json.encodeToString(next))
            snapshot = next
            SaveResult(true, "")
        } catch (_: Exception) {
            SaveResult(false, "Could not save. Please try again.")
        }
    }
}

private fun validDate(value: String): Boolean {
    if (value.contains('T')) return LedgerDates.dateOrNull(value) != null
    if (!Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(value)) return false
    val parts = value.split('-').map { it.toInt() }
    val (year, month, day) = parts
    if (year !in 1900..9999 || month !in 1..12) return false
    val leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    val days = listOf(31, if (leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    return day in 1..days[month - 1]
}
