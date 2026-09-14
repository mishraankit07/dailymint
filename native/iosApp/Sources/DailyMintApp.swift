import SwiftUI
import DailyMintCore

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
                NavigationStack { Text("Coming soon").navigationTitle("Plan").withSettings(model: model) }.tabItem { Label("Plan", systemImage: "target") }.tag(AppTab.plan)
            }.tint(.green)
        }
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
            Form {
                if let loadError = model.engine.loadError { Text(loadError).foregroundStyle(.red) }
                Picker("Type", selection: $income) {
                    Text("Expense").tag(false)
                    Text("Income").tag(true)
                }.pickerStyle(.segmented)
                    .onChange(of: income) { value in category = value ? "Received" : "Miscellaneous" }
                TextField("Name", text: $name).accessibilityIdentifier("entryName")
                    .focused($focusedField, equals: .name)
                    .onChange(of: name) { value in category = model.engine.suggestCategory(name: value, income: income) }
                TextField("Amount", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("entryAmount")
                    .focused($focusedField, equals: .amount)
                Picker("Category", selection: $category) {
                    ForEach(income ? ["Salary", "Received"] : model.engine.categories(), id: \.self) { Text($0).tag($0) }
                }.accessibilityIdentifier("entryCategory")
                DatePicker("Date", selection: $date, displayedComponents: .date)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("entryError") }
                Button("Save") {
                    focusedField = nil
                    error = model.addEntry(name: name, amount: amount, category: category, date: date, income: income)
                    if error == nil { name = ""; amount = ""; category = income ? "Received" : "Miscellaneous"; saved = true }
                }.accessibilityIdentifier("saveEntry").disabled(model.engine.loadError != nil)
            }.navigationTitle("DailyMint").withSettings(model: model)
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
    var body: some View {
        NavigationStack {
            List {
                Picker("Tracking cycle starts", selection: Binding(get: { model.engine.monthStartDay() }, set: { value in error = model.apply(model.engine.setMonthStartDay(day: value)) })) {
                    ForEach(1...31, id: \.self) { Text(String($0)).tag(Int32($0)) }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section("Categories") {
                    ForEach(model.engine.categories(), id: \.self) { category in
                        HStack { Text(category); Spacer(); if category != "Miscellaneous" { Button { deletion = category } label: { Image(systemName: "xmark").foregroundStyle(.red) }.accessibilityLabel("Delete " + category) } }
                    }
                }
            }.navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showCategory = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add category").accessibilityIdentifier("addCategory")
                    }
                }
                .sheet(isPresented: $showCategory) { CategorySheet(model: model) }
                .confirmationDialog("Delete category? Transactions will move to Miscellaneous.", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                    Button("Delete", role: .destructive) { if let deletion { error = model.apply(model.engine.deleteCategory(name: deletion)) }; deletion = nil }
                }
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
            Form {
                TextField("Category name", text: $name).focused($focused)
                    .accessibilityIdentifier("categoryName").submitLabel(.done).onSubmit(save)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("categoryError") }
            }.navigationTitle("Add category").navigationBarTitleDisplayMode(.inline)
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
