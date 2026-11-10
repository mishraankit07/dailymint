import SwiftUI
import Combine
import AppIntents
import FendYourSpendCore
import UserNotifications
import Darwin
import UIKit

enum OnboardingReleaseTracker {
    static let seenKey = "smsOnboardingSeenV1"
    static let releaseKey = "smsOnboardingRelease"

    static func prepare(arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard) {
        if arguments.contains("--reset-onboarding-release") {
            defaults.removeObject(forKey: releaseKey)
        }

        let release = testRelease(in: arguments) ?? bundleRelease
        guard defaults.string(forKey: releaseKey) != release else { return }
        defaults.set(false, forKey: seenKey)
        defaults.set(release, forKey: releaseKey)
    }

    private static func testRelease(in arguments: [String]) -> String? {
        arguments
            .first { $0.hasPrefix("--test-app-release=") }
            .map { String($0.dropFirst("--test-app-release=".count)) }
    }

    private static var bundleRelease: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }
}

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
            $0.addEntryWithSplit(id: UUID().uuidString, name: name, amount: amount,
                                 category: category, date: formatter.string(from: date), income: income,
                                 splitMethod: "none", splitPeopleCount: 0, personalAmount: "")
        }
    }
}

enum ReminderScheduler {
    static func apply(engine: LedgerEngine) {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-check-in"])
        center.removeDeliveredNotifications(withIdentifiers: ["daily-check-in"])
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
            content.title = "Fend Your Spend check-in"
            content.body = engine.reminderQuote(daySeed: Int32(daySeed)) + " Add today's expenses?"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            center.add(UNNotificationRequest(identifier: "daily-check-in", content: content, trigger: trigger))
        }
    }
}

final class FendYourSpendAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

private struct AnimatedBrandSplash: View {
    let onFinished: () -> Void
    @State private var spendVisible = false
    @State private var splashOpacity = 1.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SplashBackground")
                    .resizable()
                    .scaledToFill()

