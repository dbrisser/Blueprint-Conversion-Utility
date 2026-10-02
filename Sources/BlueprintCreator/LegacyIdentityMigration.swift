import Foundation

/// Migrates preferences from the former application identity after the bundle
/// identifier changes. The new preferences domain is authoritative once it
/// contains settings.
enum LegacyIdentityMigration {
    private static let oldBundleIdentifier = "com.jarredwheeler.blueprintcreator"
    private static let settingsKey = "BlueprintCreator.Settings"
    private static let updateCheckKey = "BlueprintCreator.LastAppUpdateCheck"

    static func runIfNeeded() {
        let currentDefaults = UserDefaults.standard
        guard currentDefaults.data(forKey: settingsKey) == nil else { return }
        guard let legacyDefaults = UserDefaults(suiteName: oldBundleIdentifier) else { return }

        if let settings = legacyDefaults.data(forKey: settingsKey) {
            currentDefaults.set(settings, forKey: settingsKey)
        }
        if let updateDate = legacyDefaults.object(forKey: updateCheckKey) as? Date {
            currentDefaults.set(updateDate, forKey: updateCheckKey)
        }
        currentDefaults.synchronize()
    }
}
