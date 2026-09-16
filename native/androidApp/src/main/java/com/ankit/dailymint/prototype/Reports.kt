package com.ankit.dailymint.prototype

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ankit.dailymint.core.*

@Composable
fun MonthContent(engine: LedgerEngine, revision: Int, onEdit: (Entry) -> Unit, onDebug: (Entry) -> Unit) {
    var detailed by remember { mutableStateOf(false) }
    val summary = remember(revision) { engine.monthSummary(engine.today()) }
    BrandHeader("Good evening")
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = Ink)
    ) {
        Column(Modifier.padding(20.dp)) {
            Text("Remaining this month", color = Color(0xffb9c6bc), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text("Rs " + engine.formatAmount(summary.remaining), color = Paper, fontFamily = FontFamily.Serif,
                fontSize = 36.sp, lineHeight = 40.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                HeroStat("Money in", "Rs " + engine.formatAmount(summary.moneyIn), IncomeGreen, Modifier.testTag("moneyIn"))
                HeroStat("Spent", "Rs " + engine.formatAmount(summary.spent), SpendRed, Modifier.testTag("spent"))
                HeroStat("Invested", "Rs " + engine.formatAmount(summary.invested), InvestGold)
            }
        }
    }
    SectionTitle("Where it went", trailing = summary.label)
    RaisedCard {
        SplitLine("Spent", summary.spentPercent, SpendRed)
        Spacer(Modifier.height(8.dp))
        SplitLine("Saved/Invested", summary.savedInvestedPercent, IncomeGreen)
        Text("Target 20%", color = InkFaint, fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp))
    }
    SectionTitle("Outflow breakdown")
    RaisedCard {
        if (summary.categories.isEmpty()) Text("No outflow yet.", color = InkFaint)
        summary.categories.forEach {
            CategoryBreakdownRow(it.name, it.percent, "Rs " + engine.formatAmount(it.paise))
        }
    }
    SectionTitle("Top 5 transactions")
    RaisedCard {
        if (summary.topFive.isEmpty()) Text("No transactions yet.", color = InkFaint)
        summary.topFive.forEach { TransactionRow(it, engine) }
    }
    OutlinedButton(onClick = { detailed = !detailed }, modifier = Modifier.fillMaxWidth().testTag("detailedReport")) { Text(if (detailed) "Collapse" else "Detailed report") }
    if (detailed) {
        SectionTitle("Detailed report")
        summary.days.forEach { day ->
            RaisedCard {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(day.date, color = Ink, fontWeight = FontWeight.Bold)
                    Text("In Rs " + engine.formatAmount(day.moneyIn) + " · Out Rs " + engine.formatAmount(day.moneyOut), color = InkFaint, fontSize = 12.sp)
                }
                day.entries.forEach { entry ->
                    TransactionRow(entry, engine)
                    Row {
                        if (engine.canEdit(entry.id, "android", System.currentTimeMillis())) TextButton(onClick = { onEdit(entry) }) { Text("Edit") }
                        if (entry.rawSms.isNotEmpty()) TextButton(onClick = { onDebug(entry) }) { Text("Debug") }
                    }
                }
            }
        }
    }
}

@Composable
private fun HeroStat(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}) {
        Row {
            Spacer(Modifier.size(8.dp).background(color, RoundedCornerShape(99.dp)))
            Spacer(Modifier.width(6.dp))
            Text(label, color = Color(0xffb9c6bc), fontSize = 12.sp)
        }
        Text(value, color = Paper, fontWeight = FontWeight.Bold, fontSize = 13.sp)
    }
}

@Composable
private fun SplitLine(name: String, percent: Double?, color: Color) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(name, color = Ink, fontWeight = FontWeight.SemiBold)
        Text(percent?.let { kotlin.math.round(it).toInt().toString() + "%" } ?: "--", color = InkSoft)
    }
    LinearProgressIndicator(
        progress = { ((percent ?: 0.0) / 100).toFloat().coerceIn(0f, 1f) },
        modifier = Modifier.fillMaxWidth().height(8.dp),
        color = color,
        trackColor = Hairline
    )
}

@Composable
private fun CategoryBreakdownRow(name: String, percent: Double, amount: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp)) {
        Text(name, color = Ink, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, modifier = Modifier.width(92.dp))
        LinearProgressIndicator(
            progress = { (percent / 100).toFloat().coerceIn(0f, 1f) },
            modifier = Modifier.weight(1f).height(8.dp),
            color = categoryColor(name),
            trackColor = Hairline
        )
        Text(amount, color = InkSoft, fontSize = 12.sp, modifier = Modifier.width(86.dp).padding(start = 10.dp))
    }
}

@Composable
fun TransactionRow(entry: Entry, engine: LedgerEngine) {
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
        Column(Modifier.weight(1f)) {
            Text(entry.name, color = Ink, fontWeight = FontWeight.SemiBold)
            Text(entry.category + " · " + entry.date.take(10), color = InkFaint, fontSize = 12.sp)
        }
        Text((if (entry.type == "income") "+" else "-") + "Rs " + engine.formatAmount(entry.paise),
            color = if (entry.type == "income") IncomeGreen else SpendRed, fontWeight = FontWeight.Bold)
    }
    HorizontalDivider(color = Hairline)
}

