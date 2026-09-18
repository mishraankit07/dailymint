import SwiftUI
import Combine
import DailyMintCore
import UserNotifications
import Darwin

final class FileStore: NSObject, LedgerStore {
    let url: URL
    init(testing: Bool = false) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = directory.appendingPathComponent(testing ? "ui-test-ledger.json" : "ledger-v1.json")
        super.init()
        protectForBackgroundAccess()
    }
    func load() throws -> LedgerRead {
        guard FileManager.default.fileExists(atPath: url.path) else { return LedgerRead(snapshot: nil) }
        return LedgerRead(snapshot: try String(contentsOf: url, encoding: .utf8))
    }
    func save(snapshot: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try snapshot.write(to: url, atomically: true, encoding: .utf8)
        protectForBackgroundAccess()
    }
    private func protectForBackgroundAccess() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }
    func withExclusiveLock<T>(_ body: () -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(descriptor) }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: lockURL.path
        )
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(descriptor, LOCK_UN) }
        return body()
    }
}

@MainActor
final class LedgerModel: ObservableObject {
    @Published private(set) var engine: LedgerEngine
    @Published var revision = 0
    private let store: FileStore
    private var lastLoadedFileState: FileState?

    private struct FileState: Equatable {
        let modificationDate: Date?
        let size: UInt64?
    }

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        store = FileStore(testing: testing)
        #if DEBUG
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-test-data") {
            try? FileManager.default.removeItem(at: store.url)
        }
        #endif
        engine = LedgerEngine(store: store)
        lastLoadedFileState = fileState()
    }
    func reload() {
        engine = LedgerEngine(store: store)
        lastLoadedFileState = fileState()
        revision += 1
    }
    func refreshIfChanged() {
        if fileState() != lastLoadedFileState { reload() }
    }
    private func fileState() -> FileState? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: store.url.path) else { return nil }
        return FileState(
            modificationDate: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value
        )
    }
    func mutate(_ operation: (LedgerEngine) -> SaveResult) -> String? {
        do {
            return try store.withExclusiveLock {
                engine = LedgerEngine(store: store)
                let result = operation(engine)
                lastLoadedFileState = fileState()
                if result.success { revision += 1; return nil }
                return result.message
            }
        } catch {
            return "Could not access local data. Please try again."
        }
    }
    func addCategory(_ name: String) -> String? {
        mutate { $0.addCategory(rawName: name) }
    }
    func addEntry(name: String, amount: String, category: String, date: Date, income: Bool) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return mutate {
            $0.addEntry(id: UUID().uuidString, name: name, amount: amount,
                        category: category, date: formatter.string(from: date), income: income)
        }
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
    @State private var selectedTab = AppTab.home
    @State private var showingAdd = false
    @AppStorage("smsOnboardingSeenV1") private var onboardingSeen = false
    @Environment(\.scenePhase) private var scenePhase
    private enum AppTab: String, CaseIterable { case home, growth, add, ledger, plan
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .home: return "house"
            case .growth: return "chart.xyaxis.line"
            case .add: return "plus.circle.fill"
            case .ledger: return "list.bullet.rectangle"
            case .plan: return "target"
            }
        }
    }
    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: "smsOnboardingSeenV1")
        }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if !onboardingSeen && (!ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.arguments.contains("--show-onboarding")) {
                    SMSOnboardingView { onboardingSeen = true }
                } else {
                    Group {
                        switch selectedTab {
                        case .home: MonthView(model: model, onSeeAll: { selectedTab = .ledger })
                        case .growth: GrowthView(model: model)
                        case .add: EmptyView()
                        case .ledger: LedgerView(model: model)
                        case .plan: PlanView(model: model)
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(AppTab.allCases, id: \.self) { tab in
                                Button {
                                    if tab == .add { showingAdd = true } else { selectedTab = tab }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: tab.icon).font(.system(size: tab == .add ? 27 : 21, weight: .medium))
                                        Text(tab.title).font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(selectedTab == tab || tab == .add ? Color.dmNavSelected : Color.dmHeroText)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(tab.title)
                                .accessibilityAddTraits(selectedTab == tab && tab != .add ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 7)
                        .background(Color.dmNav.ignoresSafeArea(edges: .bottom))
                    }
                    .tint(Color.dmFlow)
                }
            }
            .sheet(isPresented: $showingAdd) {
                ManualView(model: model, onFinish: { showingAdd = false })
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    model.reload()
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                if scenePhase == .active { model.refreshIfChanged() }
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.arguments.contains("--simulate-sms-after-launch") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "dd/MM/yyyy"
                    let date = formatter.string(from: Date())
                    _ = await ShortcutSMSProcessor.shared.importMessage(
                        "A/c *2468 debited by Rs.5.00 towards mandate for APPLE MEDIA on \(date).RRN:900000000022 Avl bal is Rs.6247.64-INDIAN BANK",
                        sender: "INDIAN BANK"
                    )
                }
            }
            #endif
        }
    }
}

