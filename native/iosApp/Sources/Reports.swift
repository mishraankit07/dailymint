import SwiftUI
import Charts
import DailyMintCore

struct MonthView: View {
    @ObservedObject var model: LedgerModel
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
                            Text("Add an entry or use automatic transaction capture to start tracking.")
                                .font(.subheadline).foregroundStyle(Color.dmInkSoft)
                        }
                    }
                    CycleAllocation(summary: summary)
                    if summary.spent > 0 || summary.invested > 0 {
                        SectionHeading(title: "Where it went")
                        RaisedPanel {
                            ForEach(summary.categories, id: \.name) { item in
                                CategoryLine(
                                    name: item.name,
                                    percentOfMoneyIn: summary.moneyIn > 0
                                        ? Double(item.paise) * 100 / Double(summary.moneyIn)
                                        : 0,
                                    amount: "Rs " + model.engine.formatAmount(paise: item.paise)
                                )
                            }
                        }
                        if !summary.topFive.isEmpty {
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
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .withSettings(model: model)
            .sheet(item: $detail) { TransactionDetailView(model: model, entry: $0) }
        }
    }
}

struct CycleAllocation: View {
    let summary: MonthSummary

    var body: some View {
        RaisedPanel {
            SectionHeading(title: "Cycle allocation")
            if summary.allocationInvestedPercent < 0 {
                Text("Add income to see how this cycle is allocated.")
                    .font(.subheadline)
                    .foregroundStyle(Color.dmInkSoft)
            } else {
                GeometryReader { proxy in
                    let invested = max(0, Double(summary.allocationInvestedPercent))
                    let spent = max(0, Double(summary.allocationSpentPercent))
                    let left = max(0, Double(summary.allocationLeftPercent))
                    let scale = max(100, invested + spent + left)
                    HStack(spacing: 0) {
                        Color.dmInvest.frame(width: proxy.size.width * invested / scale)
                        Color.dmSpend.frame(width: proxy.size.width * spent / scale)
                        Color.dmInkFaint.opacity(0.35).frame(width: proxy.size.width * left / scale)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                HStack(spacing: 12) {
                    allocationLegend("Invested", summary.allocationInvestedPercent, .dmInvest)
                    allocationLegend("Spent", summary.allocationSpentPercent, .dmSpend)
                    allocationLegend("Left", summary.allocationLeftPercent, .dmInkFaint)
                }
                if summary.allocationExceedsIncome {
                    Text("Outflows exceed earned income; Left is zero.")
                        .font(.caption)
                        .foregroundStyle(Color.dmSpend)
                }
            }
        }
    }

    private func allocationLegend(_ title: String, _ percent: Int32, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) · \(percent)%")
                .font(.caption2)
                .foregroundStyle(Color.dmInkSoft)
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
            Text("This cycle").font(.caption.weight(.semibold)).foregroundStyle(Color.dmHeroMuted)
            Text(cycleRange).font(.caption).foregroundStyle(Color.dmHeroMuted)
            HStack(alignment: .top, spacing: 12) {
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
    let percentOfMoneyIn: Double
    let amount: String
    private var fill: Double { min(1, max(0, percentOfMoneyIn / 100)) }
    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(Color.dmInk).frame(width: 98, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dmHairline)
                    Capsule()
                        .fill(categoryColor(name))
                        .frame(width: proxy.size.width * fill)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
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
                Text(entry.category + " · " + model.engine.transactionDay(date: entry.date))
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
            }
        }
        Divider().background(Color.dmHairline)
    }
}