@Composable
fun GrowthContent(engine: LedgerEngine, revision: Int) {
    var years by remember { mutableStateOf(false) }
    var count by remember { mutableIntStateOf(3) }
    var expanded by remember { mutableStateOf(false) }
    BrandHeader("Growth")
    Row {
        FilterChip(selected = !years, onClick = { years = false; count = 3 }, label = { Text("Months") })
        Spacer(Modifier.width(8.dp))
        FilterChip(selected = years, onClick = { years = true; count = 1 }, label = { Text("Years") })
        Spacer(Modifier.width(8.dp))
        Box {
            OutlinedButton(onClick = { expanded = true }) { Text("$count " + if (years) "years" else "months") }
            DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
                (if (years) listOf(1, 2, 3, 5) else listOf(3, 6)).forEach { option ->
                    DropdownMenuItem(text = { Text("$option " + if (years) "years" else "months") },
                        onClick = { count = option; expanded = false })
                }
            }
        }
    }
    val buckets = remember(revision, count, years) { engine.trendBuckets(engine.today(), years, count) }
    SectionTitle("Money movement")
    RaisedCard {
        val colors = listOf(IncomeGreen, SpendRed, InvestGold)
        Text("Money in · Spent · Invested", color = InkSoft, fontSize = 13.sp)
        Canvas(Modifier.fillMaxWidth().height(190.dp).padding(top = 10.dp)) {
            val maximum = buckets.flatMap { listOf(it.moneyIn, it.spent, it.invested) }.maxOrNull()?.coerceAtLeast(1) ?: 1
            val group = size.width / buckets.size.coerceAtLeast(1)
            buckets.forEachIndexed { index, bucket ->
                listOf(bucket.moneyIn, bucket.spent, bucket.invested).forEachIndexed { series, amount ->
                    val height = (amount.toDouble() / maximum * size.height).toFloat()
                    drawRect(colors[series], Offset(index * group + series * group / 4, size.height - height), Size(group / 5, height))
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { buckets.forEach { Text(it.label.takeLast(if (years) 4 else 2), color = InkFaint, fontSize = 11.sp) } }
        Text("Money in, spending and investments across calendar periods.", color = InkSoft, style = MaterialTheme.typography.bodySmall)
    }
    SectionTitle("Wealth Progress")
    RaisedCard {
        Canvas(Modifier.fillMaxWidth().height(190.dp)) {
            val min = minOf(0L, buckets.minOf { it.wealth })
            val max = maxOf(1L, buckets.maxOf { it.wealth })
            fun point(index: Int): Offset = Offset(if (buckets.size == 1) size.width / 2 else index * size.width / (buckets.size - 1),
                size.height - ((buckets[index].wealth - min).toDouble() / (max - min) * size.height).toFloat())
            for (index in 1 until buckets.size) drawLine(IncomeGreen, point(index - 1), point(index), 4f)
            buckets.indices.forEach { drawCircle(IncomeGreen, 5f, point(it)) }
        }
        Text("Remaining money in bank plus investment.", color = InkSoft, style = MaterialTheme.typography.bodySmall)
        buckets.forEach { Text(it.label + " · Rs " + engine.formatAmount(it.wealth), color = InkSoft) }
    }
}

@Composable
fun EntryEditor(entry: Entry, engine: LedgerEngine, onDismiss: () -> Unit, onChanged: () -> Unit) {
    var name by remember(entry.id) { mutableStateOf(entry.name) }
    var amount by remember(entry.id) { mutableStateOf(engine.formatAmount(entry.paise)) }
    var category by remember(entry.id) { mutableStateOf(entry.category) }
    var expanded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    var confirmDelete by remember { mutableStateOf(false) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Edit transaction") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(name, { name = it }, label = { Text("Name") })
            OutlinedTextField(amount, { amount = it }, label = { Text("Amount") },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal))
            Box {
                OutlinedButton(onClick = { expanded = true }) { Text(category) }
                DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
                    (if (entry.type == "income") listOf("Salary", "Received") else engine.categories()).forEach { option ->
                        DropdownMenuItem(text = { Text(option) }, onClick = { category = option; expanded = false })
                    }
                }
            }
            if (error.isNotEmpty()) Text(error, color = MaterialTheme.colorScheme.error)
            TextButton(onClick = { confirmDelete = true }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
        }
    }, confirmButton = { TextButton(onClick = {
        val result = engine.editEntry(entry.id, name, amount, category, entry.date, "android", System.currentTimeMillis())
        if (result.success) { onChanged(); onDismiss() } else error = result.message
    }) { Text("Save") } }, dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text("Delete transaction?") },
        confirmButton = { TextButton(onClick = {
            val result = engine.deleteEntry(entry.id, "android", System.currentTimeMillis())
            if (result.success) { onChanged(); onDismiss() } else { error = result.message; confirmDelete = false }
        }) { Text("Delete") } }, dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } })
}