                VStack(spacing: 18) {
                    HStack(alignment: .center, spacing: 2) {
                        Image("SplashFMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 53, height: 68)
                        Text("end")
                            .font(.custom("Georgia-Bold", fixedSize: 68))
                            .foregroundStyle(Color(red: 242 / 255, green: 240 / 255, blue: 228 / 255))
                    }

                    HStack(alignment: .center, spacing: 14) {
                        Text("your spend")
                            .font(.custom("Georgia", fixedSize: 29))
                            .foregroundStyle(Color(red: 164 / 255, green: 183 / 255, blue: 174 / 255))
                        Image("SplashMoneyBag")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 34)
                    }
                    .opacity(spendVisible ? 1 : 0)
                    .offset(y: spendVisible ? 0 : 10)
                }
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .opacity(splashOpacity)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.easeOut(duration: 0.38)) {
                spendVisible = true
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                splashOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            onFinished()
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    static let storageKey = "appearanceTheme"

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

@main
struct FendYourSpendApp: App {
    @UIApplicationDelegateAdaptor(FendYourSpendAppDelegate.self) private var appDelegate
    @StateObject private var model = LedgerModel()
    @State private var selectedTab = AppTab.home
    @State private var showingAdd = false
    @State private var pendingTransactionSavedToast = false
    @State private var transactionSavedToastVisible = false
    @State private var transactionSavedToastGeneration = 0
    @State private var showingBrandSplash: Bool
    @State private var keyboardVisible = false
    @AppStorage(OnboardingReleaseTracker.seenKey) private var onboardingSeen = false
    @AppStorage(AppTheme.storageKey) private var appTheme = AppTheme.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    private enum AppTab: String, CaseIterable { case home, growth, add, ledger
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .home: return "house"
            case .growth: return "chart.xyaxis.line"
            case .add: return "plus"
            case .ledger: return "list.bullet.rectangle"
            }
        }
    }
    init() {
        OnboardingReleaseTracker.prepare()
        FendYourSpendShortcuts.updateAppShortcutParameters()
        _showingBrandSplash = State(initialValue: !ProcessInfo.processInfo.arguments.contains("--ui-testing"))
        if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: OnboardingReleaseTracker.seenKey)
        }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if !onboardingSeen && (!ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.arguments.contains("--show-onboarding")) {
                    SMSOnboardingView { onboardingSeen = true }
                } else {
                    ZStack {
                        persistentDestination(.home) { MonthView(model: model) }
                        persistentDestination(.growth) { GrowthView(model: model) }
                        persistentDestination(.ledger) { LedgerView(model: model) }
                        if transactionSavedToastVisible {
                            Text("Transaction Saved!")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.dmPaper)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 44)
                                .background(Color.dmInk)
                                .clipShape(Capsule())
                                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .accessibilityIdentifier("transactionSavedToast")
                                .allowsHitTesting(false)
                                .zIndex(20)
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !keyboardVisible {
                            DockedTabBar(
                                tabs: AppTab.allCases,
                                selected: selectedTab,
                                title: { $0.title },
                                icon: { $0.icon },
                                isCenterAction: { $0 == .add },
                                action: { tab in
                                    dismissKeyboard()
                                    if tab == .add { showingAdd = true } else { selectedTab = tab }
                                }
                            )
                        }
                    }
                    .animation(.easeOut(duration: 0.16), value: keyboardVisible)
                    .tint(Color.dmFlow)
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                guard pendingTransactionSavedToast else { return }
                pendingTransactionSavedToast = false
                showTransactionSavedToast()
            }) {
                ManualView(model: model, onFinish: { saved in
                    pendingTransactionSavedToast = saved
                    showingAdd = false
                })
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    model.reload()
                }
            }
            .task {
                ReminderScheduler.apply(engine: model.engine)
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                if scenePhase == .active { model.refreshIfChanged() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
            #if DEBUG
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--simulate-sms-after-launch") || arguments.contains("--simulate-sms-in-sender") {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "dd/MM/yyyy"
                    let date = formatter.string(from: Date())
                    let message = "A/c *2468 debited by Rs.5.00 towards mandate for APPLE MEDIA on \(date).RRN:900000000022 Avl bal is Rs.6247.64-INDIAN BANK"
                    let messageInSender = arguments.contains("--simulate-sms-in-sender")
                    _ = await ShortcutSMSProcessor.shared.importMessage(
                        messageInSender ? nil : message,
                        sender: messageInSender ? message : "INDIAN BANK"
                    )
                }
            }
            #endif
            .overlay {
                if showingBrandSplash {
                    AnimatedBrandSplash {
                        showingBrandSplash = false
                    }
                }
            }
            .preferredColorScheme((AppTheme(rawValue: appTheme) ?? .system).colorScheme)
        }
    }

    private func showTransactionSavedToast() {
        transactionSavedToastGeneration += 1
        let generation = transactionSavedToastGeneration
        withAnimation(.easeOut(duration: 0.2)) {
            transactionSavedToastVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard transactionSavedToastGeneration == generation else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                transactionSavedToastVisible = false
            }
        }
    }

    private func persistentDestination<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .environment(\.destinationIsActive, selectedTab == tab)
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
            .zIndex(selectedTab == tab ? 1 : 0)
    }
}

