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
    @State private var visibleDayCount = 30

    private var filterActive: Bool {
        !query.isEmpty || typeFilter != "All" || categoryFilter != "All" || useDateRange
    }

    private var allGroups: [LedgerDateGroup] {
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

    private var groups: [LedgerDateGroup] { Array(allGroups.prefix(visibleDayCount)) }

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
                                .onChange(of: query) { _ in visibleDayCount = 30 }
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
                        if groups.count < allGroups.count {
                            Button("Load more transactions") { visibleDayCount += 30 }
                                .buttonStyle(SecondaryPillButtonStyle())
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("loadMoreLedger")
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
                        Button(typeLabel(value)) { typeFilter = value; visibleDayCount = 30 }
                    }
                } label: {
                    Label(typeLabel(typeFilter), systemImage: "line.3.horizontal.decrease")
                        .frame(minHeight: 44)
                }
                Menu {
                    Button("All categories") { categoryFilter = "All"; visibleDayCount = 30 }
                    ForEach(model.engine.categories() + ["Salary", "Other income", "Reimbursement", "Refund", "Own-account transfer"], id: \.self) { value in
                        Button(value) { categoryFilter = value; visibleDayCount = 30 }
                    }
                } label: {
                    Label(categoryFilter == "All" ? "Category" : categoryFilter, systemImage: "tag")
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(SecondaryPillButtonStyle())
            Toggle("Date range", isOn: $useDateRange)
                .tint(Color.dmFlow)
                .onChange(of: useDateRange) { _ in visibleDayCount = 30 }
            if useDateRange {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .onChange(of: startDate) { _ in visibleDayCount = 30 }
                DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .onChange(of: endDate) { _ in visibleDayCount = 30 }
            }
        }
        .foregroundStyle(Color.dmInk)
    }

    private func clearFilters() {
        query = ""
        typeFilter = "All"
        categoryFilter = "All"
        useDateRange = false
        visibleDayCount = 30
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
    @State private var name = ""
    @State private var category = ""
    @State private var creditKind = "other_income"
    @State private var splitEnabled = false
    @State private var splitMethod = "equal"
    @State private var people = "2"
    @State private var customShare = ""
    @State private var error: String?
    @State private var showingManualEdit = false
    @State private var confirmingIgnore = false
    @State private var confirmingDiscard = false

    private var current: Entry {
        model.engine.entries().first(where: { $0.id == entry.id }) ?? entry
    }
    private var imported: Bool { current.source != "manual" }
    private var isExpense: Bool { category != "Investments" && current.type != "income" }
    private var stagedMethod: String { splitEnabled && isExpense ? splitMethod : "none" }
    private var equalSharePaise: Int64 {
        model.engine.equalShare(id: current.id, people: Int32(people) ?? 0)
    }
    private var previewPaise: Int64? {
        guard splitEnabled && isExpense else { return current.paise }
        if splitMethod == "equal" { return equalSharePaise >= 0 ? equalSharePaise : nil }
        return parseDisplayAmount(customShare)
    }
    private var hasUnsavedChanges: Bool {
        guard imported else { return false }
        let savedSplit = current.splitMethod != "none" || current.personalSpent != current.paise
        let savedMethod = current.splitMethod == "none" && savedSplit ? "custom" : current.splitMethod
        let savedPeople = model.engine.splitPeopleCount(id: current.id)
        return name != current.name || category != current.category ||
            (current.type == "income" && creditKind != current.effectiveCreditKind()) ||
            (current.type == "expense" && (splitEnabled != savedSplit ||
                (splitEnabled && splitMethod != savedMethod) ||
                (splitEnabled && splitMethod == "equal" && Int32(people) != savedPeople) ||
                (splitEnabled && splitMethod == "custom" && parseDisplayAmount(customShare) != current.personalSpent)))
    }

    var body: some View {
        NavigationStack {
            ScreenSurface {
                RaisedPanel {
                    Text("Rs " + model.engine.formatAmount(paise: current.paise))
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.dmInk)
                        .accessibilityLabel("Original amount, Rs " + model.engine.formatAmount(paise: current.paise))
                    Text("Original amount")
                        .font(.caption).foregroundStyle(Color.dmInkFaint)
                    detailLine("Date", model.engine.transactionDay(date: current.date))
                    detailLine("Source", sourceLabel(current.source))
                    if current.ignored {
                        Label("Ignored in totals", systemImage: "eye.slash")
                            .foregroundStyle(Color.dmSpend)
                    }
                }

                if imported {
                    importedEditor
                } else {
                    RaisedPanel {
                        detailLine("Name", current.name)
                        detailLine("Category", current.type == "income" ? creditLabel(current.effectiveCreditKind()) : current.category)
                        if current.type == "expense" {
                            detailLine("Personal spending", "Rs " + model.engine.formatAmount(paise: current.personalSpent))
                        }
                    }
                    if model.engine.canEdit(id: current.id, platform: "ios", nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) {
                        Button("Edit manual entry") { showingManualEdit = true }
                            .buttonStyle(SecondaryPillButtonStyle())
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
                ToolbarItem(placement: .cancellationAction) {
                    Button(imported ? "Cancel" : "Done", action: requestDismiss)
                }
                if imported {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: saveImported)
                            .accessibilityIdentifier("saveImportedTransaction")
                    }
                }
            }
            .onAppear {
                loadEditorState()
            }
            .sheet(isPresented: $showingManualEdit) { EntryEditSheet(model: model, entry: current, reviewId: nil) }
            .confirmationDialog(current.ignored ? "Restore this transaction?" : "Ignore this transaction?", isPresented: $confirmingIgnore) {
                Button(current.ignored ? "Restore" : "Ignore", role: current.ignored ? nil : .destructive) {
                    error = model.mutate { $0.setIgnored(id: current.id, ignored: !current.ignored) }
                    if error == nil { dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(current.ignored
                     ? "This transaction will return to analytics."
                     : (hasUnsavedChanges
                        ? "This transaction will be excluded from analytics and retained in local diagnostic history. Your unsaved edits will not be applied."
                        : "This transaction will be excluded from analytics and retained in local diagnostic history."))
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Your changes have not been saved.")
            }
            .interactiveDismissDisabled(imported && hasUnsavedChanges)
        }
    }

    private var importedEditor: some View {
        Group {
            RaisedPanel {
                FieldLabel(text: "Merchant")
                PaperField(placeholder: "Merchant name", text: $name)
                    .accessibilityIdentifier("transactionName")

                if current.type == "income" {
                    FieldLabel(text: "Credit kind")
                    Picker("Credit kind", selection: $creditKind) {
                        ForEach(["salary", "other_income", "reimbursement", "refund", "own_transfer"], id: \.self) { kind in
                            Text(creditLabel(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.dmFlow)
                } else {
                    FieldLabel(text: "Category")
                    Menu {
                        ForEach(model.engine.categories(), id: \.self) { option in
                            Button(option) {
                                category = option
                                if option == "Investments" { splitEnabled = false }
                            }
                        }
                    } label: {
                        Label(category, systemImage: "tag")
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                }
            }

            if current.type != "income" && category != "Investments" {
                RaisedPanel {
                    Toggle("Split this bill with others", isOn: $splitEnabled)
                        .tint(Color.dmFlow)
                        .accessibilityIdentifier("splitTransaction")
                    if splitEnabled {
                        HStack(spacing: 6) {
                            PaperSegment(title: "Split equally", value: "equal", selection: $splitMethod)
                            PaperSegment(title: "Custom share", value: "custom", selection: $splitMethod)
                        }
                        .padding(4)
                        .background(Color.dmHairline.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if splitMethod == "equal" {
                            FieldLabel(text: "Among people, including you")
                            PaperField(placeholder: "Number of people", text: $people, keyboard: .numberPad)
                                .accessibilityIdentifier("splitPeople")
                        } else {
                            FieldLabel(text: "Your share")
                            PaperField(placeholder: "Amount", text: $customShare, keyboard: .decimalPad)
                                .accessibilityIdentifier("customShare")
                        }

                        if let previewPaise {
                            Text("Rs \(model.engine.formatAmount(paise: current.paise)) paid - Rs \(model.engine.formatAmount(paise: previewPaise)) counts as your spending")
                                .font(.caption).foregroundStyle(Color.dmInkSoft)
                                .accessibilityIdentifier("splitPreview")
                        } else {
                            Text(splitMethod == "equal" ? "Enter at least 2 people, including you." : "Enter an amount from Rs 0 to the original amount.")
                                .font(.caption).foregroundStyle(Color.dmSpend)
                        }
                    }
                }
            }

            if current.ignored {
                Button("Restore transaction") { confirmingIgnore = true }
                    .buttonStyle(SecondaryPillButtonStyle())
            } else {
                Button("Ignore this transaction") { confirmingIgnore = true }
                    .buttonStyle(DestructivePillButtonStyle())
            }
        }
    }

    private func loadEditorState() {
        name = current.name
        category = current.category
        creditKind = current.effectiveCreditKind()
        splitEnabled = current.splitMethod != "none" || current.personalSpent != current.paise
        splitMethod = current.splitMethod == "equal" ? "equal" : "custom"
        let savedPeople = model.engine.splitPeopleCount(id: current.id)
        people = savedPeople >= 2 ? String(savedPeople) : "2"
        customShare = model.engine.formatAmount(paise: current.personalSpent)
    }

    private func requestDismiss() {
        if imported && hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
    }

    private func saveImported() {
        error = model.mutate {
            $0.updateImportedTransaction(
                id: current.id,
                name: name,
                category: category,
                personalAmount: customShare,
                splitMethod: stagedMethod,
                splitPeopleCount: Int32(people) ?? 0,
                creditKind: creditKind
            )
        }
        if error == nil { dismiss() }
    }

    private func parseDisplayAmount(_ value: String) -> Int64? {
        let normalized = value.replacingOccurrences(of: ",", with: "")
        guard normalized.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int64(parts[0]) else { return nil }
        let rawFraction = parts.count == 2 ? String(parts[1]) : ""
        let fraction = rawFraction.isEmpty ? "00" : (rawFraction.count == 1 ? rawFraction + "0" : rawFraction)
        guard let paise = Int64(fraction) else { return nil }
        let (base, multiplyOverflow) = whole.multipliedReportingOverflow(by: 100)
        let (total, addOverflow) = base.addingReportingOverflow(paise)
        return multiplyOverflow || addOverflow ? nil : total
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
