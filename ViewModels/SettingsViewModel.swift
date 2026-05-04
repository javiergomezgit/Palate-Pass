// MARK: – MVVM | ViewModel
// Provides display values and mutations for the Settings screen.
// Profile data is sourced from FirebaseAuth (live) + Firestore (extended profile).
// Local DataManager is still used for entry stats until entries migrate to Firestore.

import UIKit
import FirebaseAuth

final class SettingsViewModel {

    // MARK: – Output callbacks

    var onMessage:       ((String) -> Void)?
    var onExportReady:   ((URL) -> Void)?
    var onProfileLoaded: (() -> Void)?      // fires when Firestore profile arrives
    var onSignOut:       (() -> Void)?

    // MARK: – Cached Firestore profile

    private(set) var userProfile: UserProfile?

    // MARK: – Profile: display name

    /// Editable name shown in the Settings header.
    /// Priority: Firestore displayName → email prefix → empty
    var displayName: String {
        get {
            if let name = userProfile?.displayName, !name.isEmpty { return name }
            return UserProfile.nameFromEmail(Auth.auth().currentUser?.email)
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }

            // 1. Update Firebase Auth profile (so other parts of the app stay in sync)
            let request = Auth.auth().currentUser?.createProfileChangeRequest()
            request?.displayName = trimmed
            request?.commitChanges { _ in }

            // 2. Update Firestore document
            UserService.shared.updateDisplayName(trimmed, uid: uid)

            // 3. Keep local cache in sync
            userProfile?.displayName = trimmed
        }
    }

    var email: String { Auth.auth().currentUser?.email ?? "" }

    var isEmailVerified: Bool { Auth.auth().currentUser?.isEmailVerified ?? false }

    var memberSince: String { userProfile?.memberSinceText ?? "–" }

    var authProvider: String { userProfile?.authProvider ?? "–" }

    // MARK: – Avatar (local for now; will migrate to Firebase Storage)

    var avatarImage: UIImage? {
        guard let data = UserDefaults.standard.data(forKey: "avatarImageData") else { return nil }
        return UIImage(data: data)
    }

    func saveAvatar(_ image: UIImage) {
        let data = image.jpegData(compressionQuality: 0.85)
        UserDefaults.standard.set(data, forKey: "avatarImageData")
    }

    // MARK: – Entry stats

    var entryCount: Int { DataManager.shared.entries.count }

    var averageRatingText: String {
        let entries = DataManager.shared.entries
        guard !entries.isEmpty else { return "–" }
        let avg = entries.map(\.rating).reduce(0, +) / Double(entries.count)
        return String(format: "%.1f", avg)
    }

    var statsLine: String { "\(entryCount) entries · avg ⭐ \(averageRatingText)" }

    // MARK: – Settings options

    var defaultPrivacyLabel: String {
        let isPublic = UserDefaults.standard.object(forKey: "defaultPublic") == nil
            ? true : UserDefaults.standard.bool(forKey: "defaultPublic")
        return isPublic ? "Public" : "Private"
    }

    var currentSortOrder: String {
        UserDefaults.standard.string(forKey: "sortOrder") ?? "Date (newest first)"
    }

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

    // MARK: – Data operations

    func exportData() {
        guard
            let data = try? JSONEncoder().encode(DataManager.shared.entries),
            let json = String(data: data, encoding: .utf8)
        else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("palatepass_export.json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        onExportReady?(url)
    }

    func deleteAllEntries() {
        DataManager.shared.entries.forEach { DataManager.shared.delete($0) }
    }

    // MARK: – Firestore profile

    func loadProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserService.shared.fetchProfile(uid: uid) { [weak self] profile in
            DispatchQueue.main.async {
                self?.userProfile = profile
                self?.onProfileLoaded?()
            }
        }
    }

    // MARK: – Sign out

    func signOut() {
        try? Auth.auth().signOut()
        onSignOut?()
    }
}
