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
    @State private var detail: Entry?
    @State private var showingCategoryFilter = false

    private var filterActive: Bool {
        !query.isEmpty || typeFilter != "All" || categoryFilter != "All"
    }

    private var allGroups: [LedgerDateGroup] {
        return model.engine.ledgerDays().compactMap { day in
            let entries = day.entries.filter { entry in
                (query.isEmpty || entry.name.localizedCaseInsensitiveContains(query)) &&
                matchesType(entry) && matchesClassification(entry)
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
                                Text("\(model.engine.ledgerDays().reduce(0) { $0 + $1.entries.count }) transactions this cycle")
                                    .font(.caption).foregroundStyle(Color.dmInkFaint)
                                Spacer()
                            }
                            PaperField(placeholder: "Search transactions", text: $query)
                                .accessibilityIdentifier("ledgerSearch")
                            filterControls
                        }

                        if allGroups.isEmpty {
                            RaisedPanel {
                                Text(filterActive ? "No matching transactions" : "No transactions this cycle")
                                    .font(.headline).foregroundStyle(Color.dmInk)
                                Text(!filterActive
                                     ? "Add an entry or use automatic transaction capture."
                                     : "Try a different search or clear the filters.")
                                    .font(.subheadline).foregroundStyle(Color.dmInkSoft)
                                if filterActive {
                                    Button("Clear filters", action: clearFilters)
                                        .accessibilityIdentifier("clearLedgerFilters")
                                }
                            }
                        }

                        ForEach(allGroups) { group in
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
            .sheet(isPresented: $showingCategoryFilter) {
                CategorySelectionSheet(
                    title: typeFilter == "income" ? "Filter credits" : "Filter expenses",
                    options: typeFilter == "income"
                        ? ["All", "Income", "Own account transfer", "Settlement"]
                        : ["All"] + model.engine.categories(),
                    selection: $categoryFilter,
                    optionIdentifierPrefix: "ledgerCategoryFilterOption"
                )
            }
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(["All", "expense", "income"], id: \.self) { value in
                        Button(typeLabel(value)) {
                            typeFilter = value
                            categoryFilter = "All"
                        }
                    }
                } label: {
                    Label(typeLabel(typeFilter), systemImage: "line.3.horizontal.decrease")
                        .frame(minHeight: 44)
                }
                if typeFilter != "All" {
                    Button { showingCategoryFilter = true } label: {
                        Label(classificationFilterLabel, systemImage: "tag")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("ledgerCategoryFilter")
                }
            }
            .buttonStyle(SecondaryPillButtonStyle())
        }
        .foregroundStyle(Color.dmInk)
    }

    private func clearFilters() {
        query = ""
        typeFilter = "All"
        categoryFilter = "All"
    }

    private func typeLabel(_ value: String) -> String {
        switch value {
        case "expense": return "Expense"
        case "income": return "Credit"
        default: return "Type"
        }
    }

    private var classificationFilterLabel: String {
        if categoryFilter != "All" { return categoryFilter }
        return typeFilter == "income" ? "All credits" : "All categories"
    }

    private func matchesType(_ entry: Entry) -> Bool {
        switch typeFilter {
        case "expense": return entry.type != "income"
        case "income": return entry.type == "income"
        default: return true
        }
    }

    private func matchesClassification(_ entry: Entry) -> Bool {
        guard categoryFilter != "All" else { return true }
        if entry.type == "income" {
            return ledgerCreditLabel(entry.effectiveCreditKind()) == categoryFilter
        }
        return entry.category == categoryFilter
    }

    private func ledgerCreditLabel(_ kind: String) -> String {
        switch kind {
        case "own_transfer": return "Own account transfer"
        case "settlement": return "Settlement"
        default: return "Income"
        }
    }

}

struct TransactionDetailView: View {
    @ObservedObject var model: LedgerModel
    let entry: Entry
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    @State private var creditKind = "income"
    @State private var splitEnabled = false
    @State private var splitMethod = "equal"
    @State private var people = "2"
    @State private var customShare = ""
    @State private var error: String?
    @State private var showingManualEdit = false
    @State private var showingCategoryPicker = false
    @State private var showingCreditKindPicker = false
    @State private var confirmingDelete = false
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
                }

                if imported {
                    importedEditor
                } else {
                    RaisedPanel {
                        detailLine("Name", current.name)
                        detailLine("Category", current.type == "income" ? creditLabel(current.effectiveCreditKind()) : current.category)
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
            .sheet(isPresented: $showingCategoryPicker) {
                CategorySelectionSheet(
                    title: "Choose category",
                    options: model.engine.categories(),
                    selection: $category,
                    optionIdentifierPrefix: "transactionCategoryOption",
                    onSelection: { option in
                        if option == "Investments" { splitEnabled = false }
                    }
                )
            }
            .sheet(isPresented: $showingCreditKindPicker) {
                CategorySelectionSheet(
                    title: "Choose credit kind",
                    options: ["income", "own_transfer", "settlement"],
                    selection: $creditKind,
                    optionIdentifierPrefix: "transactionCreditKindOption",
                    optionLabel: creditLabel
                )
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete) {
                Button("Delete transaction", role: .destructive) {
                    error = model.mutate { $0.deleteEntry(id: current.id) }
                    if error == nil { dismiss() }
                }
                .accessibilityIdentifier("confirmDeleteImportedTransaction")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("cancelDeleteImportedTransaction")
            } message: {
                Text(hasUnsavedChanges
                     ? "This transaction will be removed from the Ledger and from all calculations. Your unsaved changes will not be applied."
                     : "This transaction will be removed from the Ledger and from all calculations.")
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
                detailLine("Captured at", capturedAtText)
                FieldLabel(text: "Merchant")
                PaperField(placeholder: "Merchant name", text: $name)
                    .accessibilityIdentifier("transactionName")

                if current.type == "income" {
                    FieldLabel(text: "Credit kind")
                    Button { showingCreditKindPicker = true } label: {
                        HStack {
                            Label(creditLabel(creditKind), systemImage: "tag")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                    .accessibilityIdentifier("transactionCreditKind")
                } else {
                    FieldLabel(text: "Category")
                    Button { showingCategoryPicker = true } label: {
                        HStack {
                            Label(category, systemImage: "tag")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(SecondaryPillButtonStyle())
                    .accessibilityIdentifier("transactionCategory")
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

            Button("Delete transaction") { confirmingDelete = true }
                .buttonStyle(DestructivePillButtonStyle())
                .accessibilityIdentifier("deleteImportedTransaction")
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
        case "own_transfer": return "Own account transfer"
        case "settlement": return "Settlement"
        default: return "Income"
        }
    }

    private var capturedAtText: String {
        guard current.capturedAtMillis > 0 else { return "Unavailable" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy, h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: Double(current.capturedAtMillis) / 1000))
    }
}
