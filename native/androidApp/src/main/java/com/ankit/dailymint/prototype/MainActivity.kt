package com.ankit.dailymint.prototype

import android.os.Bundle
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.content.Intent
import android.net.Uri
import android.provider.Settings
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
import androidx.compose.material.icons.automirrored.filled.ReceiptLong
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
    private var smsAllowed by mutableStateOf(false)
    private var smsIntroDismissed by mutableStateOf(false)
    private var smsPermissionRequested by mutableStateOf(false)
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        smsAllowed = granted
        if (granted) { smsError = ""; smsIntroDismissed = true; smsReader.start(); scanMessages() }
        else smsError = "Allow SMS access to capture bank transactions automatically."
    }
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) ReminderScheduler.apply(this, engine)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        engine = LedgerEngine(PreferenceStore(this))
        smsReader = SmsReader(this) { scanMessages() }
        smsAllowed = smsReader.allowed()
        smsPermissionRequested = getSharedPreferences("sms-setup", MODE_PRIVATE).getBoolean("permission-requested", false)
        setContent {
            DailyMintTheme {
                if (!smsAllowed && !smsIntroDismissed) {
                    AndroidSMSOnboarding(
                        onAllow = {
                            smsPermissionRequested = true
                            getSharedPreferences("sms-setup", MODE_PRIVATE).edit().putBoolean("permission-requested", true).apply()
                            permission.launch(android.Manifest.permission.READ_SMS)
                        },
                        onOpenSettings = {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")))
                        },
                        showSettings = smsPermissionRequested && !shouldShowRequestPermissionRationale(android.Manifest.permission.READ_SMS),
                        onContinue = { smsIntroDismissed = true }
                    )
                } else {
                    DailyMint(engine, externalRevision, smsError,
                        requestSms = { permission.launch(android.Manifest.permission.READ_SMS) },
                        requestNotifications = { requestNotificationPermission() },
                        smsAccessAllowed = smsAllowed,
                        openAppSettings = { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"))) })
                }
            }
        }
    }
    override fun onResume() { super.onResume(); if (::smsReader.isInitialized) { smsAllowed = smsReader.allowed(); smsReader.start(); scanMessages() } }
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
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    MaterialTheme(
        colorScheme = (if (dark) darkColorScheme(
            primary = Flow,
            secondary = IncomeGreen,
            tertiary = InvestGold,
            background = Paper,
            surface = PaperRaised,
            surfaceVariant = FlowSoft,
            onPrimary = Paper,
            onSecondary = Paper,
            onBackground = Ink,
            onSurface = Ink,
            outline = Hairline,
            error = SpendRed
        ) else lightColorScheme(
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
        )),
        content = content
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DailyMint(engine: LedgerEngine, externalRevision: Int = 0, smsError: String = "", requestSms: () -> Unit = {},
    requestNotifications: () -> Unit = {}, smsAccessAllowed: Boolean = true, openAppSettings: () -> Unit = {}) {
    val context = LocalContext.current
    val stateHolder = rememberSaveableStateHolder()
    var revision by remember { mutableIntStateOf(0) }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var addReturnTab by rememberSaveable { mutableIntStateOf(0) }
    var settingsReturnTab by rememberSaveable { mutableIntStateOf(0) }
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
    var edited by remember { mutableStateOf<Entry?>(null) }
    var detailId by rememberSaveable { mutableStateOf<String?>(null) }
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
                    Text("DailyMint", color = Ink, fontWeight = FontWeight.Bold)
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Paper),
                actions = {
                    IconButton(onClick = {
                        if (tab == 5) tab = settingsReturnTab else { settingsReturnTab = tab; tab = 5 }
                    }) {
                        Icon(if (tab == 5) Icons.Default.Close else Icons.Default.Settings,
                            contentDescription = if (tab == 5) "Close settings" else "Settings", tint = Ink)
                    }
                }
            )
        },
        bottomBar = {
            NavigationBar(containerColor = NavColor, tonalElevation = 0.dp) {
                listOf(
                    NavItem("Home", Icons.Default.CalendarMonth),
                    NavItem("Growth", Icons.AutoMirrored.Filled.ShowChart),
                    NavItem("Add", Icons.Default.AddCircle),
                    NavItem("Ledger", Icons.AutoMirrored.Filled.ReceiptLong),
                    NavItem("Plan", Icons.Default.Flag)
                ).forEachIndexed { index, item ->
                    NavigationBarItem(
                        modifier = Modifier.testTag("nav${item.title}"),
                        selected = (if (tab == 5) settingsReturnTab else tab) == index,
                        onClick = {
                            if (index == 2 && tab != 2) addReturnTab = if (tab == 5) settingsReturnTab else tab
                            tab = index
                        },
                        icon = { Icon(item.icon, contentDescription = item.title,
                            modifier = Modifier.size(if (index == 2) 30.dp else 24.dp)) },
                        label = { Text(item.title) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = NavSelected,
                            selectedTextColor = NavSelected,
                            indicatorColor = Color.Transparent,
                            unselectedIconColor = HeroText,
                            unselectedTextColor = HeroText
                        )
                    )
                }
            }
        }
    ) { padding ->
        stateHolder.SaveableStateProvider(tab) {
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (tab == 3) {
                LedgerContent(engine, revision + externalRevision, smsError,
                    onDetail = { detailId = it.id }, onUnrecognized = { unrecognizedDebug = it })
            } else Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                engine.loadError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                if (smsError.isNotEmpty()) { Text(smsError); TextButton(onClick = requestSms) { Text("Allow SMS access") } }
                when (tab) {
                    0 -> MonthContent(engine, revision + externalRevision, onOpenLedger = { tab = 3 }, onDetail = { detailId = it.id })
                    1 -> GrowthContent(engine, revision + externalRevision)
                    4 -> {
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
                                        onClick = { income = index == 1; category = if (income) "Income" else "Miscellaneous" },
                                        shape = SegmentedButtonDefaults.itemShape(index, 2)) { Text(label) }
                                }
                            }
                            Spacer(Modifier.height(12.dp))
                            OutlinedTextField(name, { name = it; category = engine.suggestCategory(it, income).let { suggestion ->
                                suggestion
                            } }, label = { Text("Name") }, singleLine = true,
                                modifier = Modifier.fillMaxWidth().testTag("entryName"))
                            OutlinedTextField(amount, { amount = it }, label = { Text("Amount") }, singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                modifier = Modifier.fillMaxWidth().testTag("entryAmount"))
                            Box {
                                OutlinedButton(onClick = { categoryMenu = true }, modifier = Modifier.testTag("entryCategory")) { Text(category) }
                                DropdownMenu(expanded = categoryMenu, onDismissRequest = { categoryMenu = false }) {
                                    (if (income) CreditKind.all.map(CreditKind::label) else categories).forEach { option ->
                                        DropdownMenuItem(text = { Text(option) }, onClick = { category = option; categoryMenu = false })
                                    }
                                    if (!income) DropdownMenuItem(text = { Text("Add category") }, onClick = {
                                        categoryMenu = false; categoryName = ""; categoryError = ""; showCategory = true
                                    })
                                }
                            }
                            OutlinedTextField(date, { date = it }, label = { Text("Date (YYYY-MM-DD)") }, singleLine = true,
                                modifier = Modifier.fillMaxWidth().testTag("entryDate"))
                            if (entryError.isNotEmpty()) Text(entryError, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("entryError"))
                            Button(onClick = {
                                val result = engine.addEntry(UUID.randomUUID().toString(), name, amount, category, date, income)
                                entryError = result.message
                                if (result.success) {
                                    revision++; name = ""; amount = ""; category = if (income) "Income" else "Miscellaneous"
                                    tab = addReturnTab
                                }
                            }, enabled = engine.loadError == null, modifier = Modifier.fillMaxWidth().testTag("saveEntry")) { Text("Save") }
                            OutlinedButton(onClick = {
                                name = ""; amount = ""; entryError = ""; tab = addReturnTab
                            }, modifier = Modifier.fillMaxWidth().testTag("cancelEntry")) { Text("Cancel") }
                        }
                    }
                    5 -> {
                        BrandHeader("Settings")
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
                            ReminderTimeEditor(
                                time = engine.reminderTime(),
                                error = settingsError,
                                onError = { settingsError = it },
                                onValid = { time ->
                                    val result = engine.setReminder(engine.reminderEnabled(), time)
                                    settingsError = result.message
                                    if (result.success) {
                                        revision++
                                        ReminderScheduler.apply(context, engine)
                                    }
                                },
                                modifier = Modifier.testTag("reminderTime")
                            )
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
                        RaisedCard {
                            SectionTitle("SMS access")
                            Text(if (smsAccessAllowed) "Enabled" else "Off. Allow access to capture bank transactions automatically.", color = InkSoft)
                            if (!smsAccessAllowed) {
                                TextButton(onClick = requestSms) { Text("Allow SMS access") }
                                TextButton(onClick = openAppSettings) { Text("Open app settings") }
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
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                categories.forEach { categoryName ->
                                    CategoryChip(categoryName, removable = categoryName != "Miscellaneous") {
                                        deletingCategory = categoryName
                                    }
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
    detailId?.let { id -> TransactionDetail(id, engine, revision + externalRevision,
        onDismiss = { detailId = null }, onChanged = { revision++ }, onManualEdit = { edited = it }) }
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
                if (result.success) { revision++; if (tab == 2) category = categoryName.trim(); showCategory = false }
            }, modifier = Modifier.testTag("saveCategory")) { Text("Save") } },
            dismissButton = { TextButton(onClick = { showCategory = false }, modifier = Modifier.testTag("cancelCategory")) { Text("Cancel") } })
    }
}

