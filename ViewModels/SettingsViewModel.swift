import UIKit

// MARK: – MVVM | ViewModel
// Provides computed stats, settings mutations, and data operations for the Settings screen.
// All UserDefaults and DataManager access lives here; the View only presents results.

final class SettingsViewModel {

    // MARK: – Output (View binds to these)

    var onMessage: ((String) -> Void)?
    var onExportReady: ((URL) -> Void)?

    // MARK: – User profile

    var username: String {
        get { UserDefaults.standard.string(forKey: "username") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "username") }
    }

    var avatarImage: UIImage? {
        guard let data = UserDefaults.standard.data(forKey: "avatarImageData") else { return nil }
        return UIImage(data: data)
    }

    func saveAvatar(_ image: UIImage) {
        let data = image.jpegData(compressionQuality: 0.85)
        UserDefaults.standard.set(data, forKey: "avatarImageData")
    }

    // MARK: – Computed display values

    var entryCount: Int { DataManager.shared.entries.count }

    var averageRatingText: String {
        let entries = DataManager.shared.entries
        guard !entries.isEmpty else { return "–" }
        let avg = entries.map(\.rating).reduce(0, +) / Double(entries.count)
        return String(format: "%.1f", avg)
    }

    var statsLine: String { "\(entryCount) entries · avg ⭐ \(averageRatingText)" }

    var defaultPrivacyLabel: String {
        let isPublic = UserDefaults.standard.object(forKey: "defaultPublic") == nil
            ? true : UserDefaults.standard.bool(forKey: "defaultPublic")
        return isPublic ? "Default: Public" : "Default: Private"
    }

    var currentSortOrder: String {
        UserDefaults.standard.string(forKey: "sortOrder") ?? "Date (newest first)"
    }

    // MARK: – Input (View calls these)

    func toggleDefaultPrivacy() {
        let current = UserDefaults.standard.object(forKey: "defaultPublic") == nil
            ? true : UserDefaults.standard.bool(forKey: "defaultPublic")
        UserDefaults.standard.set(!current, forKey: "defaultPublic")
        let msg = !current ? "New entries will default to Public." : "New entries will default to Private."
        onMessage?(msg)
    }

    func setSortOrder(_ order: String) {
        UserDefaults.standard.set(order, forKey: "sortOrder")
    }

    func exportData() {
        guard
            let data = try? JSONEncoder().encode(DataManager.shared.entries),
            let json = String(data: data, encoding: .utf8)
        else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodie_export.json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        onExportReady?(url)
    }

    func deleteAllEntries() {
        DataManager.shared.entries.forEach { DataManager.shared.delete($0) }
    }
}