struct ManualView: View {
    @ObservedObject var model: LedgerModel
    let onFinish: (_ saved: Bool) -> Void
    @State private var name = ""
    @State private var amount = ""
    @State private var income = false
    @State private var category = "Miscellaneous"
    @State private var date = Date()
    @State private var formError: String?
    @State private var nameInputError: String?
    @State private var amountInputError: String?
    @State private var validationAttempted = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, amount }
    private var amountLimitError: String? {
        AmountInputFormatter.exceedsTransactionLimit(amount)
            ? AmountInputFormatter.transactionLimitMessage
            : nil
    }
    private var nameIsValid: Bool {
        model.engine.manualNameValidationError(name: name) == nil
    }
    private var amountIsValid: Bool {
        model.engine.manualAmountValidationError(amount: AmountInputFormatter.normalized(amount)) == nil
    }
    private var nameValidationError: String? {
        if let nameInputError { return nameInputError }
        return validationAttempted ? model.engine.manualNameValidationError(name: name) : nil
    }
    private var amountValidationError: String? {
        if let amountInputError { return amountInputError }
        if let amountLimitError { return amountLimitError }
        return validationAttempted
            ? model.engine.manualAmountValidationError(amount: AmountInputFormatter.normalized(amount))
            : nil
    }
    var body: some View {
        NavigationStack {
            ScreenSurface {
                BrandHeader(title: "Add transaction")
                RaisedPanel {
                    if let loadError = model.engine.loadError { Text(loadError).foregroundStyle(Color.dmSpend) }
                    if let formError {
                        Text(formError)
                            .foregroundStyle(Color.dmSpend)
                            .accessibilityIdentifier("entryError")
                    }
                    HStack(spacing: 6) {
                        PaperSegment(title: "Expense", value: false, selection: $income)
                        PaperSegment(title: "Credit", value: true, selection: $income)
                    }
                    .onChange(of: income) { value in category = value ? "Income" : "Miscellaneous" }
                    .padding(4)
                    .background(Color.dmHairline.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    FieldLabel(text: "Name")
                    PaperNameField(
                        placeholder: income ? "Add sender or company name" : "Add restaurant or merchant name",
                        text: $name,
                        validationError: $nameInputError
                    )
                        .accessibilityIdentifier("entryName")
                        .focused($focusedField, equals: .name)
                        .onChange(of: name) { value in category = model.engine.suggestCategory(name: value, income: income) }
                    Text(nameValidationError ?? " ")
                        .font(.caption)
                        .foregroundStyle(nameValidationError == nil ? Color.clear : Color.dmSpend)
                        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                        .accessibilityHidden(nameValidationError == nil)
                        .accessibilityIdentifier("entryNameError")
                    FieldLabel(text: "Amount")
                    PaperAmountField(
                        placeholder: income ? "Enter the value received" : "Enter the value spent",
                        text: $amount,
                        validationError: $amountInputError
                    )
                        .accessibilityIdentifier("entryAmount")
                        .focused($focusedField, equals: .amount)
                    Text(amountValidationError ?? " ")
                        .font(.caption)
                        .foregroundStyle(amountValidationError == nil ? Color.clear : Color.dmSpend)
                        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                        .accessibilityHidden(amountValidationError == nil)
                        .accessibilityIdentifier("entryAmountError")
                    FieldLabel(text: income ? "Credit kind" : "Category")
                    ChipFlowLayout {
                        ForEach(income ? ["Income", "Own account transfer", "Settlement"] : model.engine.categories(), id: \.self) { option in
                            SelectableCategoryChip(
                                name: option,
                                selected: category == option,
                                accessibilityIdentifier: "entryCategoryOption-\(option)"
                            ) {
                                category = option
                            }
                        }
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .foregroundStyle(Color.dmInk)

                    Button("Save") {
                        validationAttempted = true
                        formError = nil
                        guard nameIsValid, amountIsValid else { return }
                        focusedField = nil
                        formError = model.addEntry(
                            name: name,
                            amount: AmountInputFormatter.normalized(amount),
                            category: category,
                            date: date,
                            income: income
                        )
                        if formError == nil { onFinish(true) }
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("saveEntry")
                    .disabled(model.engine.loadError != nil || amountLimitError != nil)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(false) }.accessibilityIdentifier("cancelEntry")
                }
            }
            .onDisappear { focusedField = nil }
        }
    }

}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: LedgerModel
    @AppStorage(OnboardingReleaseTracker.seenKey) private var onboardingSeen = true
    @AppStorage(AutomaticImportNotification.enabledKey) private var automaticImportNotificationsEnabled = false
    @AppStorage(AppTheme.storageKey) private var appTheme = AppTheme.system.rawValue
    @State private var showCategory = false
    @State private var deletion: String?
    @State private var error: String?
    @State private var reminderEnabled = false
    @State private var reminderTime = "21:30"
    @State private var reminderDigits = ReminderDigits.from24Hour("21:30")
    @State private var focusedReminderDigit: ReminderDigit?
    @State private var notificationPermissionDenied = false
    var body: some View {
        NavigationStack {
            ScreenSurface {
                HStack(alignment: .top, spacing: 12) {
                    BrandHeader(title: "Settings")
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.dmInk)
                            .frame(width: 44, height: 44)
                            .background(Color.dmPaperRaised)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.dmHairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close settings")
                    .accessibilityIdentifier("closeSettings")
                }
                appearanceSection
                dailyCheckInSection
                trackingCyclePicker
                if let error {
                    Text(error).font(.caption).foregroundStyle(Color.dmSpend)
                }
                categoriesSection
                shortcutSetupSection
                automaticImportNotificationSection
                privacySection
            }
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
                    refreshAutomaticImportNotificationPermission()
                }
                .alert("Notifications are off", isPresented: $notificationPermissionDenied) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Allow notifications for Fend Your Spend in iPhone Settings, then enable this option again.")
                }
        }
        .preferredColorScheme((AppTheme(rawValue: appTheme) ?? .system).colorScheme)
    }

    private var appearanceSection: some View {
        RaisedPanel {
            SectionHeading(title: "Appearance")
            HStack(spacing: 16) {
                Text("Theme")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dmInk)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(AppTheme.allCases) { theme in
                        PaperSegment(title: theme.title, value: theme.rawValue, selection: $appTheme)
                            .accessibilityIdentifier("theme-" + theme.rawValue)
                    }
                }
                .padding(3)
                .frame(width: 220)
                .background(Color.dmPaper)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmHairline, lineWidth: 1))
            }
        }
    }

    private var dailyCheckInSection: some View {
        RaisedPanel {
            SectionHeading(title: "Daily check-in")
            settingsToggleRow(
                title: "Expense reminder",
                subtitle: reminderEnabled ? "Reminder on" : "Reminder off",
                isOn: reminderEnabledBinding,
                identifier: "reminderToggle",
                statusIdentifier: "reminderStatus"
            )

            if reminderEnabled {
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
    }

    private var trackingCyclePicker: some View {
        RaisedPanel {
            SectionHeading(title: "Tracking cycle")
            StableMenu {
                ForEach(1...31, id: \.self) { day in
                    Button(String(day)) { monthStartBinding.wrappedValue = Int32(day) }
                }
            } label: {
                HStack {
                    Text("Start date").foregroundStyle(Color.dmInk)
                    Spacer()
                    Text(String(model.engine.monthStartDay())).foregroundStyle(Color.dmFlow)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Color.dmFlow)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trackingCycleMenu")
            Text("For shorter months, the cycle starts on the last day of the month.")
                .font(.caption)
                .foregroundStyle(Color.dmInkFaint)
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
            .buttonStyle(SecondaryPillButtonStyle())
            .accessibilityLabel("Add category")
            .accessibilityIdentifier("addCategory")
            ChipFlowLayout {
                ForEach(model.engine.categories(), id: \.self) { item in
                    CategoryChip(name: item, removable: item != "Miscellaneous") {
                        deletion = item
                    }
                }
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
                dismiss()
            } label: {
                Label("Open setup guide", systemImage: "arrow.right")
            }
            .buttonStyle(SecondaryPillButtonStyle())
            .accessibilityIdentifier("openSMSSetup")
        }
    }

    private var automaticImportNotificationSection: some View {
        RaisedPanel {
            settingsToggleRow(
                title: "Notify on auto-import",
                subtitle: "Alert when Fend Your Spend adds a transaction automatically",
                isOn: automaticImportNotificationBinding,
                identifier: "automaticImportNotificationToggle"
            )
        }
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        identifier: String,
        statusIdentifier: String? = nil
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.dmInk)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.dmInkFaint)
                    .accessibilityIdentifier(statusIdentifier ?? "\(identifier)Status")
            }
        }
        .tint(Color.dmIncome)
        .accessibilityIdentifier(identifier)
    }

    private var privacySection: some View {
        RaisedPanel {
            SectionHeading(title: "Privacy")
            Text("Your financial data stays on this device.")
                .font(.subheadline)
                .foregroundStyle(Color.dmInkSoft)
            Button {
                guard let url = URL(string: "https://mishraankit07.github.io/dailymint-privacy/") else { return }
                openURL(url)
            } label: {
                Label("View privacy policy", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(SecondaryPillButtonStyle())
            .accessibilityIdentifier("privacyPolicy")
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

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { reminderEnabled },
            set: updateReminderEnabled
        )
    }

    private var automaticImportNotificationBinding: Binding<Bool> {
        Binding(
            get: { automaticImportNotificationsEnabled },
            set: { enabled in
                guard enabled else {
                    automaticImportNotificationsEnabled = false
                    return
                }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        automaticImportNotificationsEnabled = granted
                        notificationPermissionDenied = !granted
                    }
                }
            }
        )
    }

    private func refreshAutomaticImportNotificationPermission() {
        guard automaticImportNotificationsEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral
            if !allowed {
                DispatchQueue.main.async {
                    automaticImportNotificationsEnabled = false
                }
            }
        }
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

    private func updateReminderEnabled(_ enabled: Bool) {
        let result = model.mutate { $0.setReminder(enabled: enabled, time: reminderTime) }
        error = result
        if result == nil {
            reminderEnabled = enabled
            ReminderScheduler.apply(engine: model.engine)
        }
    }

    private func reminderDigitField(_ digit: ReminderDigit) -> some View {
        let invalid = reminderDigits.invalidDigits.contains(digit)
        return ReminderDigitTextField(
            text: reminderDigitBinding(digit),
            isFocused: Binding(
                get: { focusedReminderDigit == digit },
                set: { if $0 { focusedReminderDigit = digit } else if focusedReminderDigit == digit { focusedReminderDigit = nil } }
            ),
            dismissKeyboard: focusedReminderDigit == nil,
            onEmptyBackspace: {
                guard let previous = digit.previous else { return }
                reminderDigits.set("", for: previous)
                focusedReminderDigit = previous
            },
            accessibilityIdentifier: "reminder\(digit.rawValue)"
        )
            .frame(width: 38, height: 42)
            .background(invalid ? Color.dmSpend.opacity(0.12) : Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(invalid ? Color.dmSpend : Color.dmHairline, lineWidth: 1)
            )
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

    var previous: ReminderDigit? {
        switch self {
        case .h1: return nil
        case .h2: return .h1
        case .m1: return .h2
        case .m2: return .m1
        }
    }
}

