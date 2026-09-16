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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Good evening")
                    MonthHero(summary: summary, model: model)
                    SectionHeading(title: "Where it went", trailing: summary.label)
                    MoneySplitPanel(summary: summary)
                    SectionHeading(title: "Outflow breakdown")
                    HairlineBlock {
                        if summary.categories.isEmpty { Text("No outflow yet.").foregroundStyle(Color.dmInkFaint) }
                        ForEach(summary.categories, id: \.name) { item in
                            CategoryLine(name: item.name, percent: item.percent, amount: "Rs " + model.engine.formatAmount(paise: item.paise))
                        }
                    }
                    SectionHeading(title: "Top 5 transactions")
                    HairlineBlock {
                        if summary.topFive.isEmpty { Text("No transactions yet.").foregroundStyle(Color.dmInkFaint) }
                        ForEach(summary.topFive, id: \.id) { entry in TransactionLine(entry: entry, model: model) }
                    }
                    Button(detailed ? "Collapse" : "Detailed report") { detailed.toggle() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("detailedReport")
                    if detailed {
                        SectionHeading(title: "Detailed report")
                        ForEach(summary.days, id: \.date) { day in
                            RaisedPanel {
                                HStack {
                                    Text(day.date).font(.headline).foregroundStyle(Color.dmInk)
                                    Spacer()
                                    Text("In Rs " + model.engine.formatAmount(paise: day.moneyIn) + " · Out Rs " + model.engine.formatAmount(paise: day.moneyOut))
                                        .font(.caption)
                                        .foregroundStyle(Color.dmInkFaint)
                                }
                                ForEach(day.entries, id: \.id) { entry in
                                    TransactionLine(entry: entry, model: model)
                                    if model.engine.canEdit(id: entry.id, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) {
                                        Button("Edit") { edit = entry }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("DailyMint")
            .withSettings(model: model)
            .sheet(item: $edit) { EntryEditSheet(model: model, entry: $0, reviewId: nil) }
        }
    }
}

struct MoneySplitPanel: View {
    let summary: MonthSummary
    private var moneyIn: Double { max(1, Double(summary.moneyIn)) }
    private var investedPercent: Double { summary.moneyIn > 0 ? Double(summary.invested) / moneyIn * 100 : 0 }
    private var spentPercent: Double { summary.spentPercent?.doubleValue ?? 0 }
    private var remainingPercent: Double { max(0, 100 - spentPercent - investedPercent) }
    private var visualTotal: Double { max(100, spentPercent + investedPercent) }
    var body: some View {
        RaisedPanel {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Color.dmInvest.frame(width: proxy.size.width * investedPercent / visualTotal)
                    Color.dmSpend.frame(width: proxy.size.width * spentPercent / visualTotal)
                    Color.dmHairline.frame(maxWidth: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: 14)
            HStack(spacing: 14) {
                SplitLegend(name: "Invested", percent: investedPercent, color: .dmInvest)
                SplitLegend(name: "Spent", percent: spentPercent, color: .dmSpend)
                SplitLegend(name: "Remaining", percent: remainingPercent, color: .dmHairline)
            }
        }
    }
}

struct SplitLegend: View {
    let name: String
    let percent: Double
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name + " · " + String(Int(percent.rounded())) + "%")
                .font(.caption)
                .foregroundStyle(Color.dmInkSoft)
        }
    }
}

struct MonthHero: View {
    let summary: MonthSummary
    @ObservedObject var model: LedgerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remaining this month").font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.725, green: 0.776, blue: 0.737))
            Text("Rs " + model.engine.formatAmount(paise: summary.remaining))
                .font(.system(size: 38, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dmPaper)
                .minimumScaleFactor(0.65)
            HStack(alignment: .top) {
                HeroStat(label: "Money in", value: "Rs " + model.engine.formatAmount(paise: summary.moneyIn), color: .dmIncome)
                    .accessibilityIdentifier("moneyIn")
                Spacer()
                HeroStat(label: "Spent", value: "Rs " + model.engine.formatAmount(paise: summary.spent), color: .dmSpend)
                    .accessibilityIdentifier("spent")
                Spacer()
                HeroStat(label: "Invested", value: "Rs " + model.engine.formatAmount(paise: summary.invested), color: .dmInvest)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dmInk)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct HeroStat: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.caption2).foregroundStyle(Color(red: 0.725, green: 0.776, blue: 0.737))
            }
            Text(value).font(.caption.weight(.bold)).foregroundStyle(Color.dmPaper)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + ": " + value)
    }
}

struct CategoryLine: View {
    let name: String
    let percent: Double
    let amount: String
    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Color.dmInk).frame(width: 92, alignment: .leading)
            ProgressView(value: min(1, max(0, percent / 100))).tint(categoryColor(name))
            Text(amount).font(.caption).foregroundStyle(Color.dmInkSoft).frame(width: 82, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }
}

extension Entry: Identifiable {}

