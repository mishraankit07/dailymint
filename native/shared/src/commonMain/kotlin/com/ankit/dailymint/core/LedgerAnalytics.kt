package com.ankit.dailymint.core

import kotlinx.datetime.*
import kotlin.math.roundToInt

internal object LedgerDates {
    val zone = TimeZone.of("Asia/Kolkata")
    fun today(): LocalDate = Clock.System.now().toLocalDateTime(zone).date
    fun dateOrNull(value: String): LocalDate? = try {
        if (value.contains('T')) Instant.parse(value).toLocalDateTime(zone).date else LocalDate.parse(value)
    } catch (_: Exception) { null }
    fun date(value: String): LocalDate = dateOrNull(value) ?: error("Invalid date")
    fun daysInMonth(year: Int, month: Int): Int {
        val next = LocalDate(year, month, 1).plus(DatePeriod(months = 1))
        return next.minus(DatePeriod(days = 1)).dayOfMonth
    }
    fun start(year: Int, month: Int, day: Int): LocalDate = LocalDate(year, month, day.coerceIn(1, daysInMonth(year, month)))
}

data class CategoryTotal(val name: String, val paise: Long, val percent: Double)
data class DayGroup(val date: String, val moneyIn: Long, val moneyOut: Long, val entries: List<Entry>)
data class MonthSummary(
    val start: String, val endExclusive: String, val label: String,
    val moneyIn: Long, val spent: Long, val invested: Long, val remaining: Long,
    val spentPercent: Double?, val savedInvestedPercent: Double?,
    val todaySpend: Long, val weekSpend: Long, val categories: List<CategoryTotal>,
    val topFive: List<Entry>, val days: List<DayGroup>, val neutralCredits: Long = 0,
    val allocationInvestedPercent: Int = -1, val allocationSpentPercent: Int = -1,
    val allocationLeftPercent: Int = -1, val allocationExceedsIncome: Boolean = false
)
data class TrendBucket(val label: String, val moneyIn: Long, val spent: Long, val invested: Long, val savedAndInvested: Long,
    val neutralCredits: Long = 0)

object LedgerAnalytics {
    private fun cycle(entries: List<Entry>, today: String, startDay: Int): Triple<LocalDate, LocalDate, List<Entry>> {
        val now = LedgerDates.date(today)
        var start = LedgerDates.start(now.year, now.monthNumber, startDay)
        if (now < start) {
            val previous = LocalDate(now.year, now.monthNumber, 1).minus(DatePeriod(months = 1))
            start = LedgerDates.start(previous.year, previous.monthNumber, startDay)
        }
        val next = LocalDate(start.year, start.monthNumber, 1).plus(DatePeriod(months = 1))
        val end = LedgerDates.start(next.year, next.monthNumber, startDay)
        return Triple(start, end, entries.filter { val date = LedgerDates.date(it.date); date >= start && date < end })
    }

    fun ledgerDays(entries: List<Entry>, today: String, startDay: Int): List<DayGroup> = cycle(entries, today, startDay).third
        .groupBy { LedgerDates.date(it.date).toString() }
        .map { (date, items) ->
            DayGroup(date,
                items.filter { it.type == "income" }.sumOf { it.paise },
                items.filter { it.type != "income" }.sumOf { it.paise },
                items.sortedWith(compareByDescending<Entry> { it.date }.thenByDescending { it.capturedAtMillis }))
        }
        .sortedByDescending { it.date }

    fun month(entries: List<Entry>, today: String, startDay: Int): MonthSummary {
        val now = LedgerDates.date(today)
        val (start, end, selected) = cycle(entries, today, startDay)
        val moneyIn = selected.sumOf { it.earnedIncome }
        val neutralCredits = selected.sumOf { it.neutralCredit }
        val spent = selected.sumOf { it.personalSpent }
        val invested = selected.filter { it.type == "investment" }.sumOf { it.paise }
        val weekStart = now.minus(DatePeriod(days = now.dayOfWeek.isoDayNumber - 1))
        val weekEnd = weekStart.plus(DatePeriod(days = 7))
        val outflow = spent + invested
        val expenseCategories = selected.filter { it.type == "expense" && it.personalSpent > 0 }.groupBy { it.category }.map { (name, values) ->
            val amount = values.sumOf { it.personalSpent }
            CategoryTotal(name, amount, if (outflow > 0) amount.toDouble() / outflow * 100 else 0.0)
        }
        val investmentCategory = if (invested > 0) listOf(CategoryTotal("Investments", invested, invested.toDouble() / outflow * 100)) else emptyList()
        val categoryTotals = (expenseCategories + investmentCategory)
            .sortedWith(compareBy<CategoryTotal> { it.name == "Miscellaneous" }.thenByDescending { it.paise }.thenBy { it.name })
        val days = selected.groupBy { LedgerDates.date(it.date).toString() }.map { (date, items) ->
            DayGroup(date, items.filter { it.type == "income" }.sumOf { it.paise },
                items.filter { it.type != "income" }.sumOf { it.paise }, items.sortedByDescending { it.paise })
        }.sortedByDescending { it.date }
        return MonthSummary(start.toString(), end.toString(), start.toString() + " - " + end.minus(DatePeriod(days = 1)),
            moneyIn, spent, invested, moneyIn - spent - invested,
            if (moneyIn > 0) spent.toDouble() / moneyIn * 100 else null,
            if (moneyIn > 0) (moneyIn - spent).toDouble() / moneyIn * 100 else null,
            entries.filter { LedgerDates.date(it.date) == now }.sumOf { it.personalSpent },
            entries.filter { val date = LedgerDates.date(it.date); date >= weekStart && date < weekEnd }.sumOf { it.personalSpent },
            categoryTotals, selected.filter { it.type == "expense" && it.personalSpent > 0 }.sortedByDescending { it.personalSpent }.take(5), days,
            neutralCredits,
            if (moneyIn > 0) (invested.toDouble() / moneyIn * 100).roundToInt() else -1,
            if (moneyIn > 0) (spent.toDouble() / moneyIn * 100).roundToInt() else -1,
            if (moneyIn > 0) (maxOf(0L, moneyIn - spent - invested).toDouble() / moneyIn * 100).roundToInt() else -1,
            spent + invested > moneyIn)
    }
    fun trends(entries: List<Entry>, today: String, years: Boolean, count: Int): List<TrendBucket> {
        val allowed = if (years) listOf(1, 2, 3, 5) else listOf(3, 6)
        val safeCount = if (count in allowed) count else allowed.first()
        val now = LedgerDates.date(today)
        return (safeCount - 1 downTo 0).map { offset ->
            val start = if (years) LocalDate(now.year - offset, 1, 1)
                else LocalDate(now.year, now.monthNumber, 1).minus(DatePeriod(months = offset))
            val end = start.plus(if (years) DatePeriod(years = 1) else DatePeriod(months = 1))
            val selected = entries.filter { val date = LedgerDates.date(it.date); date >= start && date < end }
            val moneyIn = selected.sumOf { it.earnedIncome }
            val spent = selected.sumOf { it.personalSpent }
            val invested = selected.filter { it.type == "investment" }.sumOf { it.paise }
            TrendBucket(if (years) start.year.toString() else start.toString().take(7), moneyIn, spent, invested,
                moneyIn - spent, selected.sumOf { it.neutralCredit })
        }
    }
}
