package com.ankit.dailymint.prototype

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.ankit.dailymint.core.*

@Composable
fun LedgerContent(
    engine: LedgerEngine,
    revision: Int,
    smsError: String,
    onDetail: (Entry) -> Unit,
    onUnrecognized: (ReviewRow) -> Unit,
    modifier: Modifier = Modifier
) {
    var search by rememberSaveable { mutableStateOf("") }
    var from by rememberSaveable { mutableStateOf("") }
    var to by rememberSaveable { mutableStateOf("") }
    var type by rememberSaveable { mutableStateOf("All") }
    var category by rememberSaveable { mutableStateOf("All categories") }
    var pageSize by rememberSaveable { mutableIntStateOf(50) }
    var showActivity by rememberSaveable { mutableStateOf(false) }
    var categoryMenu by remember { mutableStateOf(false) }
    LaunchedEffect(search, from, to, type, category) { pageSize = 50 }

    val all = remember(revision) { engine.entries().sortedWith(compareByDescending<Entry> { it.date.take(10) }.thenByDescending { it.capturedAtMillis }) }
    val filtered = all.filter { entry ->
        (search.isBlank() || entry.name.contains(search.trim(), ignoreCase = true)) &&
            (from.isBlank() || entry.date.take(10) >= from.trim()) &&
            (to.isBlank() || entry.date.take(10) <= to.trim()) &&
            (type == "All" || when (type) {
                "Expenses" -> entry.type == "expense" && !entry.ignored
                "Investments" -> entry.type == "investment" && !entry.ignored
                "Credits" -> entry.type == "income" && !entry.ignored
                else -> entry.ignored
            }) &&
            (category == "All categories" || entry.category == category)
    }
    val visible = filtered.take(pageSize)
    val dayTotals = filtered.groupBy { it.date.take(10) }

    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        BrandHeader("Ledger")
        OutlinedTextField(search, { search = it }, label = { Text("Search transactions") }, singleLine = true,
            modifier = Modifier.fillMaxWidth().testTag("ledgerSearch"))
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("All", "Expenses", "Investments", "Credits", "Ignored").forEach { option ->
                FilterChip(selected = type == option, onClick = { type = option }, label = { Text(option) })
            }
        }
        Box {
            OutlinedButton(onClick = { categoryMenu = true }) { Text(category) }
            DropdownMenu(categoryMenu, onDismissRequest = { categoryMenu = false }) {
                (listOf("All categories") + engine.categories() + CreditKind.all.map(CreditKind::label)).distinct().forEach { option ->
                    DropdownMenuItem(text = { Text(option) }, onClick = { category = option; categoryMenu = false })
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(from, { from = it }, label = { Text("From YYYY-MM-DD") }, singleLine = true,
                modifier = Modifier.weight(1f).testTag("ledgerFrom"))
            OutlinedTextField(to, { to = it }, label = { Text("To YYYY-MM-DD") }, singleLine = true,
                modifier = Modifier.weight(1f).testTag("ledgerTo"))
        }
        OutlinedButton(onClick = { showActivity = !showActivity }, modifier = Modifier.fillMaxWidth().testTag("importActivity")) {
            Text(if (showActivity) "Hide import activity" else "Import activity")
        }
        if (showActivity) {
            RaisedCard {
                SectionTitle("Automatic SMS scan")
                Text(if (smsError.isNotEmpty()) smsError else "Bank messages are scanned when SMS access is available.", color = InkSoft)
                val unrecognized = engine.unrecognizedMessages()
                if (unrecognized.isNotEmpty()) {
                    SectionTitle("Unrecognized", trailing = unrecognized.size.toString())
                    unrecognized.takeLast(20).forEachIndexed { index, row ->
                        TextButton(onClick = { onUnrecognized(row) }, modifier = Modifier.fillMaxWidth()) {
                            Text("View message ${index + 1}")
                        }
                    }
                }
            }
        }
        if (all.isEmpty()) {
            Text("No transactions yet. Add one manually or allow SMS access to import bank messages.", color = InkSoft)
        } else if (filtered.isEmpty()) {
            Text("No transactions match these filters.", color = InkSoft)
            OutlinedButton(onClick = { search = ""; from = ""; to = ""; type = "All"; category = "All categories" }) {
                Text("Clear filters")
            }
        } else {
            visible.groupBy { it.date.take(10) }.forEach { (date, entries) ->
                RaisedCard {
                    val active = dayTotals.getValue(date).filterNot { it.ignored }
                    val grossIn = active.filter { it.type == "income" }.sumOf { it.paise }
                    val grossOut = active.filter { it.type != "income" }.sumOf { it.paise }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(date, color = Ink, fontWeight = FontWeight.Bold)
                        Text("In Rs ${engine.formatAmount(grossIn)} · Out Rs ${engine.formatAmount(grossOut)}", color = InkFaint,
                            style = MaterialTheme.typography.bodySmall)
                    }
                    entries.forEach { entry ->
                        TransactionRow(entry, engine, onClick = { onDetail(entry) }, tag = "ledgerRow-${entry.id}")
                        if (entry.ignored) Text("Ignored", color = InkFaint, style = MaterialTheme.typography.labelSmall)
                        else if (entry.type == "expense" && entry.personalSpent != entry.paise) {
                            Text("Bank Rs ${engine.formatAmount(entry.paise)} · Personal Rs ${engine.formatAmount(entry.personalSpent)}",
                                color = InkSoft, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            if (filtered.size > visible.size) {
                OutlinedButton(onClick = { pageSize += 50 }, modifier = Modifier.fillMaxWidth().testTag("loadMoreLedger")) {
                    Text("Load more")
                }
            }
        }
    }
}

@Composable
fun TransactionDetail(
    id: String,
    engine: LedgerEngine,
    revision: Int,
    onDismiss: () -> Unit,
    onChanged: () -> Unit,
    onManualEdit: (Entry) -> Unit
) {
    val entry = remember(id, revision) { engine.entries().find { it.id == id } } ?: return
    var showOriginal by remember(id) { mutableStateOf(false) }
    var share by remember(id, revision) { mutableStateOf(engine.formatAmount(entry.personalSpent)) }
    var name by remember(id, revision) { mutableStateOf(entry.name) }
    var category by remember(id, revision) { mutableStateOf(entry.category) }
    var categoryMenu by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    fun apply(result: SaveResult) {
        error = result.message
        if (result.success) onChanged()
    }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(entry.name) },
        text = {
            Column(Modifier.heightIn(max = 500.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Date: ${entry.date.take(10)}")
                Text("Source: ${if (entry.source == "manual") "Manual" else "Bank SMS / file"}")
                Text("Original amount: Rs ${engine.formatAmount(entry.paise)}", modifier = Modifier.testTag("originalAmount"))
                if (entry.type == "expense") Text("Personal spending: Rs ${engine.formatAmount(entry.personalSpent)}",
                    modifier = Modifier.testTag("personalAmount"))
                Text("Category: ${if (entry.type == "income") CreditKind.label(entry.effectiveCreditKind()) else entry.category}")
                if (entry.ignored) Text("Ignored: excluded from all totals", color = InkSoft)
                if (entry.source != "manual" && entry.type == "expense") {
                    HorizontalDivider()
                    Text("Count as my expense", fontWeight = FontWeight.SemiBold)
                    Text("Only this amount counts in Home, Growth, and category spending. The bank amount stays unchanged.",
                        color = InkSoft, style = MaterialTheme.typography.bodySmall)
                    OutlinedTextField(share, { share = it }, label = { Text("Personal amount") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth().testTag("personalShare"))
                    Button(onClick = { apply(engine.setPersonalExpense(id, share)) }, modifier = Modifier.testTag("savePersonalShare")) {
                        Text("Save personal amount")
                    }
                    TextButton(onClick = { apply(engine.setPersonalExpense(id, engine.formatAmount(entry.paise))) }) {
                        Text("Count full amount")
                    }
                }
                if (entry.type == "income") {
                    HorizontalDivider()
                    Text("Credit kind", fontWeight = FontWeight.SemiBold)
                    CreditKind.all.forEach { kind ->
                        FilterChip(selected = entry.effectiveCreditKind() == kind,
                            onClick = { apply(engine.classifyCredit(id, kind)) },
                            label = { Text(CreditKind.label(kind)) },
                            modifier = Modifier.testTag("creditKind-$kind"))
                    }
                    Text("Settlements and own-account transfers do not change spending or earned income.",
                        color = InkSoft, style = MaterialTheme.typography.bodySmall)
                }
                if (entry.source != "manual" && entry.type != "income") {
                    HorizontalDivider()
                    Text("Correct classification", fontWeight = FontWeight.SemiBold)
                    OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth().testTag("correctedName"))
                    Box {
                        OutlinedButton(onClick = { categoryMenu = true }) { Text(category) }
                        DropdownMenu(categoryMenu, onDismissRequest = { categoryMenu = false }) {
                            engine.categories().forEach { option ->
                                DropdownMenuItem(text = { Text(option) }, onClick = { category = option; categoryMenu = false })
                            }
                        }
                    }
                    Button(onClick = { apply(engine.correctImported(id, name, category)) }, modifier = Modifier.testTag("saveClassification")) {
                        Text("Save classification")
                    }
                }
                if (entry.source == "manual" && engine.canEdit(id, "android", System.currentTimeMillis())) {
                    TextButton(onClick = { onDismiss(); onManualEdit(entry) }) { Text("Edit manual entry") }
                }
                if (entry.source != "manual") {
                    TextButton(onClick = { apply(engine.setIgnored(id, !entry.ignored)) }, modifier = Modifier.testTag("toggleIgnored")) {
                        Text(if (entry.ignored) "Restore transaction" else "Ignore false positive")
                    }
                }
                if (entry.rawSms.isNotEmpty()) {
                    TextButton(onClick = { showOriginal = !showOriginal }, modifier = Modifier.testTag("viewOriginalMessage")) {
                        Text(if (showOriginal) "Hide original message" else "View original message")
                    }
                    if (showOriginal) {
                        Text("From: ${entry.sender}", color = InkSoft)
                        Text(entry.rawSms, color = InkSoft)
                    }
                }
                if (error.isNotEmpty()) Text(error, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("detailError"))
            }
        }, confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } })
}
