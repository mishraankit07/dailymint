package com.ankit.dailymint.prototype

import android.os.Bundle
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.ankit.dailymint.core.*
import java.time.LocalDate
import java.util.UUID

class PreferenceStore(context: Context) : LedgerStore {
    private val preferences = context.getSharedPreferences("native-ledger-v1", Context.MODE_PRIVATE)
    override fun load() = com.ankit.dailymint.core.LedgerRead(preferences.getString("snapshot", null))
    override fun save(snapshot: String) {
        check(preferences.edit().putString("snapshot", snapshot).commit()) { "Save failed" }
    }
}

class MainActivity : ComponentActivity() {
    private lateinit var engine: LedgerEngine
    private lateinit var smsReader: SmsReader
    private var externalRevision by mutableIntStateOf(0)
    private var scanning = false
    private var rescanRequested = false
    private var smsError by mutableStateOf("")
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) { smsError = ""; smsReader.start(); scanMessages() }
        else smsError = "Allow SMS access to capture bank transactions automatically."
    }
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) ReminderScheduler.apply(this, engine)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        engine = LedgerEngine(PreferenceStore(this))
        smsReader = SmsReader(this) { scanMessages() }
        setContent {
            DailyMintTheme {
                DailyMint(engine, externalRevision, smsError,
                    requestSms = { permission.launch(android.Manifest.permission.READ_SMS) },
                    requestNotifications = { requestNotificationPermission() })
            }
        }
        if (!smsReader.allowed()) permission.launch(android.Manifest.permission.READ_SMS)
    }
    override fun onResume() { super.onResume(); if (::smsReader.isInitialized) { smsReader.start(); scanMessages() } }
    override fun onPause() { if (::smsReader.isInitialized) smsReader.stop(); super.onPause() }
    private fun scanMessages() {
        if (!smsReader.allowed()) return
        if (scanning) { rescanRequested = true; return }
        scanning = true
        lifecycleScope.launch {
            try {
                val since = engine.smsWatermark().takeIf { it > 0 } ?: (System.currentTimeMillis() - 30L * 86400000)
                val json = withContext(Dispatchers.IO) { smsReader.read(since) }
                val result = engine.importMessages(json)
                smsError = if (result.success) "" else result.message
                if (result.success) externalRevision++
            } catch (_: Exception) { smsError = "Could not read bank messages. Please try again." }
            finally { scanning = false; if (rescanRequested) { rescanRequested = false; scanMessages() } }
        }
    }
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        notificationPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
    }
}

