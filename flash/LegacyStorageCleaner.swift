import Foundation
import OSLog

enum LegacyStorageCleaner {
    private static let cleanupKey = "didRemoveLegacyFirebaseCache"
    private static let logger = Logger(subsystem: "abbe.ca.flash", category: "StorageCleanup")
    private static let legacyDirectoryNames = ["firestore", "google-heartbeat-storage"]

    static func removeFirebaseCacheIfNeeded(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) {
        guard !userDefaults.bool(forKey: cleanupKey) else { return }
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.error("Unable to locate Application Support for legacy cache cleanup")
            return
        }

        do {
            for directoryName in legacyDirectoryNames {
                let directory = applicationSupport.appendingPathComponent(
                    directoryName,
                    isDirectory: true
                )
                guard fileManager.fileExists(atPath: directory.path) else { continue }
                try fileManager.removeItem(at: directory)
            }

            userDefaults.set(true, forKey: cleanupKey)
        } catch {
            logger.error(
                "Legacy Firebase cache cleanup failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
