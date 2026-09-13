import SwiftUI
import Charts
import UniformTypeIdentifiers
import DailyMintCore

struct MonthView: View {
    @ObservedObject var model: LedgerModel
    @State private var detailed = false
    @State private var edit: Entry?
    var body: some View {
        NavigationStack {
            let summary = model.engine.monthSummary(today: model.engine.today())
            List {
                Section(summary.label) {
                    Text("Money in: Rs " + model.engine.formatAmount(paise: summary.moneyIn)).accessibilityIdentifier("moneyIn")
                    Text("Spent: Rs " + model.engine.formatAmount(paise: summary.spent)).accessibilityIdentifier("spent")
                    Text("Invested: Rs " + model.engine.formatAmount(paise: summary.invested))
                    Text("Remaining: Rs " + model.engine.formatAmount(paise: summary.remaining))
                }
                Section("Money split") {
                    split("Spent", summary.spentPercent?.doubleValue, saved: false)
                    split("Saved/Invested", summary.savedInvestedPercent?.doubleValue, saved: true)
                    Text("Target 20%").font(.caption)
                }
                Section("Outflow breakdown") {
                    ForEach(summary.categories, id: \.name) { item in
                        HStack { Text(item.name); Spacer(); Text(String(Int(item.percent.rounded())) + "%"); Text("Rs " + model.engine.formatAmount(paise: item.paise)) }
                    }
                }
                Section("Top 5 transactions") {
                    ForEach(summary.topFive, id: \.id) { entry in TransactionLine(entry: entry, model: model) }
                }
                Button(detailed ? "Collapse" : "Detailed report") { detailed.toggle() }.accessibilityIdentifier("detailedReport")
                if detailed {
                    ForEach(summary.days, id: \.date) { day in
                        Section(day.date + " · In Rs " + model.engine.formatAmount(paise: day.moneyIn) + " · Out Rs " + model.engine.formatAmount(paise: day.moneyOut)) {
                            ForEach(day.entries, id: \.id) { entry in
                                VStack(alignment: .leading) {
                                    TransactionLine(entry: entry, model: model)
                                    if model.engine.canEdit(id: entry.id, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) {
                                        Button("Edit") { edit = entry }
                                    }
                                }
                            }
                        }
                    }
                }
            }.navigationTitle("DailyMint").withSettings(model: model)
                .sheet(item: $edit) { EntryEditSheet(model: model, entry: $0, reviewId: nil) }
        }
    }
    @ViewBuilder private func split(_ name: String, _ percent: Double?, saved: Bool) -> some View {
        Text(name + ": " + (percent.map { String(Int($0.rounded())) + "%" } ?? "--"))
        ProgressView(value: min(1, max(0, (percent ?? 0) / 100)))
            .tint((saved ? (percent ?? 0) >= 20 : (percent ?? 0) <= 80) ? .green : .red)
    }
}

extension Entry: Identifiable {}

struct TransactionLine: View {
    let entry: Entry
    @ObservedObject var model: LedgerModel
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.name)
                Text(entry.category + " · " + String(entry.date.prefix(10))).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text((entry.type == "income" ? "+" : "-") + "Rs " + model.engine.formatAmount(paise: entry.paise))
                .foregroundStyle(entry.type == "income" ? .green : .primary)
        }
    }
}

struct GrowthView: View {
    @ObservedObject var model: LedgerModel
    @State private var years = false
    @State private var count: Int32 = 3
    var body: some View {
        NavigationStack {
            let buckets = model.engine.trendBuckets(today: model.engine.today(), years: years, count: count)
            List {
                Picker("Period", selection: $years) {
                    Text("Months").tag(false); Text("Years").tag(true)
                }.pickerStyle(.segmented).onChange(of: years) { value in count = value ? 1 : 3 }
                Picker("Range", selection: $count) {
                    ForEach(years ? [1, 2, 3, 5] : [3, 6], id: \.self) { value in
                        Text(String(value) + (years ? " years" : " months")).tag(Int32(value))
                    }
                }
                Section("Money movement") {
                    Chart {
                        ForEach(buckets, id: \.label) { bucket in
                            BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.moneyIn) / 100))
                                .foregroundStyle(by: .value("Type", "Money in")).position(by: .value("Type", "Money in"))
                            BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.spent) / 100))
                                .foregroundStyle(by: .value("Type", "Spent")).position(by: .value("Type", "Spent"))
                            BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.invested) / 100))
                                .foregroundStyle(by: .value("Type", "Invested")).position(by: .value("Type", "Invested"))
                        }
                    }.chartForegroundStyleScale(["Money in": Color.green, "Spent": Color.red, "Invested": Color.blue]).frame(height: 220)
                    Text("Money in, spending and investments across calendar periods.").font(.caption)
                }
                Section("Wealth Progress") {
                    Chart(buckets, id: \.label) { bucket in
                        LineMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.wealth) / 100)).foregroundStyle(.green)
                        PointMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.wealth) / 100)).foregroundStyle(.green)
                    }.frame(height: 200)
                    Text("Remaining money in bank plus investment.").font(.caption)
                }
            }.navigationTitle("Growth").withSettings(model: model)
        }
    }
}

