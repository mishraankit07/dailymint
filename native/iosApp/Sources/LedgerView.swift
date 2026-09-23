import SwiftUI
import DailyMintCore

private struct LedgerDateGroup: Identifiable {
    let date: String
    let entries: [Entry]
    let grossIn: Int64
    let grossOut: Int64
    var id: String { date }
}

struct LedgerView: View {
    @ObservedObject var model: LedgerModel
    @State private var query = ""
    @State private var typeFilter = "All"
    @State private var categoryFilter = "All"
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var detail: Entry?

    private var filterActive: Bool {
        !query.isEmpty || typeFilter != "All" || categoryFilter != "All" || useDateRange
    }

    private var groups: [LedgerDateGroup] {
        let start = Self.dateKey(startDate)
        let end = Self.dateKey(endDate)
        return model.engine.ledgerDays().compactMap { day in
            guard !useDateRange || (day.date >= start && day.date <= end) else { return nil }
            let entries = day.entries.filter { entry in
                (query.isEmpty || entry.name.localizedCaseInsensitiveContains(query)) &&
                (typeFilter == "All" || entry.type == typeFilter || (typeFilter == "neutral" && entry.neutralCredit > 0)) &&
                (categoryFilter == "All" || entry.category == categoryFilter ||
                    (categoryFilter == "Other income" && entry.category == "Received"))
            }
            return entries.isEmpty ? nil : LedgerDateGroup(date: day.date, entries: entries,
                                                            grossIn: day.moneyIn, grossOut: day.moneyOut)
        }
    }

