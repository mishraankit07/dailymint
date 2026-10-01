import AppIntents
import Foundation
import DailyMintCore

struct CaptureIncomingSmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Bank SMS"
    static var description = IntentDescription("Send a bank transaction message to DailyMint.")
    static var openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$message)")
    }

    @Parameter(title: "Message", inputConnectionBehavior: .connectToPreviousIntentResult)
    var message: String?

    @Parameter(title: "Sender (optional)")
    var sender: String?

    func perform() async throws -> some IntentResult {
        _ = await ShortcutSMSProcessor.shared.importMessage(message, sender: sender)
        return .result()
    }
}

actor ShortcutSMSProcessor {
    static let shared = ShortcutSMSProcessor()

    private struct ImportOutcome {
        let response: String
        let status: String
        let addedTransaction: Bool
    }

    func importMessage(_ message: String?, sender: String?) async -> String {
        let suppliedMessage = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let suppliedSender = (sender ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveredFromSender = suppliedMessage.isEmpty && !suppliedSender.isEmpty
        let text = recoveredFromSender ? suppliedSender : suppliedMessage
        guard !text.isEmpty else {
            ShortcutImportLog.record(status: "empty input", sender: "Shortcut", message: "")
            return "DailyMint did not receive a message. Check the Message field in Shortcuts."
        }

        let normalizedSender = recoveredFromSender || suppliedSender.isEmpty ? "Shortcut" : suppliedSender
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let sourceId = "shortcut-\(stableHash(normalizedSender + "|" + text))"
        let store = FileStore(testing: ProcessInfo.processInfo.arguments.contains("--ui-testing"))
        do {
            let outcome = try store.withExclusiveLock {
                importLocked(text: text, sender: normalizedSender, timestamp: timestamp, sourceId: sourceId, store: store)
            }
            let status = recoveredFromSender ? outcome.status + " (recovered sender input)" : outcome.status
            ShortcutImportLog.record(status: status, sender: normalizedSender, message: text)
            if outcome.addedTransaction {
                await AutomaticImportNotification.sendTransactionAdded()
            }
            return outcome.response
        } catch {
            ShortcutImportLog.record(status: "ledger access failed", sender: normalizedSender, message: text)
            return "DailyMint could not access its local data. Try again."
        }
    }

    private func importLocked(text: String, sender: String, timestamp: Int64, sourceId: String, store: FileStore) -> ImportOutcome {
        let engine = LedgerEngine(store: store)
        if let loadError = engine.loadError {
            return ImportOutcome(
                response: "DailyMint could not open its ledger: \(loadError)",
                status: "ledger load failed",
                addedTransaction: false
            )
        }
        let entryCount = engine.entries().count
        let unrecognizedCount = engine.unrecognizedMessages().count
        let result = engine.importSingleMessage(
            id: sourceId,
            body: text,
            sender: sender,
            timestamp: timestamp
        )

        if result.success {
            if engine.entries().count > entryCount {
                return ImportOutcome(response: "DailyMint added this transaction.", status: "transaction added", addedTransaction: true)
            }
            if engine.unrecognizedMessages().count > unrecognizedCount {
                return ImportOutcome(
                    response: "DailyMint received this SMS, but could not recognize it yet.",
                    status: "unrecognized",
                    addedTransaction: false
                )
            }
            return ImportOutcome(
                response: "DailyMint received this SMS. It was ignored or already recorded.",
                status: "ignored or already recorded",
                addedTransaction: false
            )
        }
        return ImportOutcome(response: "DailyMint could not save this message.", status: "save failed", addedTransaction: false)
    }

    private func stableHash(_ text: String) -> String {
        var value: UInt32 = 2_166_136_261
        for scalar in text.unicodeScalars {
            value = (value ^ UInt32(scalar.value)) &* 16_777_619
        }
        return String(value, radix: 16)
    }
}

struct DailyMintShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIncomingSmsIntent(),
            phrases: [
                "Import bank SMS in \(.applicationName)",
                "Add bank SMS to \(.applicationName)"
            ],
            shortTitle: "Import SMS",
            systemImageName: "banknote"
        )
    }
}