@Composable
fun DailyMintTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Ink,
            secondary = Flow,
            tertiary = InvestGold,
            background = Paper,
            surface = Paper,
            surfaceVariant = PaperRaised,
            onPrimary = Paper,
            onSecondary = Paper,
            onBackground = Ink,
            onSurface = Ink,
            outline = Hairline,
            error = SpendRed
        ),
        content = content
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DailyMint(engine: LedgerEngine, externalRevision: Int = 0, smsError: String = "", requestSms: () -> Unit = {}, requestNotifications: () -> Unit = {}) {
    val context = LocalContext.current
    var revision by remember { mutableIntStateOf(0) }
    var tab by remember { mutableIntStateOf(0) }
    var showCategory by remember { mutableStateOf(false) }
    var categoryName by remember { mutableStateOf("") }
    var categoryError by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var income by remember { mutableStateOf(false) }
    var category by remember { mutableStateOf("Miscellaneous") }
    var categoryMenu by remember { mutableStateOf(false) }
    var date by remember { mutableStateOf(LocalDate.now().toString()) }
    var entryError by remember { mutableStateOf("") }
    var saved by remember { mutableStateOf(false) }
    var edited by remember { mutableStateOf<Entry?>(null) }
    var debug by remember { mutableStateOf<Entry?>(null) }
    var unrecognizedDebug by remember { mutableStateOf<ReviewRow?>(null) }
    var deletingCategory by remember { mutableStateOf<String?>(null) }
    var monthMenu by remember { mutableStateOf(false) }
    var settingsError by remember { mutableStateOf("") }
    val categories = remember(revision, externalRevision) { engine.categories() }

    Scaffold(
        containerColor = Paper,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("DailyMint", color = Ink, fontWeight = FontWeight.Bold)
                        Text("Know your flow", color = InkFaint, style = MaterialTheme.typography.labelMedium)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Paper),
                actions = {
                    IconButton(onClick = { tab = if (tab == 4) 0 else 4 }) {
                        Icon(if (tab == 4) Icons.Default.Close else Icons.Default.Settings, contentDescription = if (tab == 4) "Close settings" else "Settings", tint = Ink)
                    }
                }
            )
        },
        bottomBar = {
            NavigationBar(containerColor = PaperRaised, tonalElevation = 0.dp) {
                listOf(
                    NavItem("Month", Icons.Default.CalendarMonth),
                    NavItem("Growth", Icons.AutoMirrored.Filled.ShowChart),
                    NavItem("Manual", Icons.Default.AddCircle),
                    NavItem("Plan", Icons.Default.Flag)
                ).forEachIndexed { index, item ->
                    NavigationBarItem(
                        selected = tab == index,
                        onClick = { tab = index },
                        icon = { Icon(item.icon, contentDescription = item.title) },
                        label = { Text(item.title) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = Paper,
                            selectedTextColor = Ink,
                            indicatorColor = Ink,
                            unselectedIconColor = InkFaint,
                            unselectedTextColor = InkFaint
                        )
                    )
                }
            }
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                engine.loadError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                if (smsError.isNotEmpty()) { Text(smsError); TextButton(onClick = requestSms) { Text("Allow SMS access") } }
                when (tab) {
                    0 -> MonthContent(engine, revision + externalRevision, onEdit = { edited = it }, onDebug = { debug = it })
                    1 -> GrowthContent(engine, revision + externalRevision)
                    3 -> {
                        BrandHeader("Plan")
                        RaisedCard {
                            Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                                Icon(Icons.Default.Flag, contentDescription = null, tint = Flow, modifier = Modifier.size(74.dp))
                            }
                            Text("Coming soon", color = Ink, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.headlineSmall)
                            Text("Plan a goal, set aside money, and watch the gap close over time.", color = InkSoft, style = MaterialTheme.typography.bodyMedium)
                            Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    CategoryDot("Investment")
                                    Spacer(Modifier.width(8.dp))
                                    Text("Goal planning", color = InkFaint, fontWeight = FontWeight.SemiBold)
                                }
                                Text("Soon", color = Flow, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                    2 -> {
                        BrandHeader("Add transaction")
                        RaisedCard {
                            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                                listOf("Expense", "Income").forEachIndexed { index, label ->
                                    SegmentedButton(selected = income == (index == 1),
                                        onClick = { income = index == 1; category = if (income) "Received" else "Miscellaneous" },
                                        shape = SegmentedButtonDefaults.itemShape(index, 2)) { Text(label) }
                                }
                            }
                            Spacer(Modifier.height(12.dp))
                            OutlinedTextField(name, { name = it; category = engine.suggestCategory(it, income) }, label = { Text("Name") }, singleLine = true,
                                modifier = Modifier.fillMaxWidth().testTag("entryName"))
                            OutlinedTextField(amount, { amount = it }, label = { Text("Amount") }, singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                modifier = Modifier.fillMaxWidth().testTag("entryAmount"))
                            Box {
                                OutlinedButton(onClick = { categoryMenu = true }, modifier = Modifier.testTag("entryCategory")) { Text(category) }
                                DropdownMenu(expanded = categoryMenu, onDismissRequest = { categoryMenu = false }) {
                                    (if (income) listOf("Salary", "Received") else categories).forEach { option ->
                                        DropdownMenuItem(text = { Text(option) }, onClick = { category = option; categoryMenu = false })
                                    }
                                }
                            }
                            OutlinedTextField(date, { date = it }, label = { Text("Date (YYYY-MM-DD)") }, singleLine = true,
                                modifier = Modifier.fillMaxWidth().testTag("entryDate"))
                            if (entryError.isNotEmpty()) Text(entryError, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("entryError"))
                            Button(onClick = {
                                val result = engine.addEntry(UUID.randomUUID().toString(), name, amount, category, date, income)
                                entryError = result.message
                                if (result.success) {
                                    revision++; name = ""; amount = ""; category = if (income) "Received" else "Miscellaneous"; saved = true
                                }
                            }, enabled = engine.loadError == null, modifier = Modifier.fillMaxWidth().testTag("saveEntry")) { Text("Save") }
                        }
                    }
                    4 -> {
                        BrandHeader("Settings")
                        var reminderMenu by remember { mutableStateOf(false) }
                        RaisedCard {
                            SectionTitle("Daily check-in")
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Column {
                                    Text("Expense reminder", color = Ink, fontWeight = FontWeight.SemiBold)
                                    Text(if (engine.reminderEnabled()) "Reminder on" else "Reminder off",
                                        color = InkFaint, style = MaterialTheme.typography.bodySmall)
                                }
                                Switch(checked = engine.reminderEnabled(), onCheckedChange = { enabled ->
                                    val result = engine.setReminder(enabled, engine.reminderTime())
                                    settingsError = result.message
                                    if (result.success) {
                                        revision++
                                        if (enabled) requestNotifications()
                                        ReminderScheduler.apply(context, engine)
                                    }
                                }, modifier = Modifier.testTag("reminderToggle"))
                            }
                            Spacer(Modifier.height(10.dp))
                            Box {
                                OutlinedButton(onClick = { reminderMenu = true }, modifier = Modifier.testTag("reminderTime")) {
                                    Text("Reminder time: " + engine.reminderTime())
                                }
                                DropdownMenu(reminderMenu, onDismissRequest = { reminderMenu = false }) {
                                    listOf("20:00", "20:30", "21:00", "21:30", "22:00").forEach { time ->
                                        DropdownMenuItem(text = { Text(time) }, onClick = {
                                            val result = engine.setReminder(engine.reminderEnabled(), time)
                                            settingsError = result.message
                                            if (result.success) {
                                                revision++
                                                reminderMenu = false
                                                ReminderScheduler.apply(context, engine)
                                            }
                                        })
                                    }
                                }
                            }
                        }
                        RaisedCard {
                            SectionTitle("Tracking cycle")
                            Box {
                                OutlinedButton(onClick = { monthMenu = true }) { Text("Starts on date: " + engine.monthStartDay()) }
                                DropdownMenu(monthMenu, onDismissRequest = { monthMenu = false }) {
                                    (1..31).forEach { day -> DropdownMenuItem(text = { Text(day.toString()) }, onClick = {
                                        val result = engine.setMonthStartDay(day)
                                        settingsError = result.message
                                        if (result.success) { revision++; monthMenu = false }
                                    }) }
                                }
                            }
                        }
                        if (settingsError.isNotEmpty()) Text(settingsError, color = MaterialTheme.colorScheme.error)
                        RaisedCard {
                            SectionTitle("Categories")
                            OutlinedButton(
                                onClick = { categoryName = ""; categoryError = ""; showCategory = true },
                                modifier = Modifier.fillMaxWidth().testTag("addCategory")
                            ) {
                                Icon(Icons.Default.Add, contentDescription = "Add category", tint = Ink)
                                Spacer(Modifier.width(8.dp))
                                Text("Add category")
                            }
                            categories.forEach { categoryName -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Row {
                                    Spacer(Modifier.width(9.dp).height(9.dp).background(categoryColor(categoryName), androidx.compose.foundation.shape.RoundedCornerShape(99.dp)))
                                    Spacer(Modifier.width(8.dp))
                                    Text(categoryName, color = Ink)
                                }
                                if (categoryName != "Miscellaneous") IconButton(onClick = { deletingCategory = categoryName }) { Icon(Icons.Default.Close, contentDescription = "Delete " + categoryName, tint = SpendRed) }
                            } }
                        }
                        val unrecognized = engine.unrecognizedMessages()
                        if (unrecognized.isNotEmpty()) {
                            RaisedCard {
                                SectionTitle("Unrecognized messages", trailing = unrecognized.size.toString())
                                unrecognized.takeLast(10).forEachIndexed { index, row ->
                                    OutlinedButton(onClick = { unrecognizedDebug = row }, modifier = Modifier.fillMaxWidth()) {
                                        Text("View message " + (index + 1) + if (row.reason.isNotEmpty()) " · " + row.reason else "")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    edited?.let { EntryEditor(it, engine, onDismiss = { edited = null }, onChanged = { revision++ }) }
    debug?.let { entry -> AlertDialog(onDismissRequest = { debug = null }, title = { Text("Message details") },
        text = { Text("From: " + entry.sender + "\nDate: " + entry.date + "\n\n" + entry.rawSms) },
        confirmButton = { TextButton(onClick = { debug = null }) { Text("Close") } }) }
    unrecognizedDebug?.let { row -> AlertDialog(onDismissRequest = { unrecognizedDebug = null }, title = { Text("Unrecognized message") },
        text = { Text((if (row.reason.isNotEmpty()) "Reason: " + row.reason + "\n\n" else "") + row.rawText) },
        confirmButton = { TextButton(onClick = { unrecognizedDebug = null }) { Text("Close") } }) }
    deletingCategory?.let { categoryName -> AlertDialog(onDismissRequest = { deletingCategory = null },
        title = { Text("Delete " + categoryName + "?") }, text = { Text("Transactions in this category will move to Miscellaneous.") },
        confirmButton = { TextButton(onClick = {
            val result = engine.deleteCategory(categoryName)
            settingsError = result.message
            if (result.success) { revision++; if (category == categoryName) category = "Miscellaneous"; deletingCategory = null }
        }) { Text("Delete") } }, dismissButton = { TextButton(onClick = { deletingCategory = null }) { Text("Cancel") } }) }
    if (showCategory) {
        AlertDialog(onDismissRequest = { showCategory = false },
            title = { Text("Add category") },
            text = {
                Column {
                    OutlinedTextField(categoryName, { categoryName = it }, label = { Text("Category name") },
                        singleLine = true, modifier = Modifier.testTag("categoryName"))
                    if (categoryError.isNotEmpty()) Text(categoryError, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("categoryError"))
                }
            },
            confirmButton = { TextButton(onClick = {
                val result = engine.addCategory(categoryName)
                categoryError = result.message
                if (result.success) { revision++; showCategory = false }
            }, modifier = Modifier.testTag("saveCategory")) { Text("Save") } },
            dismissButton = { TextButton(onClick = { showCategory = false }, modifier = Modifier.testTag("cancelCategory")) { Text("Cancel") } })
    }
    if (saved) AlertDialog(onDismissRequest = { saved = false }, title = { Text("Transaction saved") },
        confirmButton = { TextButton(onClick = { saved = false }) { Text("OK") } })
}

private data class NavItem(val title: String, val icon: ImageVector)