    var body: some View {
        NavigationStack {
            ScreenSurface {
                LazyVStack(alignment: .leading, spacing: 14) {
                    BrandHeader(title: "Ledger")
                    if let loadError = model.engine.loadError {
                        RaisedPanel {
                            Text("Ledger unavailable")
                                .font(.headline).foregroundStyle(Color.dmSpend)
                            Text(loadError).font(.subheadline).foregroundStyle(Color.dmInkSoft)
                        }
                    } else {
                        RaisedPanel {
                            HStack {
                                Text("\(model.engine.entries().count) transactions")
                                    .font(.caption).foregroundStyle(Color.dmInkFaint)
                                Spacer()
                            }
                            PaperField(placeholder: "Search transactions", text: $query)
                                .accessibilityIdentifier("ledgerSearch")
                            filterControls
                        }

                        if groups.isEmpty {
                            RaisedPanel {
                                Text(model.engine.entries().isEmpty ? "No transactions yet" : "No matching transactions")
                                    .font(.headline).foregroundStyle(Color.dmInk)
                                Text(model.engine.entries().isEmpty
                                     ? "Add an entry or set up SMS automation in Settings."
                                     : "Try a different search or clear the filters.")
                                    .font(.subheadline).foregroundStyle(Color.dmInkSoft)
                                if !model.engine.entries().isEmpty {
                                    Button("Clear filters", action: clearFilters)
                                        .accessibilityIdentifier("clearLedgerFilters")
                                }
                            }
                        }

                        ForEach(groups) { group in
                            RaisedPanel {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(group.date).font(.headline).foregroundStyle(Color.dmInk)
                                        Spacer()
                                        Text("\(group.entries.count) entries")
                                            .font(.caption).foregroundStyle(Color.dmInkFaint)
                                    }
                                    Text((filterActive ? "Full day · " : "") +
                                         "Gross in Rs \(model.engine.formatAmount(paise: group.grossIn)) · out Rs \(model.engine.formatAmount(paise: group.grossOut))")
                                        .font(.caption).foregroundStyle(Color.dmInkSoft)
                                }
                                .padding(.vertical, 8)
                                ForEach(group.entries, id: \.id) { entry in
                                    Button { detail = entry } label: {
                                        TransactionLine(entry: entry, model: model)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("ledgerEntry-\(entry.id)")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .withSettings(model: model)
            .sheet(item: $detail) { TransactionDetailView(model: model, entry: $0) }
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(["All", "expense", "investment", "income", "neutral"], id: \.self) { value in
                        Button(typeLabel(value)) { typeFilter = value }
                    }
                } label: {
                    Label(typeLabel(typeFilter), systemImage: "line.3.horizontal.decrease")
                        .frame(minHeight: 44)
                }
                Menu {
                    Button("All categories") { categoryFilter = "All" }
                    ForEach(model.engine.categories() + ["Salary", "Other income", "Reimbursement", "Refund", "Own-account transfer"], id: \.self) { value in
                        Button(value) { categoryFilter = value }
                    }
                } label: {
                    Label(categoryFilter == "All" ? "Category" : categoryFilter, systemImage: "tag")
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(SecondaryPillButtonStyle())
            Toggle("Date range", isOn: $useDateRange)
                .tint(Color.dmFlow)
            if useDateRange {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
            }
        }
        .foregroundStyle(Color.dmInk)
    }

    private func clearFilters() {
        query = ""
        typeFilter = "All"
        categoryFilter = "All"
        useDateRange = false
    }

    private func typeLabel(_ value: String) -> String {
        switch value {
        case "expense": return "Expense"
        case "investment": return "Investment"
        case "income": return "Credit"
        case "neutral": return "Neutral credit"
        default: return "Type"
        }
    }

    private static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct TransactionDetailView: View {
    @ObservedObject var model: LedgerModel
    let entry: Entry
    @Environment(\.dismiss) private var dismiss
    @State private var share = ""
    @State private var name = ""
    @State private var category = ""
    @State private var creditKind = "other_income"
    @State private var error: String?
    @State private var showingManualEdit = false
    @State private var confirmingIgnore = false

    private var current: Entry {
        model.engine.entries().first(where: { $0.id == entry.id }) ?? entry
    }
    private var imported: Bool { current.source != "manual" }

    var body: some View {
        NavigationStack {
            ScreenSurface {
                    BrandHeader(title: current.name)
                    RaisedPanel {
                        detailLine("Original amount", "Rs " + model.engine.formatAmount(paise: current.paise))
                        if current.type == "expense" {
                            detailLine("Personal spending", "Rs " + model.engine.formatAmount(paise: current.personalSpent))
                        }
                        detailLine("Date", model.engine.transactionDay(date: current.date))
                        detailLine("Category", current.type == "income" ? creditLabel(current.effectiveCreditKind()) : current.category)
                        detailLine("Source", sourceLabel(current.source))
                        if current.ignored {
                            Label("Ignored in totals", systemImage: "eye.slash")
                                .foregroundStyle(Color.dmSpend)
                        }
                    }

                    if imported && current.type == "expense" {
                        RaisedPanel {
                            SectionHeading(title: "Count as my expense")
                            Text("Only this amount counts toward spending and category totals. The bank amount stays unchanged.")
                                .font(.caption).foregroundStyle(Color.dmInkSoft)
                            PaperField(placeholder: "Personal amount", text: $share, keyboard: .decimalPad)
                                .accessibilityIdentifier("personalShare")
                            HStack {
                                Button("Count full amount") {
                                    share = model.engine.formatAmount(paise: current.paise)
                                }
                                .buttonStyle(SecondaryPillButtonStyle())
                                Button("Save amount", action: saveShare)
                                    .buttonStyle(PrimaryPillButtonStyle())
                                    .accessibilityIdentifier("savePersonalShare")
                            }
                        }
                    }

                    if current.type == "income" {
                        RaisedPanel {
                            SectionHeading(title: "Credit kind")
                            Picker("Credit kind", selection: $creditKind) {
                                ForEach(["salary", "other_income", "reimbursement", "refund", "own_transfer"], id: \.self) { kind in
                                    Text(creditLabel(kind)).tag(kind)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.dmFlow)
                            Button("Save classification") {
                                error = model.mutate { $0.classifyCredit(id: current.id, kind: creditKind) }
                            }
                            .buttonStyle(PrimaryPillButtonStyle())
                            .accessibilityIdentifier("saveCreditKind")
                        }
                    }

                    if imported && current.type != "income" {
                        RaisedPanel {
                            SectionHeading(title: "Correct classification")
                            PaperField(placeholder: "Name", text: $name)
                            Menu {
                                ForEach(model.engine.categories(), id: \.self) { option in
                                    Button(option) { category = option }
                                }
                            } label: {
                                Label(category, systemImage: "tag")
                            }
                            .buttonStyle(SecondaryPillButtonStyle())
                            Button("Save correction") {
                                error = model.mutate { $0.correctImported(id: current.id, name: name, category: category) }
                            }
                            .buttonStyle(SecondaryPillButtonStyle())
                        }
                    }

                    if model.engine.canEdit(id: current.id, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) {
                        Button("Edit manual entry") { showingManualEdit = true }
                            .buttonStyle(SecondaryPillButtonStyle())
                    }
                    if imported {
                        if current.ignored {
                            Button("Restore transaction") {
                                confirmingIgnore = true
                            }
                            .buttonStyle(SecondaryPillButtonStyle())
                        } else {
                            Button("Ignore transaction") {
                                confirmingIgnore = true
                            }
                            .buttonStyle(DestructivePillButtonStyle())
                        }
                    }
                    if let error {
                        Text(error).foregroundStyle(Color.dmSpend)
                            .accessibilityIdentifier("transactionError")
                    }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                share = model.engine.formatAmount(paise: current.personalSpent)
                name = current.name
                category = current.category
                creditKind = current.effectiveCreditKind()
            }
            .sheet(isPresented: $showingManualEdit) { EntryEditSheet(model: model, entry: current, reviewId: nil) }
            .confirmationDialog(current.ignored ? "Restore this transaction?" : "Ignore this transaction in totals?", isPresented: $confirmingIgnore) {
                Button(current.ignored ? "Restore" : "Ignore", role: current.ignored ? nil : .destructive) {
                    error = model.mutate { $0.setIgnored(id: current.id, ignored: !current.ignored) }
                }
            }
        }
    }

    private func saveShare() {
        error = model.mutate { $0.setPersonalExpense(id: current.id, amount: share) }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Color.dmInkSoft)
            Spacer()
            Text(value).foregroundStyle(Color.dmInk).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func creditLabel(_ kind: String) -> String {
        switch kind {
        case "salary": return "Salary"
        case "reimbursement": return "Reimbursement"
        case "refund": return "Refund"
        case "own_transfer": return "Own-account transfer"
        default: return "Other income"
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "manual": return "Manual"
        case "bank-sms": return "Bank SMS via Shortcut"
        case "bank-file": return "Imported file"
        case "bank-wal": return "Legacy bank import"
        default: return "Imported"
        }
    }
}
