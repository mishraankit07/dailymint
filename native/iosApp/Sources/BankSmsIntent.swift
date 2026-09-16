import AppIntents
import Foundation
import DailyMintCore

struct ImportBankSmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Bank SMS"
    static var description = IntentDescription("Send a bank transaction message to DailyMint.")
    static var openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$message)")
    }

    @Parameter(title: "Message")
    var message: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: "DailyMint did not receive a message.")
        }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let sourceId = "shortcut-\(timestamp)-\(stableHash(text))"
        let engine = LedgerEngine(store: FileStore())
        let result = engine.importSingleMessage(
            id: sourceId,
            body: text,
            sender: "Shortcut",
            timestamp: timestamp
        )

        if result.success {
            return .result(dialog: "DailyMint processed the bank message.")
        }
        return .result(dialog: "DailyMint could not save this message.")
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
    static var appShortcuts: [AppShortcut] {
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