struct GrowthView: View {
    @ObservedObject var model: LedgerModel
    @State private var years = false
    @State private var count: Int32 = 3
    private var rangeOptions: [Int32] { years ? [1, 2, 3, 5] : [3, 6] }
    private var safeCount: Int32 {
        rangeOptions.contains(count) ? count : rangeOptions[0]
    }
    private func rangeTitle(_ value: Int32) -> String {
        let unit = years ? (value == 1 ? "year" : "years") : "months"
        return "\(value) \(unit)"
    }
    private func periodLabel(_ label: String) -> String {
        if years { return String(label.prefix(4)) }
        let parts = label.split(separator: "-")
        guard parts.count >= 2,
              let month = Int(parts[1]),
              month >= 1,
              month <= 12 else { return label }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let names = safeCount == 3 ? formatter.monthSymbols : formatter.shortMonthSymbols
        return names?[month - 1] ?? label
    }
    var body: some View {
        NavigationStack {
            let buckets = model.engine.trendBuckets(today: model.engine.today(), years: years, count: safeCount)
            ScreenSurface {
                BrandHeader(title: "Growth")
                VStack(alignment: .leading, spacing: 8) {
                    StableMenu {
                        Button("Months") {
                            years = false
                            count = 3
                        }
                        Button("Years") {
                            years = true
                            count = 1
                        }
                    } label: {
                        periodMenuRow(title: "Period", value: years ? "Years" : "Months")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("growthPeriodMenu")

                    StableMenu {
                        ForEach(rangeOptions, id: \.self) { value in
                            Button(rangeTitle(value)) { count = value }
                        }
                    } label: {
                        periodMenuRow(title: "Range", value: rangeTitle(safeCount))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("growthRangeMenu")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                            AxisMarks(values: buckets.map { $0.label }) { value in
                                AxisGridLine().foregroundStyle(Color.dmHairline)
                                AxisTick().foregroundStyle(Color.dmInkFaint)
                                AxisValueLabel {
                                    if let label = value.as(String.self) {
                                        Text(periodLabel(label))
                                            .font(.caption2)
                                            .foregroundStyle(Color.dmInkSoft)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { value in
                                AxisGridLine().foregroundStyle(Color.dmHairline.opacity(0.65))
                                AxisTick().foregroundStyle(Color.dmInkFaint)
                                AxisValueLabel {
                                    if let rupees = value.as(Double.self) {
                                        Text(model.engine.formatAmount(paise: Int64(rupees * 100)))
                                            .font(.caption2)
                                            .foregroundStyle(Color.dmInkSoft)
                                    }
                                }
                            }
                        }
                        .frame(height: 240)
                    }
                }
                RaisedPanel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved + invested")
                            .font(.headline)
                            .foregroundStyle(Color.dmInk)
                        Text("For each \(years ? "calendar year" : "calendar month")")
                            .font(.caption)
                            .foregroundStyle(Color.dmInkFaint)
                    }
                    if buckets.allSatisfy({ $0.spent == 0 && $0.invested == 0 && $0.moneyIn == 0 }) {
                        Text("No movement in these periods.")
                            .font(.subheadline)
                            .foregroundStyle(Color.dmInkSoft)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        Chart {
                            ForEach(buckets, id: \.label) { bucket in
                                LineMark(
                                    x: .value("Period", bucket.label),
                                    y: .value("Rupees", Double(bucket.savedAndInvested) / 100)
                                )
                                .foregroundStyle(Color.dmFlow)
                                .interpolationMethod(.linear)
                                PointMark(
                                    x: .value("Period", bucket.label),
                                    y: .value("Rupees", Double(bucket.savedAndInvested) / 100)
                                )
                                .foregroundStyle(Color.dmFlow)
                            }
                        }
                        .chartLegend(.hidden)
                        .chartXAxis {
                            AxisMarks(values: buckets.map { $0.label }) { value in
                                AxisGridLine().foregroundStyle(Color.dmHairline)
                                AxisTick().foregroundStyle(Color.dmInkFaint)
                                AxisValueLabel {
                                    if let label = value.as(String.self) {
                                        Text(periodLabel(label))
                                            .font(.caption2)
                                            .foregroundStyle(Color.dmInkSoft)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { value in
                                AxisGridLine().foregroundStyle(Color.dmHairline.opacity(0.65))
                                AxisTick().foregroundStyle(Color.dmInkFaint)
                                AxisValueLabel {
                                    if let rupees = value.as(Double.self) {
                                        Text(model.engine.formatAmount(paise: Int64(rupees * 100)))
                                            .font(.caption2)
                                            .foregroundStyle(Color.dmInkSoft)
                                    }
                                }
                            }
                        }
                        .frame(height: 220)
                        .accessibilityIdentifier("savedAndInvestedChart")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .withSettings(model: model)
        }
    }

    private func periodMenuRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.dmInk)
            Spacer()
            Text(value)
                .foregroundStyle(Color.dmFlow)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(Color.dmFlow)
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color.dmPaperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmHairline))
        .contentShape(Rectangle())
    }
}

private struct DestinationIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var destinationIsActive: Bool {
        get { self[DestinationIsActiveKey.self] }
        set { self[DestinationIsActiveKey.self] = newValue }
    }
}

struct SettingsAccess: ViewModifier {
    @ObservedObject var model: LedgerModel
    @Environment(\.destinationIsActive) private var destinationIsActive
    @State private var visible = false
    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                if destinationIsActive {
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
            }
            .fullScreenCover(isPresented: $visible) { SettingsView(model: model) }
            .onChange(of: destinationIsActive) { isActive in
                if !isActive { visible = false }
            }
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
    @State private var creditKind = "income"
    @State private var classificationIncome = false
    @State private var transactionDate = Date()
    @State private var error: String?
    @State private var dateError: String?
    @State private var delete = false
    private var isManualEdit: Bool { reviewId == nil && entry.source == "manual" }
    var body: some View {
        NavigationStack {
            ScreenSurface {
                RaisedPanel {
                    if reviewId != nil && entry.source != "manual" {
                        detailLine("Original amount", "Rs " + model.engine.formatAmount(paise: entry.paise))
                    } else {
                        FieldLabel(text: "Amount")
                        PaperField(placeholder: "Amount", text: $amount, keyboard: .decimalPad)
                            .accessibilityIdentifier("editEntryAmount")
                    }

                    FieldLabel(text: "Name")
                    PaperField(placeholder: "Name", text: $name)
                        .accessibilityIdentifier("editEntryName")

                    classificationPicker

                    if isManualEdit {
                        FieldLabel(text: "Date")
                        DatePicker("Date", selection: $transactionDate, in: ...Date(), displayedComponents: .date)
                            .foregroundStyle(Color.dmInk)
                            .environment(\.timeZone, Self.transactionTimeZone)
                            .accessibilityIdentifier("editEntryDate")
                        if let dateError {
                            Text(dateError)
                                .font(.caption)
                                .foregroundStyle(Color.dmSpend)
                                .accessibilityIdentifier("editEntryDateError")
                        }
                    }

                    if let error, dateError == nil {
                        Text(error).foregroundStyle(Color.dmSpend)
                            .accessibilityIdentifier("editEntryError")
                    }
                    if reviewId == nil {
                        Button("Delete transaction", role: .destructive) { delete = true }
                            .buttonStyle(DestructivePillButtonStyle())
                            .accessibilityIdentifier("deleteManualTransaction")
                    }
                }
            }
            .navigationTitle("Edit transaction")
            .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let saveError = model.mutate { engine in
                                let selectedCategory = classificationIncome ? creditLabel(creditKind) : category
                                if let reviewId {
                                    return engine.editReviewClassified(
                                        id: reviewId,
                                        name: name,
                                        amount: amount,
                                        category: selectedCategory,
                                        income: classificationIncome
                                    )
                                }
                                return engine.editEntryClassified(
                                    id: entry.id,
                                    name: name,
                                    amount: amount,
                                    category: selectedCategory,
                                    date: Self.transactionDateFormatter.string(from: transactionDate),
                                    income: classificationIncome,
                                    platform: "ios",
                                    nowMillis: Int64(Date().timeIntervalSince1970 * 1000)
                                )
                            }
                            error = saveError
                            dateError = saveError == "Transaction date cannot be in the future." ? saveError : nil
                            if saveError == nil { dismiss() }
                        }
                        .accessibilityIdentifier("saveManualTransaction")
                    }
                }
                .onAppear {
                    name = entry.name
                    amount = model.engine.formatAmount(paise: entry.paise)
                    category = entry.category
                    creditKind = entry.effectiveCreditKind()
                    classificationIncome = entry.type == "income"
                    let day = model.engine.transactionDay(date: entry.date)
                    transactionDate = Self.transactionDateFormatter.date(from: day) ?? Date()
                }
                .confirmationDialog("Delete transaction?", isPresented: $delete) {
                    Button("Delete", role: .destructive) {
                        error = model.mutate { $0.deleteEntry(id: entry.id, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) }
                        if error == nil { dismiss() }
                    }
                }
        }.presentationDetents([.medium, .large])
    }

    private var classificationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Debit")
            ChipFlowLayout {
                ForEach(model.engine.categories() + ["Own account transfer"], id: \.self) { option in
                    SelectableCategoryChip(
                        name: option,
                        selected: !classificationIncome && category == option,
                        accessibilityIdentifier: "editEntryCategoryOption-\(option)"
                    ) {
                        classificationIncome = false
                        category = option
                    }
                }
            }

            FieldLabel(text: "Credit")
                .padding(.top, 4)
            ChipFlowLayout {
                ForEach(["income", "own_transfer", "settlement"], id: \.self) { option in
                    SelectableCategoryChip(
                        name: creditLabel(option),
                        selected: classificationIncome && creditKind == option,
                        accessibilityIdentifier: "editEntryCreditKindOption-\(option)"
                    ) {
                        classificationIncome = true
                        creditKind = option
                    }
                }
            }
        }
    }

    private func creditLabel(_ kind: String) -> String {
        switch kind {
        case "own_transfer": return "Own account transfer"
        case "settlement": return "Settlement"
        default: return "Income"
        }
    }

    private static var transactionDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = transactionTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static var transactionTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Kolkata") ?? .current
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
