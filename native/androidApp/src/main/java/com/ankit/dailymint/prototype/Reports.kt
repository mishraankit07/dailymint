package com.ankit.dailymint.prototype

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ankit.dailymint.core.*

@Composable
fun MonthContent(engine: LedgerEngine, revision: Int, onOpenLedger: () -> Unit, onDetail: (Entry) -> Unit) {
    val summary = remember(revision) { engine.monthSummary(engine.today()) }
    BrandHeader("Home")
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = NavColor)
    ) {
        Column(Modifier.padding(20.dp)) {
            Text("Spent this cycle", color = Color(0xffb9c6bc), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text("Rs " + engine.formatAmount(summary.spent), color = HeroText, fontFamily = FontFamily.Serif,
                fontSize = 36.sp, lineHeight = 40.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.testTag("spent"))
            Text(summary.label, color = Color(0xffb9c6bc), fontSize = 12.sp)
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                if (summary.moneyIn > 0) HeroStat("Money in", "Rs " + engine.formatAmount(summary.moneyIn), IncomeGreen, Modifier.testTag("moneyIn"))
                if (summary.invested > 0) HeroStat("Invested", "Rs " + engine.formatAmount(summary.invested), InvestGold)
            }
        }
    }
    if (summary.days.isEmpty()) {
        Text("No transactions in this cycle. Add one manually or let bank messages import.", color = InkSoft)
        OutlinedButton(onClick = onOpenLedger, modifier = Modifier.fillMaxWidth().testTag("seeAllTransactions")) { Text("See all transactions") }
        return
    }
    SectionTitle("Personal spending by category")
    RaisedCard {
        if (summary.categories.isEmpty()) Text("No personal spending yet.", color = InkFaint)
        summary.categories.forEach {
            CategoryBreakdownRow(it.name, it.percent, "Rs " + engine.formatAmount(it.paise))
        }
    }
    SectionTitle("Biggest spends")
    RaisedCard {
        if (summary.topFive.isEmpty()) Text("No personal expenses yet.", color = InkFaint)
        summary.topFive.forEach { TransactionRow(it, engine, onClick = { onDetail(it) }) }
    }
    OutlinedButton(onClick = onOpenLedger, modifier = Modifier.fillMaxWidth().testTag("seeAllTransactions")) { Text("See all transactions") }
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
fun TransactionRow(entry: Entry, engine: LedgerEngine, onClick: (() -> Unit)? = null, tag: String? = null) {
    Row(Modifier.fillMaxWidth().then(if (tag != null) Modifier.testTag(tag) else Modifier)
        .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
        .padding(vertical = 10.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        IconBubble(entry.category)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(entry.name, color = Ink, fontWeight = FontWeight.SemiBold)
            Text((if (entry.type == "income") CreditKind.label(entry.effectiveCreditKind()) else entry.category) + " · " + entry.date.take(10), color = InkFaint, fontSize = 12.sp)
        }
        val displayed = if (entry.type == "expense") entry.personalSpent else entry.paise
        Text((if (entry.type == "income") "+" else "-") + "Rs " + engine.formatAmount(displayed),
            color = if (entry.type == "income") IncomeGreen else if (entry.type == "investment") InvestGold else SpendRed,
            fontWeight = FontWeight.Bold)
    }
    HorizontalDivider(color = Hairline)
}

@Composable
fun GrowthContent(engine: LedgerEngine, revision: Int) {
    var years by remember { mutableStateOf(false) }
    var count by remember { mutableIntStateOf(3) }
    var expanded by remember { mutableStateOf(false) }
    var selected by remember { mutableIntStateOf(-1) }
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
        val colors = listOf(SpendRed, InvestGold)
        Text("Spending trend", color = Ink, fontWeight = FontWeight.Bold)
        Text("Full calendar " + if (years) "years" else "months", color = InkFaint, fontSize = 12.sp)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            FlowLegend("Personal spent", SpendRed)
            FlowLegend("Invested", InvestGold)
        }
        if (buckets.all { it.spent == 0L && it.invested == 0L }) {
            Text("No spending or investments in these periods.", color = InkSoft, modifier = Modifier.padding(vertical = 24.dp))
        } else Canvas(Modifier.fillMaxWidth().height(190.dp).padding(top = 10.dp)
            .pointerInput(buckets) { detectTapGestures { point -> selected = (point.x / (size.width / buckets.size)).toInt().coerceIn(buckets.indices) } }) {
            val maximum = buckets.flatMap { listOf(it.spent, it.invested) }.maxOrNull()?.coerceAtLeast(1) ?: 1
            val groupWidth = size.width / buckets.size.coerceAtLeast(1)
            val clusterWidth = kotlin.math.min(groupWidth * 0.58f, 78f)
            val barGap = clusterWidth * 0.12f
            val barWidth = (clusterWidth - barGap) / 2f
            buckets.forEachIndexed { index, bucket ->
                val clusterStart = index * groupWidth + (groupWidth - clusterWidth) / 2f
                listOf(bucket.spent, bucket.invested).forEachIndexed { series, amount ->
                    val height = (amount.toDouble() / maximum * size.height).toFloat()
                    val x = clusterStart + series * (barWidth + barGap)
                    drawRect(colors[series], Offset(x, size.height - height), Size(barWidth, height))
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            buckets.forEachIndexed { index, bucket ->
                Box(Modifier.weight(1f).clickable { selected = index }, contentAlignment = androidx.compose.ui.Alignment.Center) {
                    Text(bucket.label.takeLast(if (years) 4 else 2), color = InkSoft, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        buckets.getOrNull(selected)?.let { bucket ->
            Text(bucket.label + " · Personal spent Rs " + engine.formatAmount(bucket.spent) +
                " · Invested Rs " + engine.formatAmount(bucket.invested), color = InkSoft,
                style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 12.dp))
        }
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
                    (if (entry.type == "income") CreditKind.all.map(CreditKind::label) else engine.categories()).forEach { option ->
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