private data class NavItem(val title: String, val icon: ImageVector)

@Composable
private fun ReminderTimeEditor(
    time: String,
    error: String,
    onError: (String) -> Unit,
    onValid: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val initial = remember(time) { ReminderDigits.from24Hour(time) }
    var h1 by remember(time) { mutableStateOf(initial.h1) }
    var h2 by remember(time) { mutableStateOf(initial.h2) }
    var m1 by remember(time) { mutableStateOf(initial.m1) }
    var m2 by remember(time) { mutableStateOf(initial.m2) }
    var period by remember(time) { mutableStateOf(initial.period) }

    fun commit(nextH1: String = h1, nextH2: String = h2, nextM1: String = m1, nextM2: String = m2, nextPeriod: String = period) {
        val digits = ReminderDigits(nextH1, nextH2, nextM1, nextM2, nextPeriod)
        val validation = digits.validationMessage()
        onError(validation.orEmpty())
        val converted = digits.to24Hour()
        if (validation == null && converted != null) onValid(converted)
    }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Reminder time", color = Ink)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ReminderDigitField("H1", h1, h1 + h2, isHour = true) { value -> h1 = value; commit(nextH1 = value) }
            ReminderDigitField("H2", h2, h1 + h2, isHour = true) { value -> h2 = value; commit(nextH2 = value) }
            Text(":", color = InkFaint, fontWeight = FontWeight.Bold)
            ReminderDigitField("M1", m1, m1 + m2, isHour = false) { value -> m1 = value; commit(nextM1 = value) }
            ReminderDigitField("M2", m2, m1 + m2, isHour = false) { value -> m2 = value; commit(nextM2 = value) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = period == "AM", onClick = { period = "AM"; commit(nextPeriod = "AM") }, label = { Text("AM") })
            FilterChip(selected = period == "PM", onClick = { period = "PM"; commit(nextPeriod = "PM") }, label = { Text("PM") })
        }
        val validation = ReminderDigits(h1, h2, m1, m2, period).validationMessage()
        if (validation != null) Text(validation, color = SpendRed, style = MaterialTheme.typography.bodySmall)
        else if (error.isNotEmpty() && error.contains("reminder", ignoreCase = true)) {
            Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun ReminderDigitField(
    label: String,
    value: String,
    pair: String,
    isHour: Boolean,
    onChange: (String) -> Unit
) {
    val invalid = pair.length == 2 && pair.toIntOrNull()?.let {
        if (isHour) it !in 1..12 else it !in 0..59
    } == true
    OutlinedTextField(
        value = value,
        onValueChange = { raw -> onChange(raw.filter { it.isDigit() }.take(1)) },
        singleLine = true,
        isError = invalid,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        modifier = Modifier.width(52.dp).semantics {
            contentDescription = when (label) {
                "H1" -> "First hour digit"
                "H2" -> "Second hour digit"
                "M1" -> "First minute digit"
                else -> "Second minute digit"
            }
        }.testTag("reminder$label")
    )
}

private data class ReminderDigits(
    val h1: String,
    val h2: String,
    val m1: String,
    val m2: String,
    val period: String
) {
    fun validationMessage(): String? {
        val hour = (h1 + h2).takeIf { it.length == 2 }?.toIntOrNull()
        if (hour != null && hour !in 1..12) return "Hour must be between 01 and 12."
        val minute = (m1 + m2).takeIf { it.length == 2 }?.toIntOrNull()
        if (minute != null && minute !in 0..59) return "Minutes must be between 00 and 59."
        return null
    }

    fun to24Hour(): String? {
        val hour = (h1 + h2).takeIf { it.length == 2 }?.toIntOrNull() ?: return null
        val minute = (m1 + m2).takeIf { it.length == 2 }?.toIntOrNull() ?: return null
        if (hour !in 1..12 || minute !in 0..59) return null
        val hour24 = if (period == "AM") {
            if (hour == 12) 0 else hour
        } else {
            if (hour == 12) 12 else hour + 12
        }
        return "%02d:%02d".format(hour24, minute)
    }

    companion object {
        fun from24Hour(time: String): ReminderDigits {
            val parts = time.split(":")
            val hour24 = parts.getOrNull(0)?.toIntOrNull() ?: 21
            val minute = parts.getOrNull(1)?.toIntOrNull() ?: 30
            val period = if (hour24 >= 12) "PM" else "AM"
            val hour12 = when {
                hour24 == 0 -> 12
                hour24 > 12 -> hour24 - 12
                else -> hour24
            }
            val hourText = "%02d".format(hour12)
            val minuteText = "%02d".format(minute)
            return ReminderDigits(
                h1 = hourText.substring(0, 1),
                h2 = hourText.substring(1, 2),
                m1 = minuteText.substring(0, 1),
                m2 = minuteText.substring(1, 2),
                period = period
            )
        }
    }
}
