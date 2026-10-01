import Foundation

struct ICloudBackupStatus: Equatable {
    let title: String
    let detail: String
}

enum ICloudLedgerBackup {
    private static let folderName = "DailyMint"
    private static let backupFileName = "ledger-backup-v1.json"

    private struct BackupFile: Codable {
        let createdAt: Date
        let appRelease: String
        let ledgerSnapshot: String
    }

    static var isDisabledForUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    static func restoreIfLocalMissing(to localURL: URL) -> ICloudBackupStatus? {
        guard !isDisabledForUITesting else { return nil }
        guard !FileManager.default.fileExists(atPath: localURL.path) else { return nil }
        guard let backup = readBackup() else { return nil }

        do {
            try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try backup.ledgerSnapshot.write(to: localURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: localURL.path
            )
            return ICloudBackupStatus(
                title: "Backup restored",
                detail: "DailyMint restored your iCloud backup from \(displayDate(backup.createdAt))."
            )
        } catch {
            return ICloudBackupStatus(
                title: "Restore failed",
                detail: "DailyMint found an iCloud backup but could not restore it."
            )
        }
    }

    static func sync(localURL: URL) -> ICloudBackupStatus {
        if isDisabledForUITesting {
            return ICloudBackupStatus(
                title: "iCloud unavailable",
                detail: "iCloud backup is skipped while UI tests are running."
            )
        }

        if FileManager.default.fileExists(atPath: localURL.path),
           let snapshot = try? String(contentsOf: localURL, encoding: .utf8),
           !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return writeBackup(snapshot: snapshot)
        }

        guard let backup = readBackup() else {
            return ICloudBackupStatus(
                title: "No data to sync",
                detail: "Add a transaction first, or sign in to iCloud if you already have a backup."
            )
        }

        do {
            try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try backup.ledgerSnapshot.write(to: localURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: localURL.path
            )
            return ICloudBackupStatus(
                title: "Backup restored",
                detail: "DailyMint restored your iCloud backup from \(displayDate(backup.createdAt))."
            )
        } catch {
            return ICloudBackupStatus(
                title: "Restore failed",
                detail: "DailyMint found an iCloud backup but could not restore it."
            )
        }
    }

    private static func writeBackup(snapshot: String) -> ICloudBackupStatus {
        guard let backupURL = backupURL() else {
            return ICloudBackupStatus(
                title: "iCloud unavailable",
                detail: "Sign in to iCloud in iPhone Settings, then make sure iCloud Drive is enabled for DailyMint."
            )
        }

        let backup = BackupFile(
            createdAt: Date(),
            appRelease: appRelease,
            ledgerSnapshot: snapshot
        )

        do {
            try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(backup).write(to: backupURL, options: .atomic)
            return ICloudBackupStatus(
                title: "Backup saved",
                detail: "Your DailyMint data is backed up to iCloud."
            )
        } catch {
            return ICloudBackupStatus(
                title: "Backup failed",
                detail: "DailyMint could not write the backup to iCloud. Please try again."
            )
        }
    }

    private static func readBackup() -> BackupFile? {
        guard let backupURL = backupURL() else { return nil }
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: backupURL)
        }
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BackupFile.self, from: data)
    }

    private static func backupURL() -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(backupFileName, isDirectory: false)
    }

    private static var appRelease: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