struct SettingsAccess: ViewModifier {
    @ObservedObject var model: LedgerModel
    @State private var visible = false
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { visible = true } label: { Image(systemName: "gearshape") }.accessibilityIdentifier("settings")
            }
        }.sheet(isPresented: $visible) { SettingsView(model: model) }
    }
}
extension View {
    func withSettings(model: LedgerModel) -> some View { modifier(SettingsAccess(model: model)) }
}

struct ImportView: View {
    @ObservedObject var model: LedgerModel
    @State private var picker = false
    @State private var error: String?
    @State private var summary: String?
    @State private var editing: ReviewRow?
    @State private var discard = false
    var body: some View {
        NavigationStack {
            List {
                let stats = model.engine.monthSummary(today: model.engine.today())
                Text("Today's spend: Rs " + model.engine.formatAmount(paise: stats.todaySpend))
                Text("Week's spend: Rs " + model.engine.formatAmount(paise: stats.weekSpend))
                Button("Import transaction file") { picker = true }.accessibilityIdentifier("importFile")
                if !model.engine.reviewFile().isEmpty { Text(model.engine.reviewFile()).font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(model.engine.reviewRows().filter { $0.entry != nil }, id: \.id) { row in
                    if let entry = row.entry {
                        VStack(alignment: .leading) {
                            TransactionLine(entry: entry, model: model)
                            if row.status == "new" { Button("Edit") { editing = row } }
                            else { Text("Already recorded").font(.caption).foregroundStyle(.green) }
                        }
                    }
                }
                if !model.engine.reviewRows().isEmpty {
                    Button("Reviewed, save to ledger") { error = model.apply(model.engine.saveReview()) }.accessibilityIdentifier("saveReview")
                    Button("Discard import", role: .destructive) { discard = true }
                }
            }.navigationTitle("Import").withSettings(model: model)
                .fileImporter(isPresented: $picker, allowedContentTypes: [.plainText, .text]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        guard (values.fileSize ?? 0) <= 5_000_000 else { error = "This file is too large."; return }
                        let text = try String(contentsOf: url, encoding: .utf8)
                        error = model.apply(model.engine.stageWal(text: text, fileName: url.lastPathComponent))
                        if error == nil {
                            let rows = model.engine.reviewRows()
                            var counts = ["Transactions: " + String(rows.filter { $0.entry != nil }.count)]
                            for (status, title) in [("new", "New"), ("already-recorded", "Already recorded"), ("repeated", "Repeated"), ("unrecognized", "Unrecognized")] {
                                let count = rows.filter { $0.status == status }.count
                                if count > 0 { counts.append(title + ": " + String(count)) }
                            }
                            summary = counts.joined(separator: "\n")
                        }
                    } catch { self.error = error.localizedDescription }
                }
                .alert("Import result", isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })) {
                    Button("OK") { summary = nil }
                } message: { Text(summary ?? "") }
                .confirmationDialog("Discard pending import?", isPresented: $discard) {
                    Button("Discard", role: .destructive) { error = model.apply(model.engine.discardReview()) }
                }
                .sheet(item: $editing) { row in
                    if let entry = row.entry { EntryEditSheet(model: model, entry: entry, reviewId: row.id) }
                }
        }
    }
}
extension ReviewRow: Identifiable {}

struct EntryEditSheet: View {
    @ObservedObject var model: LedgerModel
    let entry: Entry
    let reviewId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var category = ""
    @State private var error: String?
    @State private var delete = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Amount", text: $amount).keyboardType(.decimalPad)
                Picker("Category", selection: $category) {
                    ForEach(entry.type == "income" ? ["Salary", "Received"] : model.engine.categories(), id: \.self) { Text($0).tag($0) }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if reviewId == nil { Button("Delete", role: .destructive) { delete = true } }
            }.navigationTitle("Edit transaction").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let result: SaveResult
                            if let reviewId { result = model.engine.editReview(id: reviewId, name: name, amount: amount, category: category) }
                            else { result = model.engine.editEntry(id: entry.id, name: name, amount: amount, category: category, date: entry.date, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) }
                            error = model.apply(result)
                            if error == nil { dismiss() }
                        }
                    }
                }
                .onAppear { name = entry.name; amount = model.engine.formatAmount(paise: entry.paise); category = entry.category }
                .confirmationDialog("Delete transaction?", isPresented: $delete) {
                    Button("Delete", role: .destructive) {
                        error = model.apply(model.engine.deleteEntry(id: entry.id, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000)))
                        if error == nil { dismiss() }
                    }
                }
        }.presentationDetents([.medium, .large])
    }
}