struct PlanView: View {
    @ObservedObject var model: LedgerModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Plan")
                    RaisedPanel {
                        Text("Coming soon")
                            .font(.headline)
                            .foregroundStyle(Color.dmInk)
                        Text("Budgets and savings goals are not available yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color.dmInkSoft)
                    }
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("")
            .withSettings(model: model)
        }
    }
}

struct ManualView: View {
    @ObservedObject var model: LedgerModel
    let onFinish: () -> Void
    @State private var name = ""
    @State private var amount = ""
    @State private var income = false
    @State private var category = "Miscellaneous"
    @State private var date = Date()
    @State private var error: String?
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
                        .onChange(of: income) { value in category = value ? "Other income" : "Miscellaneous" }
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
                            ForEach(income ? ["Salary", "Other income", "Reimbursement", "Refund", "Own-account transfer"] : model.engine.categories(), id: \.self) { option in
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
                            if error == nil { onFinish() }
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinish).accessibilityIdentifier("cancelEntry")
                }
            }
            .onDisappear { focusedField = nil }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: LedgerModel
    @AppStorage("smsOnboardingSeenV1") private var onboardingSeen = true
    @State private var showCategory = false
    @State private var deletion: String?
    @State private var error: String?
    @State private var reminderEnabled = false
    @State private var reminderTime = "21:30"
    @State private var unrecognizedText: String?
    @State private var shortcutReceiptText: String?
    @State private var reminderDigits = ReminderDigits.from24Hour("21:30")
    @FocusState private var focusedReminderDigit: ReminderDigit?
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
                    shortcutSetupSection
                    shortcutReceiptsSection
                    unrecognizedSection
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showCategory) { CategorySheet(model: model) }
                .confirmationDialog("Delete category? Transactions will move to Miscellaneous.", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                    Button("Delete", role: .destructive) { if let deletion { error = model.mutate { $0.deleteCategory(name: deletion) } }; deletion = nil }
                }
                .onAppear {
                    reminderEnabled = model.engine.reminderEnabled()
                    reminderTime = model.engine.reminderTime()
                    reminderDigits = ReminderDigits.from24Hour(reminderTime)
                }
                .alert("Unrecognized message", isPresented: Binding(get: { unrecognizedText != nil }, set: { if !$0 { unrecognizedText = nil } })) {
                    Button("Close") { unrecognizedText = nil }
                } message: {
                    Text(unrecognizedText ?? "")
                }
                .alert("Shortcut import", isPresented: Binding(get: { shortcutReceiptText != nil }, set: { if !$0 { shortcutReceiptText = nil } })) {
                    Button("Close") { shortcutReceiptText = nil }
                } message: {
                    Text(shortcutReceiptText ?? "")
                }
        }
    }

    private var shortcutSetupSection: some View {
        RaisedPanel {
            SectionHeading(title: "Automatic SMS capture")
            Text("Set up or review the Message automation in Shortcuts.")
                .font(.subheadline)
                .foregroundStyle(Color.dmInkSoft)
            Button {
                onboardingSeen = false
            } label: {
                Label("Open setup guide", systemImage: "arrow.right")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("openSMSSetup")
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Reminder time").foregroundStyle(Color.dmInk)
                HStack(spacing: 8) {
                    reminderDigitField(.h1)
                    reminderDigitField(.h2)
                    Text(":").font(.headline).foregroundStyle(Color.dmInkFaint)
                    reminderDigitField(.m1)
                    reminderDigitField(.m2)
                    Picker("Period", selection: periodBinding) {
                        Text("AM").tag("AM")
                        Text("PM").tag("PM")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 112)
                }
                if let validation = reminderDigits.validationMessage {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(Color.dmSpend)
                        .accessibilityIdentifier("reminderTimeError")
                }
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(model.engine.categories(), id: \.self) { item in
                    CategoryChip(name: item, removable: item != "Miscellaneous") {
                        deletion = item
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var shortcutReceiptsSection: some View {
        let receipts = ShortcutImportLog.recent()
        if !receipts.isEmpty {
            RaisedPanel {
                SectionHeading(title: "Shortcut imports", trailing: String(receipts.count))
                ForEach(receipts) { receipt in
                    Button(receipt.title) {
                        shortcutReceiptText = "Status: \(receipt.status)\nSender: \(receipt.sender)\n\n\(receipt.preview)"
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.dmFlow)
                }
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

    private var periodBinding: Binding<String> {
        Binding(
            get: { reminderDigits.period },
            set: { value in
                reminderDigits.period = value
                commitReminderDigits()
            }
        )
    }

    private var monthStartBinding: Binding<Int32> {
        Binding(
            get: { model.engine.monthStartDay() },
            set: { value in
                error = model.mutate { $0.setMonthStartDay(day: value) }
            }
        )
    }

    private func toggleReminder() {
        reminderEnabled.toggle()
        updateReminder(time: reminderTime)
    }

    private func reminderDigitField(_ digit: ReminderDigit) -> some View {
        let invalid = reminderDigits.invalidDigits.contains(digit)
        return TextField("", text: reminderDigitBinding(digit))
            .keyboardType(.numberPad)
            .foregroundStyle(Color.dmInk)
            .multilineTextAlignment(.center)
            .font(.headline.monospacedDigit())
            .frame(width: 38, height: 42)
            .background(invalid ? Color.dmSpend.opacity(0.12) : Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(invalid ? Color.dmSpend : Color.dmHairline, lineWidth: 1)
            )
            .focused($focusedReminderDigit, equals: digit)
            .accessibilityIdentifier("reminder\(digit.rawValue)")
    }

    private func reminderDigitBinding(_ digit: ReminderDigit) -> Binding<String> {
        Binding(
            get: { reminderDigits.value(for: digit) },
            set: { value in
                reminderDigits.set(String(value.filter(\.isNumber).prefix(1)), for: digit)
                if !reminderDigits.value(for: digit).isEmpty {
                    focusedReminderDigit = digit.next
                }
                commitReminderDigits()
            }
        )
    }

    private func commitReminderDigits() {
        guard let time = reminderDigits.time24Hour else { return }
        reminderTime = time
        updateReminder(time: time)
    }

    private func updateReminder(time: String) {
        error = model.mutate { $0.setReminder(enabled: reminderEnabled, time: time) }
        if error == nil {
            ReminderScheduler.apply(engine: model.engine)
        }
    }

    private func unrecognizedTitle(index: Int, reason: String) -> String {
        "View message " + String(index + 1) + (reason.isEmpty ? "" : " · " + reason)
    }
}

private enum ReminderDigit: String, Hashable {
    case h1 = "HourTens"
    case h2 = "HourOnes"
    case m1 = "MinuteTens"
    case m2 = "MinuteOnes"

    var next: ReminderDigit? {
        switch self {
        case .h1: return .h2
        case .h2: return .m1
        case .m1: return .m2
        case .m2: return nil
        }
    }
}

private struct ReminderDigits {
    var h1: String
    var h2: String
    var m1: String
    var m2: String
    var period: String

    static func from24Hour(_ time: String) -> ReminderDigits {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour24 = parts.first ?? 21
        let minute = parts.dropFirst().first ?? 30
        let period = hour24 >= 12 ? "PM" : "AM"
        let hour12Value = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
        let hour12 = String(format: "%02d", hour12Value)
        let minuteText = String(format: "%02d", minute)
        return ReminderDigits(
            h1: String(hour12[hour12.startIndex]),
            h2: String(hour12[hour12.index(after: hour12.startIndex)]),
            m1: String(minuteText[minuteText.startIndex]),
            m2: String(minuteText[minuteText.index(after: minuteText.startIndex)]),
            period: period
        )
    }

    var hourText: String { h1 + h2 }
    var minuteText: String { m1 + m2 }

    var time24Hour: String? {
        guard validationMessage == nil, let hour = Int(hourText), let minute = Int(minuteText) else { return nil }
        let hour24 = period == "AM" ? (hour == 12 ? 0 : hour) : (hour == 12 ? 12 : hour + 12)
        return String(format: "%02d:%02d", hour24, minute)
    }

    var validationMessage: String? {
        if hourText.count == 2, let hour = Int(hourText), !(1...12).contains(hour) {
            return "Hour must be between 01 and 12."
        }
        if minuteText.count == 2, let minute = Int(minuteText), !(0...59).contains(minute) {
            return "Minutes must be between 00 and 59."
        }
        return nil
    }

    var invalidDigits: Set<ReminderDigit> {
        var result = Set<ReminderDigit>()
        if hourText.count == 2, let hour = Int(hourText), !(1...12).contains(hour) {
            result.formUnion([.h1, .h2])
        }
        if minuteText.count == 2, let minute = Int(minuteText), !(0...59).contains(minute) {
            result.formUnion([.m1, .m2])
        }
        return result
    }

    func value(for digit: ReminderDigit) -> String {
        switch digit {
        case .h1: return h1
        case .h2: return h2
        case .m1: return m1
        case .m2: return m2
        }
    }

    mutating func set(_ value: String, for digit: ReminderDigit) {
        switch digit {
        case .h1: h1 = value
        case .h2: h2 = value
        case .m1: m1 = value
        case .m2: m2 = value
        }
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
