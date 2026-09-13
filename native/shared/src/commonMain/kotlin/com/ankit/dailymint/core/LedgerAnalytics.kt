package com.ankit.dailymint.core

import kotlinx.datetime.*

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
    val topFive: List<Entry>, val days: List<DayGroup>
)
data class TrendBucket(val label: String, val moneyIn: Long, val spent: Long, val invested: Long, val wealth: Long)

object LedgerAnalytics {
    fun month(entries: List<Entry>, today: String, startDay: Int): MonthSummary {
        val now = LedgerDates.date(today)
        var start = LedgerDates.start(now.year, now.monthNumber, startDay)
        if (now < start) {
            val previous = LocalDate(now.year, now.monthNumber, 1).minus(DatePeriod(months = 1))
            start = LedgerDates.start(previous.year, previous.monthNumber, startDay)
        }
        val next = LocalDate(start.year, start.monthNumber, 1).plus(DatePeriod(months = 1))
        val end = LedgerDates.start(next.year, next.monthNumber, startDay)
        val selected = entries.filter { val date = LedgerDates.date(it.date); date >= start && date < end }
        val moneyIn = selected.filter { it.type == "income" }.sumOf { it.paise }
        val spent = selected.filter { it.type == "expense" }.sumOf { it.paise }
        val invested = selected.filter { it.type == "investment" }.sumOf { it.paise }
        val out = spent + invested
        val weekStart = now.minus(DatePeriod(days = now.dayOfWeek.isoDayNumber - 1))
        val weekEnd = weekStart.plus(DatePeriod(days = 7))
        val categoryTotals = selected.filter { it.type != "income" }.groupBy { it.category }.map { (name, values) ->
            val amount = values.sumOf { it.paise }
            CategoryTotal(name, amount, if (out > 0) amount.toDouble() / out * 100 else 0.0)
        }.sortedWith(compareBy<CategoryTotal> { it.name == "Miscellaneous" }.thenByDescending { it.paise }.thenBy { it.name })
        val days = selected.groupBy { LedgerDates.date(it.date).toString() }.map { (date, items) ->
            DayGroup(date, items.filter { it.type == "income" }.sumOf { it.paise },
                items.filter { it.type != "income" }.sumOf { it.paise }, items.sortedByDescending { it.paise })
        }.sortedByDescending { it.date }
        return MonthSummary(start.toString(), end.toString(), start.toString() + " - " + end.minus(DatePeriod(days = 1)),
            moneyIn, spent, invested, moneyIn - spent - invested,
            if (moneyIn > 0) spent.toDouble() / moneyIn * 100 else null,
            if (moneyIn > 0) (moneyIn - spent).toDouble() / moneyIn * 100 else null,
            entries.filter { it.type != "income" && LedgerDates.date(it.date) == now }.sumOf { it.paise },
            entries.filter { val date = LedgerDates.date(it.date); it.type != "income" && date >= weekStart && date < weekEnd }.sumOf { it.paise },
            categoryTotals, selected.filter { it.type != "income" }.sortedByDescending { it.paise }.take(5), days)
    }
    fun trends(entries: List<Entry>, today: String, years: Boolean, count: Int): List<TrendBucket> {
        val allowed = if (years) listOf(1, 2, 3, 5) else listOf(3, 6)
        require(count in allowed)
        val now = LedgerDates.date(today)
        var cumulative = 0L
        return (count - 1 downTo 0).map { offset ->
            val start = if (years) LocalDate(now.year - offset, 1, 1)
                else LocalDate(now.year, now.monthNumber, 1).minus(DatePeriod(months = offset))
            val end = start.plus(if (years) DatePeriod(years = 1) else DatePeriod(months = 1))
            val selected = entries.filter { val date = LedgerDates.date(it.date); date >= start && date < end }
            val moneyIn = selected.filter { it.type == "income" }.sumOf { it.paise }
            val spent = selected.filter { it.type == "expense" }.sumOf { it.paise }
            val invested = selected.filter { it.type == "investment" }.sumOf { it.paise }
            cumulative += moneyIn - spent
            TrendBucket(if (years) start.year.toString() else start.toString().take(7), moneyIn, spent, invested, cumulative)
        }
    }
}

