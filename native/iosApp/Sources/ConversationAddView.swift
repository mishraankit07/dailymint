import SwiftUI
import FendYourSpendCore

struct ConversationAddView: View {
    @ObservedObject var model: LedgerModel
    let openManualEntry: () -> Void
    @Environment(\.destinationIsActive) private var isActive
    @FocusState private var composing: Bool
    @State private var message = ""
    @State private var pending: [String: JournalMessage] = [:]
    @State private var retryable: Set<String> = []
    @State private var visibleCount = 50

    private var messages: [JournalMessage] {
        let saved = model.engine.journalMessages()
        let ids = Set(saved.map(\.entryId))
        return (saved + pending.values.filter { !ids.contains($0.entryId) })
            .sorted { timestamp($0) == timestamp($1) ? $0.entryId < $1.entryId : timestamp($0) < timestamp($1) }
    }

    private func timestamp(_ item: JournalMessage) -> Int64 {
        item.originalEntry?.capturedAtMillis ?? item.createdAtMillis
    }

    private func submit(id: String, text: String) {
        var outcome: ConversationSubmitResult?
        let failure = model.mutate { engine in
            let result = engine.submitConversationEntry(id: id, message: text)
            outcome = result
            return SaveResult(success: result.recorded, message: result.error)
        }
        if outcome?.recorded == true {
            pending.removeValue(forKey: id)
            retryable.remove(id)
        } else {
            pending[id] = JournalMessage(entryId: id, text: text, originalEntry: nil,
                error: failure ?? "Could not save. Please try again.",
                createdAtMillis: pending[id]?.createdAtMillis ?? Int64(Date().timeIntervalSince1970 * 1000))
            if outcome?.retryable ?? true { retryable.insert(id) } else { retryable.remove(id) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    BrandHeader(title: "Add transaction")
                    Button {
                        composing = false
                        openManualEntry()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Manual entry")
                    .accessibilityIdentifier("openManualEntry")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            if messages.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    Image(systemName: "text.bubble")
                                        .font(.system(size: 36))
                                        .foregroundStyle(Color.dmFlow)
                                        .accessibilityHidden(true)
                                    Text("What did you spend today?")
                                        .font(.title3.weight(.semibold))
                                    example("Paid 150 at Starbucks")
                                    example("Received 5000 from Rahul")
                                }
                                .padding(.vertical, 48)
                            } else {
                                if messages.count > visibleCount {
                                    Button("Earlier messages") { visibleCount += 50 }
                                        .frame(maxWidth: .infinity)
                                }
                                let visible = Array(messages.suffix(visibleCount))
                                let entries = Dictionary(uniqueKeysWithValues: model.engine.entries().map { ($0.id, $0) })
                                ForEach(Array(visible.enumerated()), id: \.element.entryId) { index, item in
                                    if index == 0 || day(item) != day(visible[index - 1]) {
                                        Text(day(item), style: .date)
                                            .font(.caption)
                                            .foregroundStyle(Color.dmInkSoft)
                                            .frame(maxWidth: .infinity)
                                    }
                                    JournalReceipt(message: item, entry: entries[item.entryId], model: model,
                                        stored: !pending.keys.contains(item.entryId),
                                        canRetry: retryable.contains(item.entryId) && pending[item.entryId] != nil) {
                                            submit(id: item.entryId, text: item.text)
                                        }
                                        .id(item.entryId)
                                }
                            }
                            Color.clear.frame(height: 1).id("journalBottom")
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { composing = false }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear { reader.scrollTo("journalBottom", anchor: .bottom) }
                    // Only new journal records scroll; Ledger edits and periodic reloads do not.
                    .onChange(of: messages.count) { _ in
                        reader.scrollTo("journalBottom", anchor: .bottom)
                    }
                }
                composer
            }
            .foregroundStyle(Color.dmInk)
            .background(Color.dmPaper.ignoresSafeArea())
            .navigationBarHidden(true)
            .onChange(of: isActive) { active in
                if !active { composing = false }
            }
        }
    }

    private func day(_ item: JournalMessage) -> Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(timestamp(item)) / 1000))
    }

    private func example(_ text: String) -> some View {
        Button {
            message = text
            composing = true
        } label: {
            HStack {
                Text(text).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.left")
            }
            .padding(12)
            .background(Color.dmHairline.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = model.engine.loadError {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Color.dmSpend)
                    .accessibilityIdentifier("conversationError")
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Paid 200 at...", text: $message, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Color.dmHairline.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused($composing)
                    .accessibilityLabel("Transaction message")
                    .accessibilityIdentifier("conversationInput")
                Button {
                    submit(id: UUID().uuidString, text: message)
                    message = ""
                    composing = true
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.dmActionText)
                        .background(Color.dmActionFill)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Add transaction")
                .accessibilityIdentifier("sendTransaction")
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct JournalReceipt: View {
    let message: JournalMessage
    let entry: Entry?
    let model: LedgerModel
    let stored: Bool
    let canRetry: Bool
    let retry: () -> Void
    private var updated: Bool {
        guard let entry else { return false }
        guard let original = message.originalEntry else { return false }
        return entry.name != original.name || entry.paise != original.paise || entry.category != original.category || entry.date != original.date || entry.type != original.type
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text(message.text.isEmpty ? "Added manually" : message.text)
                .padding(12)
                .foregroundStyle(Color.dmInk)
                .background(Color.dmHairline.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 28)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: !message.error.isEmpty ? "xmark.circle" : entry == nil ? "trash" : "checkmark.circle")
                    .foregroundStyle(message.error.isEmpty ? Color.dmFlow : Color.dmSpend)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if !message.error.isEmpty {
                        Text("Not saved").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.dmSpend)
                        Text(message.error).font(.caption).foregroundStyle(Color.dmInkSoft)
                        if !stored {
                            Text("This message has not been stored on your device.")
                                .font(.caption).foregroundStyle(Color.dmInkSoft)
                        }
                        if canRetry {
                            Button("Retry", action: retry)
                                .accessibilityIdentifier("retrySubmission-" + message.entryId)
                        }
                    } else if let entry {
                        Text("Rs " + model.engine.formatAmount(paise: entry.paise) + (entry.type == "income" ? " received" : " spent"))
                            .font(.subheadline.weight(.semibold))
                        Text(entry.name + " · " + entry.category + " · " + entry.date)
                            .font(.caption)
                            .foregroundStyle(Color.dmInkSoft)
                        if updated {
                            Text("Updated in Ledger").font(.caption).foregroundStyle(Color.dmInkSoft)
                        }
                    } else {
                        Text("Deleted from Ledger").font(.subheadline)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 28)
            .accessibilityElement(children: canRetry ? .contain : .combine)
            .accessibilityIdentifier("journalReceipt-" + message.entryId)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
