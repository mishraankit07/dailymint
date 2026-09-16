import SwiftUI
import DailyMintCore
import UserNotifications

final class FileStore: NSObject, LedgerStore {
    let url: URL
    init(testing: Bool = false) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = directory.appendingPathComponent(testing ? "ui-test-ledger.json" : "ledger-v1.json")
        super.init()
    }
    func load() throws -> LedgerRead {
        guard FileManager.default.fileExists(atPath: url.path) else { return LedgerRead(snapshot: nil) }
        return LedgerRead(snapshot: try String(contentsOf: url, encoding: .utf8))
    }
    func save(snapshot: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try snapshot.write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
final class LedgerModel: ObservableObject {
    let engine: LedgerEngine
    @Published var revision = 0
    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let store = FileStore(testing: testing)
        #if DEBUG
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-test-data") {
            try? FileManager.default.removeItem(at: store.url)
        }
        #endif
        engine = LedgerEngine(store: store)
    }
    func addCategory(_ name: String) -> String? {
        let result = engine.addCategory(rawName: name)
        if result.success { revision += 1; return nil }
        return result.message
    }
    func apply(_ result: SaveResult) -> String? {
        if result.success { revision += 1; return nil }
        return result.message
    }
    func addEntry(name: String, amount: String, category: String, date: Date, income: Bool) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let result = engine.addEntry(id: UUID().uuidString, name: name, amount: amount,
                                     category: category, date: formatter.string(from: date), income: income)
        if result.success { revision += 1; return nil }
        return result.message
    }
}

enum ReminderScheduler {
    static func apply(engine: LedgerEngine) {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-check-in"])
        guard engine.reminderEnabled() else { return }
        let parts = engine.reminderTime().split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            var date = DateComponents()
            date.hour = parts[0]
            date.minute = parts[1]
            let daySeed = Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: Date()) ?? 0
            let content = UNMutableNotificationContent()
            content.title = "DailyMint check-in"
            content.body = engine.reminderQuote(daySeed: Int32(daySeed)) + " Add today's expenses?"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            center.add(UNNotificationRequest(identifier: "daily-check-in", content: content, trigger: trigger))
        }
    }
}

@main
struct DailyMintApp: App {
    @StateObject private var model = LedgerModel()
    @State private var selectedTab = AppTab.month
    private enum AppTab: Hashable { case month, growth, imports, manual, plan }
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                MonthView(model: model).tabItem { Label("Month", systemImage: "calendar") }.tag(AppTab.month)
                GrowthView(model: model).tabItem { Label("Growth", systemImage: "chart.xyaxis.line") }.tag(AppTab.growth)
                ImportView(model: model).tabItem { Label("Import", systemImage: "tray.and.arrow.down") }.tag(AppTab.imports)
                ManualView(model: model).tabItem { Label("Manual", systemImage: "plus.circle") }.tag(AppTab.manual)
                PlanView().tabItem { Label("Plan", systemImage: "target") }.tag(AppTab.plan)
            }
            .tint(Color.dmInk)
            .preferredColorScheme(.light)
        }
    }
}

struct PlanView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BrandHeader(title: "Plan")
                RaisedPanel {
                    ZStack {
                        Circle().stroke(Color.dmFlow.opacity(0.24), lineWidth: 18).frame(width: 126, height: 126)
                        Circle().stroke(Color.dmIncome, lineWidth: 10).frame(width: 86, height: 86)
                        Circle().fill(Color.dmInvest).frame(width: 18, height: 18)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    Text("Coming soon")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.dmInk)
                    Text("Plan a goal, set aside money, and watch the gap close over time.")
                        .font(.subheadline)
                        .foregroundStyle(Color.dmInkSoft)
                    HStack {
                        CategoryDot(name: "Investment")
                        Text("Goal planning")
                        Spacer()
                        Text("Soon").foregroundStyle(Color.dmFlow)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dmInkFaint)
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .background(Color.dmPaper)
    }
}