private struct ReminderDigitTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let dismissKeyboard: Bool
    let onEmptyBackspace: () -> Void
    let accessibilityIdentifier: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> DigitField {
        let field = DigitField()
        field.keyboardType = .numberPad
        field.textAlignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        field.textColor = UIColor(Color.dmInk)
        field.delegate = context.coordinator
        field.accessibilityIdentifier = accessibilityIdentifier
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .editingChanged)
        field.onEmptyBackspace = onEmptyBackspace
        return field
    }

    func updateUIView(_ field: DigitField, context: Context) {
        context.coordinator.parent = self
        field.onEmptyBackspace = onEmptyBackspace
        field.textColor = UIColor(Color.dmInk)
        if field.text != text { field.text = text }
        if isFocused && !field.isFirstResponder {
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                if coordinator.parent.isFocused { field.becomeFirstResponder() }
            }
        } else if dismissKeyboard && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ReminderDigitTextField
        init(_ parent: ReminderDigitTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            let digit = String((field.text ?? "").filter(\.isNumber).prefix(1))
            if field.text != digit { field.text = digit }
            parent.text = digit
        }

        func textFieldDidBeginEditing(_ textField: UITextField) { parent.isFocused = true }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.isFocused = false }
    }

    final class DigitField: UITextField {
        var onEmptyBackspace: (() -> Void)?
        override func deleteBackward() {
            if text?.isEmpty != false { onEmptyBackspace?() }
            super.deleteBackward()
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
            return "Enter a valid hour from 01 to 12."
        }
        if minuteText.count == 2, let minute = Int(minuteText), !(0...59).contains(minute) {
            return "Enter minutes from 00 to 59."
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
            ScreenSurface {
                BrandHeader(title: "Add category")
                RaisedPanel {
                    FieldLabel(text: "Category name")
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
