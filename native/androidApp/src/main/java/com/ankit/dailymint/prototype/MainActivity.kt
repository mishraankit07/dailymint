package com.ankit.dailymint.prototype

import android.os.Bundle
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
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
        setContent { MaterialTheme { DailyMint(engine, externalRevision, smsError,
            requestSms = { permission.launch(android.Manifest.permission.READ_SMS) },
            requestNotifications = { requestNotificationPermission() }) } }
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
    var deletingCategory by remember { mutableStateOf<String?>(null) }
    var monthMenu by remember { mutableStateOf(false) }
    var settingsError by remember { mutableStateOf("") }
    val categories = remember(revision, externalRevision) { engine.categories() }

    Scaffold(topBar = { TopAppBar(title = { Column { Text("DailyMint"); Text("Know Your Flow", style = MaterialTheme.typography.labelMedium) } }, actions = {
        IconButton(onClick = { tab = if (tab == 4) 0 else 4 }) {
            Icon(if (tab == 4) Icons.Default.Close else Icons.Default.Settings, contentDescription = if (tab == 4) "Close settings" else "Settings")
        }
    }) }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            TabRow(selectedTabIndex = if (tab == 4) 0 else tab) {
                listOf("Month", "Growth", "Manual", "Plan").forEachIndexed { index, title ->
                    Tab(selected = tab == index, onClick = { tab = index }, text = { Text(title) })
                }
            }
            Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                engine.loadError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                if (smsError.isNotEmpty()) { Text(smsError); TextButton(onClick = requestSms) { Text("Allow SMS access") } }
                when (tab) {
                    0 -> MonthContent(engine, revision + externalRevision, onEdit = { edited = it }, onDebug = { debug = it })
                    1 -> GrowthContent(engine, revision + externalRevision)
                    3 -> { Text("Plan", style = MaterialTheme.typography.headlineMedium); Text("Coming soon") }
                    2 -> {
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            listOf("Expense", "Income").forEachIndexed { index, label ->
                                SegmentedButton(selected = income == (index == 1),
                                    onClick = { income = index == 1; category = if (income) "Received" else "Miscellaneous" },
                                    shape = SegmentedButtonDefaults.itemShape(index, 2)) { Text(label) }
                            }
                        }
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
                    4 -> {
                        Text("Daily check-in", style = MaterialTheme.typography.titleLarge)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Expense reminder")
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
                        var reminderMenu by remember { mutableStateOf(false) }
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
                        Box {
                            OutlinedButton(onClick = { monthMenu = true }) { Text("Tracking cycle starts: " + engine.monthStartDay()) }
                            DropdownMenu(monthMenu, onDismissRequest = { monthMenu = false }) {
                                (1..31).forEach { day -> DropdownMenuItem(text = { Text(day.toString()) }, onClick = {
                                    val result = engine.setMonthStartDay(day)
                                    settingsError = result.message
                                    if (result.success) { revision++; monthMenu = false }
                                }) }
                            }
                        }
                        if (settingsError.isNotEmpty()) Text(settingsError, color = MaterialTheme.colorScheme.error)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Categories", style = MaterialTheme.typography.titleLarge)
                            IconButton(onClick = { categoryName = ""; categoryError = ""; showCategory = true },
                                modifier = Modifier.testTag("addCategory")) { Icon(Icons.Default.Add, contentDescription = "Add category") }
                        }
                        categories.forEach { categoryName -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(categoryName)
                            if (categoryName != "Miscellaneous") IconButton(onClick = { deletingCategory = categoryName }) { Icon(Icons.Default.Close, contentDescription = "Delete " + categoryName) }
                        } }
                    }
                }
            }
        }
    }
    edited?.let { EntryEditor(it, engine, onDismiss = { edited = null }, onChanged = { revision++ }) }
    debug?.let { entry -> AlertDialog(onDismissRequest = { debug = null }, title = { Text("Message details") },
        text = { Text("From: " + entry.sender + "\nDate: " + entry.date + "\n\n" + entry.rawSms) },
        confirmButton = { TextButton(onClick = { debug = null }) { Text("Close") } }) }
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