struct ManualView: View {
    @ObservedObject var model: LedgerModel
    @State private var name = ""
    @State private var amount = ""
    @State private var income = false
    @State private var category = "Miscellaneous"
    @State private var date = Date()
    @State private var error: String?
    @State private var saved = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, amount }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Add transaction")
                    RaisedPanel {
                        if let loadError = model.engine.loadError { Text(loadError).foregroundStyle(.red) }
                        HStack(spacing: 6) {
                            PaperSegment(title: "Expense", value: false, selection: $income)
                            PaperSegment(title: "Income", value: true, selection: $income)
                        }
                        .onChange(of: income) { value in category = value ? "Received" : "Miscellaneous" }
                        .padding(4)
                        .background(Color.dmHairline.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        PaperField(placeholder: "Name", text: $name)
                            .accessibilityIdentifier("entryName")
                            .focused($focusedField, equals: .name)
                            .onChange(of: name) { value in category = model.engine.suggestCategory(name: value, income: income) }
                        PaperField(placeholder: "Amount", text: $amount, keyboard: .decimalPad)
                            .accessibilityIdentifier("entryAmount")
                            .focused($focusedField, equals: .amount)
                        Menu {
                            ForEach(income ? ["Salary", "Received"] : model.engine.categories(), id: \.self) { option in
                                Button(option) { category = option }
                            }
                        } label: {
                            HStack {
                                Text(category).foregroundStyle(Color.dmFlow)
                                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Color.dmFlow)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.dmPaperRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmHairline, lineWidth: 1))
                        }
                        .accessibilityIdentifier("entryCategory")
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .foregroundStyle(Color.dmInk)
                        if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("entryError") }
                        Button("Save") {
                            focusedField = nil
                            error = model.addEntry(name: name, amount: amount, category: category, date: date, income: income)
                            if error == nil { name = ""; amount = ""; category = income ? "Received" : "Miscellaneous"; saved = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.dmInk)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("saveEntry")
                        .disabled(model.engine.loadError != nil)
                    }
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .withSettings(model: model)
            .onDisappear { focusedField = nil }
            .alert("Transaction saved", isPresented: $saved) { Button("OK", role: .cancel) {} }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: LedgerModel
    @State private var showCategory = false
    @State private var deletion: String?
    @State private var error: String?
    @State private var reminderEnabled = false
    @State private var reminderTime = "21:30"
    @State private var unrecognizedText: String?
    private let reminderTimes = ["20:00", "20:30", "21:00", "21:30", "22:00"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Settings")
                    dailyCheckInSection
                    trackingCyclePicker
                    if let error {
                        Text(error).font(.caption).foregroundStyle(Color.dmSpend)
                    }
                    categoriesSection
                    unrecognizedSection
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showCategory) { CategorySheet(model: model) }
                .confirmationDialog("Delete category? Transactions will move to Miscellaneous.", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                    Button("Delete", role: .destructive) { if let deletion { error = model.apply(model.engine.deleteCategory(name: deletion)) }; deletion = nil }
                }
                .onAppear {
                    reminderEnabled = model.engine.reminderEnabled()
                    reminderTime = model.engine.reminderTime()
                }
                .alert("Unrecognized message", isPresented: Binding(get: { unrecognizedText != nil }, set: { if !$0 { unrecognizedText = nil } })) {
                    Button("Close") { unrecognizedText = nil }
                } message: {
                    Text(unrecognizedText ?? "")
                }
        }
    }

    private var dailyCheckInSection: some View {
        RaisedPanel {
            SectionHeading(title: "Daily check-in")
            Button(action: toggleReminder) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Expense reminder").font(.headline).foregroundStyle(Color.dmInk)
                        Text(reminderEnabled ? "Reminder on" : "Reminder off")
                            .font(.caption)
                            .foregroundStyle(Color.dmInkFaint)
                            .accessibilityIdentifier("reminderStatus")
                    }
                    Spacer()
                    Image(systemName: reminderEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(reminderEnabled ? Color.dmIncome : Color.dmInkFaint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reminderToggle")

            Menu {
                ForEach(reminderTimes, id: \.self) { time in
                    Button(time) { reminderTimeBinding.wrappedValue = time }
                }
            } label: {
                HStack {
                    Text("Reminder time").foregroundStyle(Color.dmInk)
                    Spacer()
                    Text(reminderTime).foregroundStyle(Color.dmFlow)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Color.dmFlow)
                }
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("reminderTime")
        }
    }

    private var trackingCyclePicker: some View {
        RaisedPanel {
            SectionHeading(title: "Tracking cycle")
            Menu {
                ForEach(1...31, id: \.self) { day in
                    Button(String(day)) { monthStartBinding.wrappedValue = Int32(day) }
                }
            } label: {
                HStack {
                    Text("Tracking cycle starts").foregroundStyle(Color.dmInk)
                    Spacer()
                    Text(String(model.engine.monthStartDay())).foregroundStyle(Color.dmFlow)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Color.dmFlow)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var categoriesSection: some View {
        RaisedPanel {
            SectionHeading(title: "Categories")
            Button {
                showCategory = true
            } label: {
                Label("Add category", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.dmInk)
            .accessibilityLabel("Add category")
            .accessibilityIdentifier("addCategory")
            ForEach(model.engine.categories(), id: \.self) { item in
                HStack {
                    CategoryDot(name: item, size: 9)
                    Text(item).foregroundStyle(Color.dmInk)
                    Spacer()
                    if item != "Miscellaneous" {
                        Button {
                            deletion = item
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.dmSpend)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete " + item)
                    }
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.dmHairline).frame(height: 1) }
            }
        }
    }

    @ViewBuilder
    private var unrecognizedSection: some View {
        let messages = model.engine.unrecognizedMessages()
        if !messages.isEmpty {
            RaisedPanel {
                SectionHeading(title: "Unrecognized messages", trailing: String(messages.count))
                ForEach(Array(messages.suffix(10).enumerated()), id: \.element.id) { index, row in
                    Button(unrecognizedTitle(index: index, reason: row.reason)) {
                        unrecognizedText = row.rawText
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.dmFlow)
                }
            }
        }
    }

    private var reminderTimeBinding: Binding<String> {
        Binding(
            get: { reminderTime },
            set: { value in
                reminderTime = value
                updateReminder(time: value)
            }
        )
    }

    private var monthStartBinding: Binding<Int32> {
        Binding(
            get: { model.engine.monthStartDay() },
            set: { value in
                error = model.apply(model.engine.setMonthStartDay(day: value))
            }
        )
    }

    private func toggleReminder() {
        reminderEnabled.toggle()
        updateReminder(time: reminderTime)
    }

    private func updateReminder(time: String) {
        let result = model.engine.setReminder(enabled: reminderEnabled, time: time)
        error = model.apply(result)
        if error == nil {
            ReminderScheduler.apply(engine: model.engine)
        }
    }

    private func unrecognizedTitle(index: Int, reason: String) -> String {
        "View message " + String(index + 1) + (reason.isEmpty ? "" : " · " + reason)
    }
}

struct CategorySheet: View {
    @ObservedObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Add category")
                    RaisedPanel {
                        PaperField(placeholder: "Category name", text: $name)
                            .focused($focused)
                            .accessibilityIdentifier("categoryName")
                            .submitLabel(.done)
                            .onSubmit(save)
                        if let error {
                            Text(error).font(.caption).foregroundStyle(Color.dmSpend).accessibilityIdentifier("categoryError")
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("Add category").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.accessibilityIdentifier("cancelCategory")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save).accessibilityIdentifier("saveCategory")
                    }
                }.onAppear { focused = true }
        }.presentationDetents([.medium, .large])
    }
    private func save() {
        error = model.addCategory(name)
        if error == nil { dismiss() }
    }
}

struct LedgerView: View {
    @ObservedObject var model: LedgerModel
    var body: some View {
        NavigationStack {
            List {
                Section("All entries") {
                    let totals = model.engine.totals()
                    Text("Money in: Rs " + model.engine.formatAmount(paise: totals.moneyIn)).accessibilityIdentifier("moneyIn")
                    Text("Spent: Rs " + model.engine.formatAmount(paise: totals.spent)).accessibilityIdentifier("spent")
                    Text("Invested: Rs " + model.engine.formatAmount(paise: totals.invested))
                    Text("Remaining: Rs " + model.engine.formatAmount(paise: totals.remaining))
                }
                ForEach(model.engine.entries().reversed(), id: \.id) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name)
                            Text(entry.category + " - " + entry.date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((entry.type == "income" ? "+" : "-") + "Rs " + model.engine.formatAmount(paise: entry.paise))
                    }
                }
            }.navigationTitle("Ledger")
        }
    }
}
