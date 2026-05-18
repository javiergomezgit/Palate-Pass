// MARK: – MVVM | Service / Repository
// The only class allowed to read and write persisted data.
// ViewModels call this; Views and ViewControllers never touch it directly.

import Foundation
import UIKit

final class DataManager {

    static let shared = DataManager()
    private init() { load() }

    private let entriesKey = "foodie_entries"
    private(set) var entries: [FoodEntry] = []

    // MARK: – CRUD

    func add(_ entry: FoodEntry) {
        entries.insert(entry, at: 0)
        save()
        notify()
    }

    func update(_ entry: FoodEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        save()
        notify()
    }

    func delete(_ entry: FoodEntry) {
        if let path = entry.imagePath { deleteImage(named: path) }
        entries.removeAll { $0.id == entry.id }
        save()
        notify()
    }

    /// Replaces the entire local cache with data fetched from Firestore.
    /// Already-sorted entries are written to UserDefaults and listeners are notified.
    func replaceEntries(_ newEntries: [FoodEntry]) {
        entries = newEntries
        save()
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
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: entriesKey),
            let saved = try? JSONDecoder().decode([FoodEntry].self, from: data)
        else { return }
        entries = saved
    }

    private func notify() {
        NotificationCenter.default.post(name: .entriesDidChange, object: nil)
    }
}

extension Notification.Name {
    static let entriesDidChange = Notification.Name("entriesDidChange")
}
