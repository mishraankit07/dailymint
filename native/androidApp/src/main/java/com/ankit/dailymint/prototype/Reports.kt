package com.ankit.dailymint.prototype

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.ankit.dailymint.core.*

@Composable
fun MonthContent(engine: LedgerEngine, revision: Int, onEdit: (Entry) -> Unit, onDebug: (Entry) -> Unit) {
    var detailed by remember { mutableStateOf(false) }
    val summary = remember(revision) { engine.monthSummary(engine.today()) }
    Text(summary.label, style = MaterialTheme.typography.titleMedium)
    Text("Money in: Rs " + engine.formatAmount(summary.moneyIn), Modifier.testTag("moneyIn"))
    Text("Spent: Rs " + engine.formatAmount(summary.spent), Modifier.testTag("spent"))
    Text("Invested: Rs " + engine.formatAmount(summary.invested))
    Text("Remaining: Rs " + engine.formatAmount(summary.remaining))
    HorizontalDivider()
    Text("Money split", style = MaterialTheme.typography.titleLarge)
    for ((name, percent) in listOf("Spent" to summary.spentPercent, "Saved/Invested" to summary.savedInvestedPercent)) {
        val good = if (name == "Spent") (percent ?: 0.0) <= 80 else (percent ?: 0.0) >= 20
        Text(name + ": " + (percent?.let { kotlin.math.round(it).toInt().toString() + "%" } ?: "--"))
        LinearProgressIndicator(progress = { ((percent ?: 0.0) / 100).toFloat().coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth(), color = if (good) Color(0xff15803d) else Color(0xffb91c1c))
    }
    Text("Target 20%", style = MaterialTheme.typography.labelSmall)
    Text("Outflow breakdown", style = MaterialTheme.typography.titleLarge)
    summary.categories.forEach {
        Text(it.name + " · " + kotlin.math.round(it.percent).toInt() + "% · Rs " + engine.formatAmount(it.paise))
    }
    Text("Top 5 transactions", style = MaterialTheme.typography.titleLarge)
    summary.topFive.forEach { TransactionRow(it, engine) }
    OutlinedButton(onClick = { detailed = !detailed }, modifier = Modifier.testTag("detailedReport")) { Text(if (detailed) "Collapse" else "Detailed report") }
    if (detailed) summary.days.forEach { day ->
        Text(day.date + " · In Rs " + engine.formatAmount(day.moneyIn) + " · Out Rs " + engine.formatAmount(day.moneyOut), style = MaterialTheme.typography.titleSmall)
        day.entries.forEach { entry ->
            TransactionRow(entry, engine)
            Row {
                if (engine.canEdit(entry.id, "android", System.currentTimeMillis())) TextButton(onClick = { onEdit(entry) }) { Text("Edit") }
                if (entry.rawSms.isNotEmpty()) TextButton(onClick = { onDebug(entry) }) { Text("Debug") }
            }
        }
    }
}

@Composable
fun TransactionRow(entry: Entry, engine: LedgerEngine) {
    ListItem(headlineContent = { Text(entry.name) }, supportingContent = { Text(entry.category + " · " + entry.date.take(10)) },
        trailingContent = { Text((if (entry.type == "income") "+" else "-") + "Rs " + engine.formatAmount(entry.paise)) })
    HorizontalDivider()
}

@Composable
fun GrowthContent(engine: LedgerEngine, revision: Int) {
    var years by remember { mutableStateOf(false) }
    var count by remember { mutableIntStateOf(3) }
    var expanded by remember { mutableStateOf(false) }
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
    Text("Money movement", style = MaterialTheme.typography.titleLarge)
    val colors = listOf(Color(0xff15803d), Color(0xffe11d48), Color(0xff2563eb))
    Text("Money in · Spent · Invested")
    Canvas(Modifier.fillMaxWidth().height(180.dp)) {
        val maximum = buckets.flatMap { listOf(it.moneyIn, it.spent, it.invested) }.maxOrNull()?.coerceAtLeast(1) ?: 1
        val group = size.width / buckets.size
        buckets.forEachIndexed { index, bucket ->
            listOf(bucket.moneyIn, bucket.spent, bucket.invested).forEachIndexed { series, amount ->
                val height = (amount.toDouble() / maximum * size.height).toFloat()
                drawRect(colors[series], Offset(index * group + series * group / 4, size.height - height), Size(group / 5, height))
            }
        }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { buckets.forEach { Text(it.label.takeLast(if (years) 4 else 2), style = MaterialTheme.typography.labelSmall) } }
    Text("Money in, spending and investments across calendar periods.", style = MaterialTheme.typography.bodySmall)
    Text("Wealth Progress", style = MaterialTheme.typography.titleLarge)
    Canvas(Modifier.fillMaxWidth().height(180.dp)) {
        val min = minOf(0L, buckets.minOf { it.wealth })
        val max = maxOf(1L, buckets.maxOf { it.wealth })
        fun point(index: Int): Offset = Offset(if (buckets.size == 1) size.width / 2 else index * size.width / (buckets.size - 1),
            size.height - ((buckets[index].wealth - min).toDouble() / (max - min) * size.height).toFloat())
        for (index in 1 until buckets.size) drawLine(Color(0xff15803d), point(index - 1), point(index), 4f)
        buckets.indices.forEach { drawCircle(Color(0xff15803d), 5f, point(it)) }
    }
    Text("Remaining money in bank plus investment.", style = MaterialTheme.typography.bodySmall)
    buckets.forEach { Text(it.label + " · Rs " + engine.formatAmount(it.wealth)) }
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