struct TransactionLine: View {
    let entry: Entry
    @ObservedObject var model: LedgerModel
    var body: some View {
        HStack(spacing: 12) {
            IconBubble(category: entry.category)
            VStack(alignment: .leading) {
                Text(entry.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.dmInk).lineLimit(1)
                Text(entry.category + " · " + String(entry.date.prefix(10))).font(.caption).foregroundStyle(Color.dmInkFaint)
            }
            Spacer()
            Text((entry.type == "income" ? "+" : "-") + "Rs " + model.engine.formatAmount(paise: entry.paise))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(entry.type == "income" ? Color.dmIncome : Color.dmSpend)
        }
        Divider().background(Color.dmHairline)
    }
}

struct GrowthView: View {
    @ObservedObject var model: LedgerModel
    @State private var years = false
    @State private var count: Int32 = 3
    var body: some View {
        NavigationStack {
            let buckets = model.engine.trendBuckets(today: model.engine.today(), years: years, count: count)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                BrandHeader(title: "Growth")
                Picker("Period", selection: $years) {
                    Text("Months").tag(false); Text("Years").tag(true)
                }.pickerStyle(.segmented).onChange(of: years) { value in count = value ? 1 : 3 }
                Picker("Range", selection: $count) {
                    ForEach(years ? [1, 2, 3, 5] : [3, 6], id: \.self) { value in
                        Text(String(value) + (years ? " years" : " months")).tag(Int32(value))
                    }
                }
                RaisedPanel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(years ? "Yearly flow" : "Monthly flow")
                            .font(.headline)
                            .foregroundStyle(Color.dmInk)
                        Text("Money in vs. spent vs. invested")
                            .font(.caption)
                            .foregroundStyle(Color.dmInkFaint)
                    }
                    Chart {
                        ForEach(buckets, id: \.label) { bucket in
                            BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.moneyIn) / 100))
                                .foregroundStyle(by: .value("Type", "Money in")).position(by: .value("Type", "Money in"))
                            BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.spent) / 100))
                                .foregroundStyle(by: .value("Type", "Spent")).position(by: .value("Type", "Spent"))
                            BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.invested) / 100))
                                .foregroundStyle(by: .value("Type", "Invested")).position(by: .value("Type", "Invested"))
                        }
                    }
                    .chartForegroundStyleScale(["Money in": Color.dmIncome, "Spent": Color.dmSpend, "Invested": Color.dmInvest])
                    .frame(height: 220)
                    Text("Money in, spending and investments across calendar periods.").font(.caption).foregroundStyle(Color.dmInkSoft)
                }
                RaisedPanel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wealth Progress")
                            .font(.headline)
                            .foregroundStyle(Color.dmInk)
                        Text("Remaining money in bank plus investment")
                            .font(.caption)
                            .foregroundStyle(Color.dmInkFaint)
                    }
                    Chart(buckets, id: \.label) { bucket in
                        LineMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.wealth) / 100)).foregroundStyle(Color.dmIncome)
                        PointMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.wealth) / 100)).foregroundStyle(Color.dmIncome)
                    }.frame(height: 200)
                }
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("Growth").withSettings(model: model)
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
            ScrollView {
                let stats = model.engine.monthSummary(today: model.engine.today())
                let rows = model.engine.reviewRows().filter { $0.entry != nil }
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Import")
                    RaisedPanel {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Today's spend").font(.caption.weight(.semibold)).foregroundStyle(Color.dmInkFaint)
                                Text("Rs " + model.engine.formatAmount(paise: stats.todaySpend))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.dmSpend)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Week's spend").font(.caption.weight(.semibold)).foregroundStyle(Color.dmInkFaint)
                                Text("Rs " + model.engine.formatAmount(paise: stats.weekSpend))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.dmInk)
                            }
                        }
                    }

                    RaisedPanel {
                        Button {
                            picker = true
                        } label: {
                            Label("Import transaction file", systemImage: "tray.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.dmInk)
                        .accessibilityIdentifier("importFile")

                        if !model.engine.reviewFile().isEmpty {
                            Text(model.engine.reviewFile()).font(.caption).foregroundStyle(Color.dmInkFaint)
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(Color.dmSpend)
                        }
                    }

                    if !rows.isEmpty {
                        SectionHeading(title: "Imported transactions", trailing: String(rows.count) + " rows")
                        ForEach(rows, id: \.id) { row in
                            if let entry = row.entry {
                                RaisedPanel {
                                    TransactionLine(entry: entry, model: model)
                                    if row.status == "new" {
                                        Button("Edit") { editing = row }
                                            .buttonStyle(.bordered)
                                            .tint(Color.dmFlow)
                                    } else {
                                        Text("Already recorded").font(.caption.weight(.semibold)).foregroundStyle(Color.dmIncome)
                                    }
                                }
                            }
                        }
                    }

                    if !model.engine.reviewRows().isEmpty {
                        Button("Reviewed, save to ledger") {
                            error = model.apply(model.engine.saveReview())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.dmInk)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("saveReview")

                        Button("Discard import", role: .destructive) { discard = true }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("Import")
            .withSettings(model: model)
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
