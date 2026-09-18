import SwiftUI
import Charts
import DailyMintCore
import UniformTypeIdentifiers

struct MonthView: View {
    @ObservedObject var model: LedgerModel
    let onSeeAll: () -> Void
    @State private var detail: Entry?
    var body: some View {
        NavigationStack {
            let summary = model.engine.monthSummary(today: model.engine.today())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Home")
                    MonthHero(summary: summary, model: model)
                    if summary.spent == 0 && summary.invested == 0 && summary.moneyIn == 0 {
                        RaisedPanel {
                            Text("No transactions in this cycle yet")
                                .font(.headline).foregroundStyle(Color.dmInk)
                            Text("Add an entry or import bank messages to start tracking.")
                                .font(.subheadline).foregroundStyle(Color.dmInkSoft)
                        }
                    }
                    if summary.spent > 0 {
                        SectionHeading(title: "Where it went")
                        HairlineBlock {
                            ForEach(summary.categories, id: \.name) { item in
                                CategoryLine(name: item.name, percent: item.percent, amount: "Rs " + model.engine.formatAmount(paise: item.paise))
                            }
                        }
                        SectionHeading(title: "Biggest spends")
                        HairlineBlock {
                            ForEach(summary.topFive, id: \.id) { entry in
                                Button { detail = entry } label: {
                                    TransactionLine(entry: entry, model: model)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button("See all transactions", action: onSeeAll)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("seeAllTransactions")
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .withSettings(model: model)
            .sheet(item: $detail) { TransactionDetailView(model: model, entry: $0) }
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
            Text("Spent this cycle").font(.caption.weight(.semibold)).foregroundStyle(Color.dmHeroMuted)
            Text("Rs " + model.engine.formatAmount(paise: summary.spent))
                .font(.system(size: 38, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dmHeroText)
                .minimumScaleFactor(0.65)
                .accessibilityIdentifier("spent")
            Text(summary.label).font(.caption).foregroundStyle(Color.dmHeroMuted)
            HStack(alignment: .top) {
                HeroStat(label: "Recorded in", value: "Rs " + model.engine.formatAmount(paise: summary.moneyIn), color: .dmIncome)
                    .accessibilityIdentifier("moneyIn")
                Spacer()
                HeroStat(label: "Invested", value: "Rs " + model.engine.formatAmount(paise: summary.invested), color: .dmInvest)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dmNav)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                Text(label).font(.caption2).foregroundStyle(Color.dmHeroMuted)
            }
            Text(value).font(.caption.weight(.bold)).foregroundStyle(Color.dmHeroText)
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
        let displayAmount = entry.type == "expense" ? entry.personalSpent : entry.paise
        HStack(spacing: 12) {
            IconBubble(category: entry.category)
            VStack(alignment: .leading) {
                Text(entry.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.dmInk).lineLimit(1)
                Text((entry.category == "Received" ? "Other income" : entry.category) + " · " + String(entry.date.prefix(10)))
                    .font(.caption).foregroundStyle(Color.dmInkFaint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((entry.type == "income" ? "+" : "-") + "Rs " + model.engine.formatAmount(paise: displayAmount))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(entry.type == "income" ? Color.dmIncome : Color.dmSpend)
                if entry.type == "expense" && displayAmount != entry.paise {
                    Text("Bank: Rs " + model.engine.formatAmount(paise: entry.paise))
                        .font(.caption2).foregroundStyle(Color.dmInkFaint)
                }
                if entry.ignored {
                    Text("Ignored").font(.caption2).foregroundStyle(Color.dmInkFaint)
                }
            }
        }
        Divider().background(Color.dmHairline)
    }
}

struct GrowthView: View {
    @ObservedObject var model: LedgerModel
    @State private var years = false
    @State private var count: Int32 = 3
    @State private var selectedPeriod: String?
    private var rangeOptions: [Int32] { years ? [1, 2, 3, 5] : [3, 6] }
    var body: some View {
        NavigationStack {
            let buckets = model.engine.trendBuckets(today: model.engine.today(), years: years, count: count)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Growth")
                    HStack(spacing: 6) {
                        PaperSegment(title: "Months", value: false, selection: $years)
                        PaperSegment(title: "Years", value: true, selection: $years)
                    }
                    .onChange(of: years) { value in count = value ? 1 : 3 }
                    .padding(4)
                    .background(Color.dmHairline.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 8) {
                        ForEach(rangeOptions, id: \.self) { value in
                            PaperOption(
                                title: String(value) + (years ? " years" : " months"),
                                active: count == value,
                                action: { count = value }
                            )
                        }
                    }

                    Text(years ? "Full calendar years" : "Full calendar months")
                        .font(.caption).foregroundStyle(Color.dmInkFaint)

                    RaisedPanel {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spending trend")
                                .font(.headline)
                                .foregroundStyle(Color.dmInk)
                            Text("Personal spent and invested")
                                .font(.caption)
                                .foregroundStyle(Color.dmInkFaint)
                        }
                        if buckets.allSatisfy({ $0.spent == 0 && $0.invested == 0 }) {
                            Text("No spending or investments in these periods.")
                                .font(.subheadline).foregroundStyle(Color.dmInkSoft)
                                .frame(maxWidth: .infinity, minHeight: 150)
                        } else {
                            Chart {
                                ForEach(buckets, id: \.label) { bucket in
                                    BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.spent) / 100))
                                        .foregroundStyle(by: .value("Type", "Personal spent")).position(by: .value("Type", "Personal spent"))
                                    BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.invested) / 100))
                                        .foregroundStyle(by: .value("Type", "Invested")).position(by: .value("Type", "Invested"))
                                }
                            }
                            .chartForegroundStyleScale(["Personal spent": Color.dmSpend, "Invested": Color.dmInvest])
                            .chartXAxis {
                                AxisMarks(values: buckets.map { $0.label }) { _ in
                                    AxisGridLine().foregroundStyle(Color.dmHairline)
                                    AxisTick().foregroundStyle(Color.dmInkFaint)
                                    AxisValueLabel().foregroundStyle(Color.dmInkSoft)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .trailing) { _ in
                                    AxisGridLine().foregroundStyle(Color.dmHairline.opacity(0.65))
                                    AxisTick().foregroundStyle(Color.dmInkFaint)
                                    AxisValueLabel().foregroundStyle(Color.dmInkSoft)
                                }
                            }
                            .frame(height: 220)
                        }
                    }
                    if !buckets.isEmpty {
                        SectionHeading(title: "Period details")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(buckets, id: \.label) { bucket in
                                    PaperOption(title: bucket.label, active: selectedPeriod == bucket.label,
                                                action: { selectedPeriod = bucket.label })
                                }
                            }
                        }
                        if let selected = buckets.first(where: { $0.label == selectedPeriod }) ?? buckets.last {
                            RaisedPanel {
                                Text(selected.label).font(.headline).foregroundStyle(Color.dmInk)
                                Text("Personal spent: Rs " + model.engine.formatAmount(paise: selected.spent))
                                    .foregroundStyle(Color.dmSpend)
                                Text("Invested: Rs " + model.engine.formatAmount(paise: selected.invested))
                                    .foregroundStyle(Color.dmInvest)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.dmPaper)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .withSettings(model: model)
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
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var editing: ReviewRow?
    @State private var discard = false
    @State private var picker = false
    @State private var summary: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                let stats = model.engine.monthSummary(today: model.engine.today())
                let rows = model.engine.reviewRows().filter { $0.entry != nil }
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Pending import")
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

                    Button {
                        picker = true
                    } label: {
                        Label("Import transaction file", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 44)
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
                            error = model.mutate { $0.saveReview() }
                            if error == nil { dismiss() }
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .withSettings(model: model)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("closeImport")
                    }
                }
                .fileImporter(isPresented: $picker, allowedContentTypes: [.plainText, .text]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey])
                        guard (values.fileSize ?? 0) <= 5_000_000 else { error = "This file is too large."; return }
                        let text = try String(contentsOf: url, encoding: .utf8)
                        error = model.mutate { $0.stageWal(text: text, fileName: url.lastPathComponent) }
                        if error == nil {
                            let rows = model.engine.reviewRows()
                            var counts = ["Transactions: \(rows.filter { $0.entry != nil }.count)"]
                            for (status, title) in [("new", "New"), ("already-recorded", "Already present"), ("repeated", "Repeated"), ("unrecognized", "Unrecognized")] {
                                let count = rows.filter { $0.status == status }.count
                                if count > 0 { counts.append("\(title): \(count)") }
                            }
                            summary = counts.joined(separator: "\n")
                        }
                    } catch { self.error = error.localizedDescription }
                }
                .alert("Import result", isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })) {
                    Button("OK") { summary = nil }
                } message: { Text(summary ?? "") }
                .confirmationDialog("Discard pending import?", isPresented: $discard) {
                    Button("Discard", role: .destructive) {
                        error = model.mutate { $0.discardReview() }
                        if error == nil { dismiss() }
                    }
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
                if reviewId != nil && entry.source != "manual" {
                    LabeledContent("Original amount", value: "Rs " + model.engine.formatAmount(paise: entry.paise))
                } else {
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                }
                Picker("Category", selection: $category) {
                    ForEach(entry.type == "income" ? ["Salary", "Other income", "Reimbursement", "Refund", "Own-account transfer", "Received"] : model.engine.categories(), id: \.self) { Text($0).tag($0) }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if reviewId == nil { Button("Delete", role: .destructive) { delete = true } }
            }.navigationTitle("Edit transaction").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            error = model.mutate { engine in
                                if let reviewId { return engine.editReview(id: reviewId, name: name, amount: amount, category: category) }
                                return engine.editEntry(id: entry.id, name: name, amount: amount, category: category, date: entry.date, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
                            }
                            if error == nil { dismiss() }
                        }
                    }
                }
                .onAppear { name = entry.name; amount = model.engine.formatAmount(paise: entry.paise); category = entry.category }
                .confirmationDialog("Delete transaction?", isPresented: $delete) {
                    Button("Delete", role: .destructive) {
                        error = model.mutate { $0.deleteEntry(id: entry.id, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) }
                        if error == nil { dismiss() }
                    }
                }
        }.presentationDetents([.medium, .large])
    }
}
