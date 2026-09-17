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
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = NavColor)
    ) {
        Column(Modifier.padding(20.dp)) {
            Text("Remaining this month", color = Color(0xffb9c6bc), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text("Rs " + engine.formatAmount(summary.remaining), color = HeroText, fontFamily = FontFamily.Serif,
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
    MoneySplitCard(summary)
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
        Text(value, color = HeroText, fontWeight = FontWeight.Bold, fontSize = 13.sp)
    }
}

@Composable
private fun MoneySplitCard(summary: MonthSummary) {
    val moneyIn = summary.moneyIn.coerceAtLeast(1).toDouble()
    val investedPercent = if (summary.moneyIn > 0) summary.invested.toDouble() / moneyIn * 100 else 0.0
    val spentPercent = summary.spentPercent ?: 0.0
    val remainingPercent = (100.0 - spentPercent - investedPercent).coerceAtLeast(0.0)
    RaisedCard {
        Row(
            Modifier
                .fillMaxWidth()
                .height(14.dp)
                .background(Hairline, RoundedCornerShape(8.dp))
        ) {
            if (investedPercent > 0) Spacer(Modifier.fillMaxHeight().weight(investedPercent.toFloat()).background(InvestGold))
            if (spentPercent > 0) Spacer(Modifier.fillMaxHeight().weight(spentPercent.toFloat()).background(SpendRed))
            if (remainingPercent > 0) Spacer(Modifier.fillMaxHeight().weight(remainingPercent.toFloat()))
        }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            SplitLegend("Invested", investedPercent, InvestGold)
            SplitLegend("Spent", spentPercent, SpendRed)
            SplitLegend("Remaining", remainingPercent, Hairline)
        }
    }
}

@Composable
private fun SplitLegend(name: String, percent: Double, color: Color) {
    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Spacer(Modifier.size(8.dp).background(color, RoundedCornerShape(99.dp)))
        Spacer(Modifier.width(5.dp))
        Text("$name · ${kotlin.math.round(percent).toInt()}%", color = InkSoft, fontSize = 12.sp)
    }
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
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        IconBubble(entry.category)
        Spacer(Modifier.width(12.dp))
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
    RaisedCard {
        val colors = listOf(IncomeGreen, SpendRed, InvestGold)
        Text(if (years) "Yearly flow" else "Monthly flow", color = Ink, fontWeight = FontWeight.Bold)
        Text("Money in vs. spent vs. invested", color = InkFaint, fontSize = 12.sp)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            FlowLegend("In", IncomeGreen)
            FlowLegend("Spent", SpendRed)
            FlowLegend("Invested", InvestGold)
        }
        Canvas(Modifier.fillMaxWidth().height(190.dp).padding(top = 10.dp)) {
            val maximum = buckets.flatMap { listOf(it.moneyIn, it.spent, it.invested) }.maxOrNull()?.coerceAtLeast(1) ?: 1
            val groupWidth = size.width / buckets.size.coerceAtLeast(1)
            val clusterWidth = kotlin.math.min(groupWidth * 0.58f, 78f)
            val barGap = clusterWidth * 0.12f
            val barWidth = (clusterWidth - barGap * 2) / 3f
            buckets.forEachIndexed { index, bucket ->
                val clusterStart = index * groupWidth + (groupWidth - clusterWidth) / 2f
                listOf(bucket.moneyIn, bucket.spent, bucket.invested).forEachIndexed { series, amount ->
                    val height = (amount.toDouble() / maximum * size.height).toFloat()
                    val x = clusterStart + series * (barWidth + barGap)
                    drawRect(colors[series], Offset(x, size.height - height), Size(barWidth, height))
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            buckets.forEach {
                Text(
                    it.label.takeLast(if (years) 4 else 2),
                    color = InkSoft,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        Text("Money in, spending and investments across calendar periods.", color = InkSoft, style = MaterialTheme.typography.bodySmall)
    }
    RaisedCard {
        Text("Wealth Progress", color = Ink, fontWeight = FontWeight.Bold)
        Text("Remaining money in bank plus investment", color = InkFaint, fontSize = 12.sp)
        Spacer(Modifier.height(8.dp))
        val lineColor = IncomeGreen
        Canvas(Modifier.fillMaxWidth().height(190.dp)) {
            val min = minOf(0L, buckets.minOf { it.wealth })
            val max = maxOf(1L, buckets.maxOf { it.wealth })
            fun point(index: Int): Offset = Offset(if (buckets.size == 1) size.width / 2 else index * size.width / (buckets.size - 1),
                size.height - ((buckets[index].wealth - min).toDouble() / (max - min) * size.height).toFloat())
            for (index in 1 until buckets.size) drawLine(lineColor, point(index - 1), point(index), 4f)
            buckets.indices.forEach { drawCircle(lineColor, 5f, point(it)) }
        }
        Text("Remaining money in bank plus investment.", color = InkSoft, style = MaterialTheme.typography.bodySmall)
        buckets.forEach { Text(it.label + " · Rs " + engine.formatAmount(it.wealth), color = InkSoft) }
    }
}

@Composable
private fun FlowLegend(name: String, color: Color) {
    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Spacer(Modifier.size(8.dp).background(color, RoundedCornerShape(99.dp)))
        Spacer(Modifier.width(5.dp))
        Text(name, color = InkSoft, fontSize = 12.sp)
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
