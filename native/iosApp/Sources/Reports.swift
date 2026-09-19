import SwiftUI
import Charts
import DailyMintCore

struct MonthView: View {
    @ObservedObject var model: LedgerModel
    let onSeeAll: () -> Void
    @State private var detail: Entry?
    private var greeting: String {
        Self.greeting(for: Date(), arguments: ProcessInfo.processInfo.arguments)
    }

    static func greeting(for date: Date, arguments: [String] = []) -> String {
        let hour = arguments
            .first { $0.hasPrefix("--test-hour=") }
            .flatMap { Int($0.replacingOccurrences(of: "--test-hour=", with: "")) }
            .map { max(0, min(23, $0)) }
            ?? Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            let summary = model.engine.monthSummary(today: model.engine.today())
            ScreenSurface {
                BrandHeader(title: greeting)
                if let loadError = model.engine.loadError {
                    RaisedPanel {
                        Text("Ledger unavailable")
                            .font(.headline).foregroundStyle(Color.dmSpend)
                        Text(loadError).font(.subheadline).foregroundStyle(Color.dmInkSoft)
                    }
                } else {
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
                        RaisedPanel {
                            ForEach(summary.categories, id: \.name) { item in
                                CategoryLine(name: item.name, percent: item.percent, amount: "Rs " + model.engine.formatAmount(paise: item.paise))
                            }
                        }
                        SectionHeading(title: "Biggest spends")
                        RaisedPanel {
                            ForEach(summary.topFive, id: \.id) { entry in
                                Button { detail = entry } label: {
                                    TransactionLine(entry: entry, model: model)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button("See all transactions", action: onSeeAll)
                        .buttonStyle(SecondaryPillButtonStyle())
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("seeAllTransactions")
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .withSettings(model: model)
            .sheet(item: $detail) { TransactionDetailView(model: model, entry: $0) }
        }
    }
}

struct MonthHero: View {
    let summary: MonthSummary
    @ObservedObject var model: LedgerModel
    private var cycleRange: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: summary.start),
              let endExclusive = formatter.date(from: summary.endExclusive),
              let end = formatter.calendar.date(byAdding: .day, value: -1, to: endExclusive) else {
            return summary.label
        }
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: start) + " - " + formatter.string(from: end)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spent this cycle").font(.caption.weight(.semibold)).foregroundStyle(Color.dmHeroMuted)
            Text("Rs " + model.engine.formatAmount(paise: summary.spent))
                .font(.system(size: 38, weight: .semibold, design: .serif))
                .foregroundStyle(Color.dmHeroText)
                .minimumScaleFactor(0.65)
                .accessibilityIdentifier("spent")
            Text(cycleRange).font(.caption).foregroundStyle(Color.dmHeroMuted)
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
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Color.dmInk).frame(width: 98, alignment: .leading)
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
                Text((entry.category == "Received" ? "Other income" : entry.category) + " · " + model.engine.transactionDay(date: entry.date))
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
    private var safeCount: Int32 {
        rangeOptions.contains(count) ? count : rangeOptions[0]
    }
    var body: some View {
        NavigationStack {
            let buckets = model.engine.trendBuckets(today: model.engine.today(), years: years, count: safeCount)
            ScreenSurface {
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
                            active: safeCount == value,
                            action: { count = value }
                        )
                    }
                }

                Text(years ? "Full calendar years" : "Full calendar months")
                    .font(.caption).foregroundStyle(Color.dmInkFaint)

                RaisedPanel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Money movement")
                            .font(.headline)
                            .foregroundStyle(Color.dmInk)
                        Text("Grouped by \(years ? "calendar year" : "calendar month")")
                            .font(.caption)
                            .foregroundStyle(Color.dmInkFaint)
                    }
                    if buckets.allSatisfy({ $0.spent == 0 && $0.invested == 0 && $0.moneyIn == 0 }) {
                        Text("No movement in these periods.")
                            .font(.subheadline).foregroundStyle(Color.dmInkSoft)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        Chart {
                            ForEach(buckets, id: \.label) { bucket in
                                BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.moneyIn) / 100))
                                    .foregroundStyle(by: .value("Type", "Money in"))
                                    .position(by: .value("Type", "Money in"))
                                BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.spent) / 100))
                                    .foregroundStyle(by: .value("Type", "Personal spent"))
                                    .position(by: .value("Type", "Personal spent"))
                                BarMark(x: .value("Period", bucket.label), y: .value("Rupees", Double(bucket.invested) / 100))
                                    .foregroundStyle(by: .value("Type", "Invested"))
                                    .position(by: .value("Type", "Invested"))
                            }
                        }
                        .chartForegroundStyleScale(["Money in": Color.dmIncome, "Personal spent": Color.dmSpend, "Invested": Color.dmInvest])
                        .chartLegend(position: .bottom, alignment: .leading)
                        .chartXAxis {
                            AxisMarks(values: buckets.map { $0.label }) { _ in
                                AxisGridLine().foregroundStyle(Color.dmHairline)
                                AxisTick().foregroundStyle(Color.dmInkFaint)
                                AxisValueLabel()
                                    .font(.caption2)
                                    .foregroundStyle(Color.dmInkSoft)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { _ in
                                AxisGridLine().foregroundStyle(Color.dmHairline.opacity(0.65))
                                AxisTick().foregroundStyle(Color.dmInkFaint)
                                AxisValueLabel()
                                    .font(.caption2)
                                    .foregroundStyle(Color.dmInkSoft)
                            }
                        }
                        .frame(height: 240)
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
                            Text("Money in: Rs " + model.engine.formatAmount(paise: selected.moneyIn))
                                .foregroundStyle(Color.dmIncome)
                            Text("Personal spent: Rs " + model.engine.formatAmount(paise: selected.spent))
                                .foregroundStyle(Color.dmSpend)
                            Text("Invested: Rs " + model.engine.formatAmount(paise: selected.invested))
                                .foregroundStyle(Color.dmInvest)
                        }
                    }
                }
            }
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
        content
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                Button { visible = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.dmPaperRaised)
                            .overlay(Circle().stroke(Color.dmHairline, lineWidth: 1))
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.dmFlow)
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 20)
                .accessibilityIdentifier("settings")
            }
            .sheet(isPresented: $visible) { SettingsView(model: model) }
    }
}
extension View {
    func withSettings(model: LedgerModel) -> some View { modifier(SettingsAccess(model: model)) }
}

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
            ScreenSurface {
                BrandHeader(title: "Edit transaction")
                RaisedPanel {
                    FieldLabel(text: "Name")
                    PaperField(placeholder: "Name", text: $name)
                    if reviewId != nil && entry.source != "manual" {
                        detailLine("Original amount", "Rs " + model.engine.formatAmount(paise: entry.paise))
                    } else {
                        FieldLabel(text: "Amount")
                        PaperField(placeholder: "Amount", text: $amount, keyboard: .decimalPad)
                    }
                    FieldLabel(text: entry.type == "income" ? "Credit kind" : "Category")
                    Picker("Category", selection: $category) {
                        ForEach(entry.type == "income" ? ["Salary", "Other income", "Reimbursement", "Refund", "Own-account transfer", "Received"] : model.engine.categories(), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.dmFlow)
                    if let error { Text(error).foregroundStyle(Color.dmSpend) }
                    if reviewId == nil {
                        Button("Delete", role: .destructive) { delete = true }
                            .buttonStyle(DestructivePillButtonStyle())
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Color.dmInkSoft)
            Spacer()
            Text(value).foregroundStyle(Color.dmInk).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
