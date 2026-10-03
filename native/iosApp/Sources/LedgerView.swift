import SwiftUI
import DailyMintCore

private struct LedgerDateGroup: Identifiable {
    let date: String
    let entries: [Entry]
    let moneyIn: Int64
    let spent: Int64
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
                                                            moneyIn: day.moneyIn, spent: day.spent)
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
                                         "Money in Rs \(model.engine.formatAmount(paise: group.moneyIn)) · spent Rs \(model.engine.formatAmount(paise: group.spent))")
                                        .font(.caption).foregroundStyle(Color.dmInkSoft)
                                        .accessibilityIdentifier("ledgerDaySummary-\(group.date)")
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
                        : ["All"] + model.engine.categories() + ["Own account transfer"],
                    selection: $categoryFilter,
                    isPresented: $showingCategoryFilter,
                    optionIdentifierPrefix: "ledgerCategoryFilterOption"
                )
            }
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StableMenu {
                    ForEach(["All", "expense", "income"], id: \.self) { value in
                        Button(typeLabel(value)) {
                            typeFilter = value
                            categoryFilter = "All"
                        }
                    }
                } label: {
                    Label(typeLabel(typeFilter), systemImage: "line.3.horizontal.decrease")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("ledgerTypeFilter")
                if typeFilter != "All" {
                    Button { showingCategoryFilter = true } label: {
                        Label(classificationFilterLabel, systemImage: "tag")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .frame(maxWidth: .infinity)
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
    @State private var amount = ""
    @State private var category = ""
    @State private var creditKind = "income"
    @State private var classificationIncome = false
    @State private var transactionDate = Date()
    @State private var splitEnabled = false
    @State private var splitMethod = "equal"
    @State private var people = "2"
    @State private var customShare = ""
    @State private var error: String?
    @State private var dateError: String?
    @State private var manualValidationAttempted = false
    @State private var confirmingDelete = false
    @State private var confirmingDiscard = false

    private var current: Entry {
        model.engine.entries().first(where: { $0.id == entry.id }) ?? entry
    }
    private var imported: Bool { current.source != "manual" }
    private var manualEditable: Bool {
        !imported && model.engine.canEdit(
            id: current.id,
            platform: "ios",
            nowMillis: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
    private var isExpense: Bool {
        !classificationIncome && category != "Investments" && category != "Own account transfer"
    }
    private var stagedMethod: String { splitEnabled && isExpense ? splitMethod : "none" }
    private var maximumPeople: Int { Int(model.engine.maximumSplitPeople(id: current.id)) }
    private var parsedPeople: Int? {
        guard people.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              let value = Int(people) else { return nil }
        return value
    }
    private var validPeople: Int? {
        guard let value = parsedPeople, value >= 2, value <= maximumPeople else { return nil }
        return value
    }
    private var participantError: String? {
        guard splitEnabled && isExpense && splitMethod == "equal" else { return nil }
        guard !people.isEmpty else { return nil }
        guard let value = parsedPeople, value >= 2 else { return "Enter at least 2 people, including you." }
        if value > maximumPeople { return "Each person's share must be at least Rs 1." }
        return nil
    }
    private var equalSharePaise: Int64 {
        guard let validPeople else { return -1 }
        return model.engine.equalShare(id: current.id, people: Int32(validPeople))
    }
    private var previewPaise: Int64? {
        guard splitEnabled && isExpense && splitMethod == "equal" else { return nil }
        return equalSharePaise >= 0 ? equalSharePaise : nil
    }
    private var customShareError: String? {
        guard splitEnabled && isExpense && splitMethod == "custom", !customShare.isEmpty else { return nil }
        guard let value = parseDisplayAmount(customShare) else {
            return "Enter an amount with up to two decimal places."
        }
        return value > current.paise ? "Your share cannot exceed the original amount." : nil
    }
    private var importedSaveDisabled: Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if splitEnabled && isExpense && splitMethod == "equal" { return validPeople == nil }
        if splitEnabled && isExpense && splitMethod == "custom" {
            guard let value = parseDisplayAmount(customShare) else { return true }
            return value > current.paise
        }
        return false
    }
    private var manualAmountIsValid: Bool {
        guard let value = parseDisplayAmount(amount) else { return false }
        return value > 0
    }
    private var manualNameIsValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 120
    }
    private var manualAmountError: String? {
        guard manualValidationAttempted else { return nil }
        let normalized = AmountInputFormatter.normalized(amount)
        guard normalized.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else {
            return "Enter a positive amount with up to two decimal places."
        }
        guard let value = parseDisplayAmount(amount) else { return "Amount is too large." }
        return value > 0 ? nil : "Enter a positive amount."
    }
    private var manualNameError: String? {
        manualValidationAttempted && !manualNameIsValid
            ? "Enter a name between 1 and 120 characters."
            : nil
    }
    private var hasUnsavedChanges: Bool {
        if !imported {
            guard manualEditable else { return false }
            return name != current.name ||
                amount != model.engine.formatAmount(paise: current.paise) ||
                classificationIncome != (current.type == "income") ||
                (classificationIncome ? creditKind != current.effectiveCreditKind() : category != current.category) ||
                Self.transactionDateFormatter.string(from: transactionDate) != model.engine.transactionDay(date: current.date)
        }
        let savedSplit = current.type == "expense" && current.category != "Own account transfer" &&
            (current.splitMethod != "none" || current.personalSpent != current.paise)
        let savedMethod = current.splitMethod == "none" && savedSplit ? "custom" : current.splitMethod
        let savedPeople = model.engine.splitPeopleCount(id: current.id)
        return name != current.name ||
            classificationIncome != (current.type == "income") ||
            (!classificationIncome && category != current.category) ||
            (classificationIncome && creditKind != current.effectiveCreditKind()) ||
            (!classificationIncome && current.type == "expense" && (splitEnabled != savedSplit ||
                (splitEnabled && splitMethod != savedMethod) ||
                (splitEnabled && splitMethod == "equal" && Int32(people) != savedPeople) ||
                (splitEnabled && splitMethod == "custom" && parseDisplayAmount(customShare) != current.personalSpent)))
    }

    var body: some View {
        NavigationStack {
            ScreenSurface {
                if manualEditable {
                    manualEditor
                } else if !imported {
                    RaisedPanel {
                        Text("Rs " + model.engine.formatAmount(paise: current.paise))
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundStyle(Color.dmInk)
                            .accessibilityLabel("Amount, Rs " + model.engine.formatAmount(paise: current.paise))
                        detailLine("Date", model.engine.transactionDay(date: current.date))
                    }
                }

                if imported {
                    importedEditor
                } else if !manualEditable {
                    RaisedPanel {
                        detailLine("Name", current.name)
                        detailLine("Category", current.type == "income" ? creditLabel(current.effectiveCreditKind()) : current.category)
                    }
                }

                if let error, dateError == nil {
                    Text(error).foregroundStyle(Color.dmSpend)
                        .accessibilityIdentifier("transactionError")
                }

                if imported || manualEditable {
                    Button("Save") {
                        if imported { saveImported() } else { saveManual() }
                    }
                    .buttonStyle(PrimaryPillButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(imported ? "saveImportedTransaction" : "saveManualTransaction")
                    .disabled(imported && importedSaveDisabled)
                }
            }
            .navigationTitle(imported || manualEditable ? "Edit transaction" : "Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(imported || manualEditable ? "Cancel" : "Done", action: requestDismiss)
                }
            }
            .onAppear {
                loadEditorState()
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Your changes have not been saved.")
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
        }
        .allowsHitTesting(!confirmingDelete)
        .overlay {
            if confirmingDelete {
                DeleteTransactionConfirmationDialog(
                    hasUnsavedChanges: hasUnsavedChanges,
                    confirmIdentifier: imported ? "confirmDeleteImportedTransaction" : "confirmDeleteManualTransaction",
                    onDelete: deleteTransaction,
                    onCancel: { confirmingDelete = false }
                )
            }
        }
        .animation(.easeOut(duration: 0.18), value: confirmingDelete)
    }

    private var manualEditor: some View {
        Group {
            RaisedPanel {
                FieldLabel(text: "Amount")
                PaperField(placeholder: "Amount", text: AmountInputFormatter.binding($amount), keyboard: .decimalPad)
                    .accessibilityIdentifier("editEntryAmount")
                fieldValidationLine(manualAmountError, identifier: "editEntryAmountError")

                FieldLabel(text: "Name")
                PaperField(placeholder: "Name", text: $name)
                    .accessibilityIdentifier("editEntryName")
                fieldValidationLine(manualNameError, identifier: "editEntryNameError")

                classificationPicker

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

            Button("Delete transaction") { confirmingDelete = true }
                .buttonStyle(DestructivePillButtonStyle())
                .accessibilityIdentifier("deleteManualTransaction")
        }
    }

    private var importedEditor: some View {
        Group {
            RaisedPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rs " + model.engine.formatAmount(paise: current.paise))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.dmInk)
                        Text("Original amount, can't be edited")
                            .font(.caption)
                            .foregroundStyle(Color.dmInkFaint)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color.dmInkFaint)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Original amount, Rs " + model.engine.formatAmount(paise: current.paise) + ", can't be edited")

                FieldLabel(text: "Name")
                PaperField(placeholder: "Merchant name", text: $name)
                    .accessibilityIdentifier("transactionName")

                classificationPicker

                FieldLabel(text: "Captured at")
                HStack {
                    Text(capturedAtText)
                        .foregroundStyle(Color.dmInk)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Color.dmInkFaint)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .background(Color.dmPaperRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmHairline))
            }

            RaisedPanel {
                Toggle("Record your share?", isOn: $splitEnabled)
                    .tint(Color.dmFlow)
                    .accessibilityIdentifier("splitTransaction")
                    .disabled(!isExpense)
                    .onChange(of: splitEnabled) { enabled in
                        if enabled {
                            if maximumPeople < 2 {
                                splitMethod = "custom"
                            } else if splitMethod == "none" {
                                splitMethod = "equal"
                                people = "2"
                            }
                        }
                    }
                if !isExpense {
                    Text("Available for debit spending categories.")
                        .font(.caption)
                        .foregroundStyle(Color.dmInkSoft)
                        .accessibilityIdentifier("splitUnavailableReason")
                }
                if splitEnabled {
                    Divider().overlay(Color.dmHairline)
                    HStack(spacing: 6) {
                        PaperSegment(title: "Split equally", value: "equal", selection: $splitMethod)
                            .disabled(maximumPeople < 2)
                            .accessibilityIdentifier("splitMethodEqual")
                        PaperSegment(title: "Enter your share", value: "custom", selection: $splitMethod)
                            .accessibilityIdentifier("splitMethodCustom")
                    }
                    .padding(4)
                    .background(Color.dmPaperRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if maximumPeople < 2 {
                        Text("Equal split requires an original amount of at least Rs 2.")
                            .font(.caption)
                            .foregroundStyle(Color.dmInkSoft)
                    }

                    if splitMethod == "equal" {
                        HStack {
                            Text("People, including you")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.dmInk)
                            Spacer()
                            HStack(spacing: 0) {
                                Button {
                                    if let value = validPeople, value > 2 { people = String(value - 1) }
                                } label: {
                                    Image(systemName: "minus")
                                        .frame(width: 44, height: 44)
                                }
                                .disabled(validPeople == nil || validPeople == 2)
                                .accessibilityIdentifier("splitPeopleDecrement")

                                TextField("2", text: $people)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 58, height: 44)
                                    .foregroundStyle(Color.dmInk)
                                    .accessibilityIdentifier("splitPeople")

                                Button {
                                    if let value = validPeople, value < maximumPeople { people = String(value + 1) }
                                } label: {
                                    Image(systemName: "plus")
                                        .frame(width: 44, height: 44)
                                }
                                .disabled(validPeople == nil || validPeople == maximumPeople)
                                .accessibilityIdentifier("splitPeopleIncrement")
                            }
                            .background(Color.dmPaperRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if let participantError {
                            Text(participantError)
                                .font(.caption)
                                .foregroundStyle(Color.dmSpend)
                                .accessibilityIdentifier("splitPeopleError")
                        }
                    } else {
                        FieldLabel(text: "Your share of Rs " + model.engine.formatAmount(paise: current.paise))
                        HStack(spacing: 8) {
                            Text("Rs")
                                .foregroundStyle(Color.dmInkSoft)
                            TextField("Amount", text: AmountInputFormatter.binding($customShare))
                                .keyboardType(.decimalPad)
                                .foregroundStyle(Color.dmInk)
                                .tint(Color.dmFlow)
                                .accessibilityIdentifier("customShare")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.dmPaperRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.dmHairline))
                        fieldValidationLine(customShareError, identifier: "customShareError")
                            .padding(.top, 2)
                            .padding(.bottom, 4)
                    }

                    if splitMethod == "equal", let previewPaise {
                        HStack {
                            Text("Your share")
                                .font(.subheadline)
                                .foregroundStyle(Color.dmInkSoft)
                            Spacer()
                            Text("Rs " + model.engine.formatAmount(paise: previewPaise))
                                .font(.headline)
                                .foregroundStyle(Color.dmInk)
                        }
                        .padding(14)
                        .background(Color.dmPaperRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Your share, Rs " + model.engine.formatAmount(paise: previewPaise))
                        .accessibilityIdentifier("splitPreview")
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
        amount = model.engine.formatAmount(paise: current.paise)
        category = current.category
        creditKind = current.effectiveCreditKind()
        classificationIncome = current.type == "income"
        let day = model.engine.transactionDay(date: current.date)
        transactionDate = Self.transactionDateFormatter.date(from: day) ?? Date()
        splitEnabled = current.type == "expense" && current.category != "Own account transfer" &&
            (current.splitMethod != "none" || current.personalSpent != current.paise)
        let savedCustomShare = current.splitMethod == "custom" ||
            (current.splitMethod == "none" && current.personalSpent != current.paise)
        splitMethod = savedCustomShare ? "custom" : "equal"
        let savedPeople = model.engine.splitPeopleCount(id: current.id)
        people = savedPeople >= 2 ? String(savedPeople) : "2"
        customShare = savedCustomShare ? model.engine.formatAmount(paise: current.personalSpent) : ""
    }

    private func requestDismiss() {
        if hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
    }

    private func saveImported() {
        error = model.mutate {
            $0.updateImportedTransactionClassified(
                id: current.id,
                name: name,
                category: classificationIncome ? creditLabel(creditKind) : category,
                personalAmount: AmountInputFormatter.normalized(customShare),
                splitMethod: stagedMethod,
                splitPeopleCount: Int32(people) ?? 0,
                creditKind: creditKind,
                income: classificationIncome
            )
        }
        if error == nil { dismiss() }
    }

    private func saveManual() {
        manualValidationAttempted = true
        guard manualAmountIsValid, manualNameIsValid else {
            error = nil
            dateError = nil
            return
        }
        let saveError = model.mutate {
            $0.editEntryClassified(
                id: current.id,
                name: name,
                amount: AmountInputFormatter.normalized(amount),
                category: classificationIncome ? creditLabel(creditKind) : category,
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

    private var classificationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Debit")
            ChipFlowLayout {
                ForEach(model.engine.categories() + ["Own account transfer"], id: \.self) { option in
                    SelectableCategoryChip(
                        name: option,
                        selected: !classificationIncome && category == option,
                        accessibilityIdentifier: (imported ? "transactionCategoryOption-" : "editEntryCategoryOption-") + option
                    ) {
                        classificationIncome = false
                        category = option
                        if option == "Investments" || option == "Own account transfer" {
                            splitEnabled = false
                        }
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
                        accessibilityIdentifier: (imported ? "transactionCreditKindOption-" : "editEntryCreditKindOption-") + option
                    ) {
                        classificationIncome = true
                        creditKind = option
                        splitEnabled = false
                    }
                }
            }
        }
    }

    private func deleteTransaction() {
        confirmingDelete = false
        error = model.mutate { $0.deleteEntry(id: current.id) }
        if error == nil {
            DispatchQueue.main.async { dismiss() }
        }
    }

    private func fieldValidationLine(_ message: String?, identifier: String) -> some View {
        Text(message ?? " ")
            .font(.caption)
            .foregroundStyle(message == nil ? Color.clear : Color.dmSpend)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
            .accessibilityHidden(message == nil)
            .accessibilityIdentifier(identifier)
    }

    private func parseDisplayAmount(_ value: String) -> Int64? {
        let normalized = AmountInputFormatter.normalized(value)
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

    private var capturedAtText: String {
        guard current.capturedAtMillis > 0 else { return "Unavailable" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy, h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: Double(current.capturedAtMillis) / 1000))
    }
}

private struct DeleteTransactionConfirmationDialog: View {
    let hasUnsavedChanges: Bool
    let confirmIdentifier: String
    let onDelete: () -> Void
    let onCancel: () -> Void

    private var message: String {
        if hasUnsavedChanges {
            return "This transaction will be removed from the Ledger and from all calculations. Your unsaved changes will not be applied."
        }
        return "This transaction will be removed from the Ledger and from all calculations."
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityIdentifier("deleteTransactionBackdrop")

            VStack(alignment: .leading, spacing: 16) {
                Text("Delete transaction?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.dmInk)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.dmInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("deleteTransactionMessage")
                HStack {
                    Spacer()
                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(DestructivePillButtonStyle())
                        .accessibilityIdentifier(confirmIdentifier)
                }
            }
            .padding(20)
            .frame(maxWidth: 320, alignment: .leading)
            .background(Color.dmPaperRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.dmHairline))
            .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
