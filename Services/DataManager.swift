// MARK: – MVVM | Service / Repository
// The only class allowed to read and write persisted data.
// ViewModels call this; Views and ViewControllers never touch it directly.

import Foundation
import UIKit

final class DataManager {

    static let shared = DataManager()
    private init() { load() }

    private let checkinsKey = "palate_checkins"
    private let pinnedKey   = "foodie_pinned_ids"

    private(set) var checkins: [PlaceCheckin] = []

    /// Ordered list of pinned placeID strings (max 3, index 0 = top).
    private(set) var pinnedIDs: [String] = []

    // MARK: – CRUD

    func add(_ pc: PlaceCheckin) {
        checkins.insert(pc, at: 0)
        save()
        notify()
    }

    func update(_ pc: PlaceCheckin) {
        guard let idx = checkins.firstIndex(where: { $0.checkin.id == pc.checkin.id }) else { return }
        let removedPaths = Set(checkins[idx].checkin.imagePaths).subtracting(pc.checkin.imagePaths)
        removedPaths.forEach { deleteImage(named: $0) }
        checkins[idx] = pc
        save()
        notify()
    }

    func delete(_ pc: PlaceCheckin) {
        pc.checkin.imagePaths.forEach { deleteImage(named: $0) }
        checkins.removeAll { $0.checkin.id == pc.checkin.id }
        save()
        notify()
    }

    /// Replaces the entire local cache with data fetched from Firestore.
    func replaceAll(_ new: [PlaceCheckin]) {
        checkins = new
        save()
        notify()
    }

    // MARK: – Pin management

    func pin(_ pc: PlaceCheckin) {
        let id = pc.checkin.id
        guard !pinnedIDs.contains(id) else { return }
        pinnedIDs.append(id)
        savePins()
        notify()
    }

    func unpin(_ pc: PlaceCheckin) {
        pinnedIDs.removeAll { $0 == pc.checkin.id }
        savePins()
        notify()
    }

    func isPinned(_ pc: PlaceCheckin) -> Bool {
        pinnedIDs.contains(pc.checkin.id)
    }

    /// Replaces the entire pin list (used when syncing from Firestore).
    func replacePinnedIDs(_ ids: [String]) {
        pinnedIDs = ids
        savePins()
        notify()
    }

    // MARK: – Image helpers

    func saveImage(_ image: UIImage) -> String? {
        let name = UUID().uuidString + ".jpg"
        guard
            let data = image.jpegData(compressionQuality: 0.8),
            let url = imageURL(for: name)
        else { return nil }
        try? data.write(to: url)
        return name
    }

    func loadImage(named name: String) -> UIImage? {
        guard let url = imageURL(for: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func deleteImage(named name: String) {
        guard let url = imageURL(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func imageURL(for name: String) -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(name)
    }

    // MARK: – Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(checkins) else { return }
        UserDefaults.standard.set(data, forKey: checkinsKey)
    }

    private func savePins() {
        UserDefaults.standard.set(pinnedIDs, forKey: pinnedKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: checkinsKey),
           let saved = try? JSONDecoder().decode([PlaceCheckin].self, from: data) {
            checkins = saved
        }
        pinnedIDs = UserDefaults.standard.stringArray(forKey: pinnedKey) ?? []
    }

    private func notify() {
        NotificationCenter.default.post(name: .entriesDidChange, object: nil)
    }
}

extension Notification.Name {
    static let entriesDidChange = Notification.Name("entriesDidChange")
}
