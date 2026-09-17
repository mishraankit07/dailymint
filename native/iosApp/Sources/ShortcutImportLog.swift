import Foundation

struct ShortcutImportReceipt: Identifiable {
    let id: String
    let timestamp: String
    let status: String
    let sender: String
    let preview: String

    var title: String {
        timestamp + " - " + status
    }
}

enum ShortcutImportLog {
    private static let fileName = "shortcut-import-log-v2.tsv"

    private static var url: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(fileName)
    }

    static func record(status: String, sender: String, message: String) {
        removeLegacyLog()
        let line = [
            isoTimestamp(),
            sanitize(status),
            "Hidden",
            String(message.count) + " characters"
        ].joined(separator: "\t") + "\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
            prune()
            protectForBackgroundAccess()
        } catch {
            // Best-effort debug log only; import flow must not fail because logging failed.
        }
    }

    static func recent(limit: Int = 8) -> [ShortcutImportReceipt] {
        removeLegacyLog()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n")
            .suffix(limit)
            .reversed()
            .enumerated()
            .compactMap { offset, line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 4 else { return nil }
                return ShortcutImportReceipt(
                    id: parts[0] + "-" + String(offset),
                    timestamp: parts[0],
                    status: parts[1],
                    sender: parts[2],
                    preview: parts[3]
                )
            }
    }

    private static func prune() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n").suffix(40).joined(separator: "\n")
        try? (lines + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func protectForBackgroundAccess() {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private static func removeLegacyLog() {
        let oldURL = url.deletingLastPathComponent().appendingPathComponent("shortcut-import-log.tsv")
        try? FileManager.default.removeItem(at: oldURL)
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
