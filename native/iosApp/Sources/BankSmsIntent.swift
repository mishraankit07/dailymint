import AppIntents
import Foundation
import DailyMintCore

struct ImportBankSmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Bank SMS"
    static var description = IntentDescription("Send a bank transaction message to DailyMint.")
    static var openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$message) from \(\.$sender)")
    }

    @Parameter(title: "Message", inputConnectionBehavior: .connectToPreviousIntentResult)
    var message: String

    @Parameter(title: "Sender")
    var sender: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = await ShortcutSMSProcessor.shared.importMessage(message, sender: sender)
        return .result(dialog: "\(response)")
    }
}

struct CaptureIncomingSmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Incoming SMS"
    static var description = IntentDescription("Receive the message text from a Shortcuts Message automation and check it for a transaction on this device.")
    static var openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$message) from \(\.$sender)")
    }

    @Parameter(title: "Message", inputConnectionBehavior: .connectToPreviousIntentResult)
    var message: String?

    @Parameter(title: "Sender")
    var sender: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = await ShortcutSMSProcessor.shared.importMessage(message, sender: sender)
        return .result(dialog: "\(response)")
    }
}

actor ShortcutSMSProcessor {
    static let shared = ShortcutSMSProcessor()

    func importMessage(_ message: String?, sender: String?) -> String {
        let text = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            ShortcutImportLog.record(status: "empty input", sender: sender ?? "Shortcut", message: "")
            return "DailyMint did not receive a message. Check the Message field in Shortcuts."
        }

        let messageSender = sender?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSender = (messageSender?.isEmpty == false) ? messageSender! : "Shortcut"
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let sourceId = "shortcut-\(stableHash(normalizedSender + "|" + text))"
        let store = FileStore()
        do {
            return try store.withExclusiveLock {
                importLocked(text: text, sender: normalizedSender, timestamp: timestamp, sourceId: sourceId, store: store)
            }
        } catch {
            ShortcutImportLog.record(status: "save failed", sender: normalizedSender, message: text)
            return "DailyMint could not access its local data. Try again."
        }
    }

    private func importLocked(text: String, sender: String, timestamp: Int64, sourceId: String, store: FileStore) -> String {
        let engine = LedgerEngine(store: store)
        if let loadError = engine.loadError {
            ShortcutImportLog.record(status: "load failed", sender: sender, message: text)
            return "DailyMint could not open its ledger: \(loadError)"
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
                ShortcutImportLog.record(status: "transaction added", sender: sender, message: text)
                return "DailyMint added this transaction."
            }
            if engine.unrecognizedMessages().count > unrecognizedCount {
                ShortcutImportLog.record(status: "unrecognized", sender: sender, message: text)
                return "DailyMint received this SMS, but could not recognize it yet."
            }
            ShortcutImportLog.record(status: "no new transaction", sender: sender, message: text)
            return "DailyMint received this SMS. It was ignored or already recorded."
        }
        ShortcutImportLog.record(status: "save failed", sender: sender, message: text)
        return "DailyMint could not save this message."
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
                "Capture SMS in \(.applicationName)",
                "Check incoming SMS with \(.applicationName)"
            ],
            shortTitle: "Capture SMS",
            systemImageName: "message.badge"
        )
        AppShortcut(
            intent: ImportBankSmsIntent(),
            phrases: [
                "Import bank SMS in \(.applicationName)",
                "Add bank SMS to \(.applicationName)"
            ],
            shortTitle: "Import SMS",
            systemImageName: "banknote"
        )
    }
}
