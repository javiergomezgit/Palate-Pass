// MARK: – MVVM | Service / Repository
// The only class allowed to read and write persisted data.
// ViewModels call this; Views and ViewControllers never touch it directly.
//
// Persists three things:
//   • the entry cache      (palate_checkins)
//   • the pinned id list   (foodie_pinned_ids)
//   • the sync outbox      (palate_outbox) — writes that have not reached Firebase yet

import Foundation
import UIKit

final class DataManager {

    static let shared = DataManager()
    private init() { load() }

    private let checkinsKey = "palate_checkins"
    private let pinnedKey   = "foodie_pinned_ids"
    private let outboxKey   = "palate_outbox"
    private let syncedKey   = "palate_synced_ids"

    private(set) var checkins: [PlaceCheckin] = []

    /// Ordered list of pinned placeID strings (max 3, index 0 = top).
    private(set) var pinnedIDs: [String] = []

    /// Writes waiting to reach Firebase, oldest first.
    private(set) var pendingOperations: [PendingOperation] = []

    /// Every checkin id a Firestore fetch has ever returned. An entry missing from the
    /// cloud means two very different things depending on whether it appears here:
    /// deleted on another device, or never successfully uploaded.
    private var syncedIDs: Set<String> = []

    // MARK: – CRUD

    func add(_ pc: PlaceCheckin) {
        checkins.append(pc)
        sortByDate()
        save()
        notify()
    }

    func update(_ pc: PlaceCheckin) {
        guard let idx = checkins.firstIndex(where: { $0.checkin.id == pc.checkin.id }) else { return }
        let removedPaths = Set(checkins[idx].checkin.imagePaths).subtracting(pc.checkin.imagePaths)
        removedPaths.forEach { deleteImage(named: $0) }
        checkins[idx] = pc
        sortByDate()
        save()
        notify()
    }

    func delete(_ pc: PlaceCheckin) {
        // Photos are kept until the queued deletion actually reaches Firebase — the
        // upload may still need them if the entry was never synced in the first place.
        if !isPending(id: pc.checkin.id) {
            pc.checkin.imagePaths.forEach { deleteImage(named: $0) }
        }
        checkins.removeAll { $0.checkin.id == pc.checkin.id }
        save()
        notify()
    }

    /// Folds a Firestore fetch into the local cache.
    ///
    /// Replaces the old `replaceAll`, which overwrote everything and destroyed entries
    /// that had never been uploaded. Anything still in the outbox wins over the server
    /// copy, and local image paths are carried across so cached photos aren't orphaned.
    ///
    /// - Returns: entries that exist only on this device and have no queued upload —
    ///   stranded by a failed save, or predating the outbox entirely. The caller queues
    ///   them; without that they would be dropped exactly as `replaceAll` used to.
    @discardableResult
    func merge(cloud: [PlaceCheckin]) -> [PlaceCheckin] {
        let pendingByID = Dictionary(pendingOperations.map { ($0.id, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let localByID   = Dictionary(checkins.map { ($0.checkin.id, $0) },
                                     uniquingKeysWith: { first, _ in first })

        var merged: [PlaceCheckin] = []

        for var cloudPC in cloud {
            let id = cloudPC.checkin.id

            if let op = pendingByID[id] {
                switch op.kind {
                case .delete:
                    continue                        // deleted here, deletion not pushed yet
                case .create, .update:
                    merged.append(op.placeCheckin)  // local edit wins until it uploads
                    continue
                }
            }

            // Firestore has no concept of imagePaths, so its decoder leaves them empty.
            // Carry the local filenames over, otherwise every cached photo is orphaned.
            if let local = localByID[id], !local.checkin.imagePaths.isEmpty {
                cloudPC.checkin.imagePaths = local.checkin.imagePaths
            }
            merged.append(cloudPC)
        }

        // Entries that only exist here because their upload never succeeded.
        let cloudIDs = Set(cloud.map { $0.checkin.id })
        for op in pendingOperations where op.kind != .delete && !cloudIDs.contains(op.id) {
            merged.append(op.placeCheckin)
        }

        // Local entries with no queued upload and no cloud copy. If the cloud has shown
        // us the id before, it has since been deleted elsewhere and should go. If it
        // never has, the entry simply never made it up — keep it and hand it back to be
        // queued. On the first run after upgrading, syncedIDs is empty, so everything
        // stranded is kept: resurrecting an entry once beats losing it permanently.
        var stranded: [PlaceCheckin] = []
        for local in checkins where !cloudIDs.contains(local.checkin.id)
                                 && !isPending(id: local.checkin.id) {
            guard !syncedIDs.contains(local.checkin.id) else { continue }
            merged.append(local)
            stranded.append(local)
        }

        syncedIDs.formUnion(cloudIDs)
        saveSyncedIDs()

        checkins = merged
        sortByDate()
        save()
        notify()
        return stranded
    }

    /// Keeps the cache newest-first. Called after every mutation so an edited
    /// check-in date moves the entry immediately, without waiting for a Firestore
    /// round-trip. Matches the sort order EntryService.fetchCheckins returns.
    private func sortByDate() {
        checkins.sort { $0.checkin.checkedInAt > $1.checkin.checkedInAt }
    }

    // MARK: – Outbox

    /// Adds or coalesces a pending operation. At most one is kept per entry.
    func enqueue(_ op: PendingOperation) {
        if let idx = pendingOperations.firstIndex(where: { $0.id == op.id }) {
            let existing = pendingOperations[idx]

            // Deleting something that never reached the cloud just cancels the queued work.
            if existing.kind == .create && op.kind == .delete {
                pendingOperations.remove(at: idx)
                saveOutbox()
                // delete() held these back in case the upload still needed them.
                // With the upload cancelled, nothing references them any more.
                if !checkins.contains(where: { $0.checkin.id == op.id }) {
                    existing.placeCheckin.checkin.imagePaths.forEach { deleteImage(named: $0) }
                }
                notifySync()
                return
            }

            var coalesced = op
            // An entry the server has never seen stays a create, however often it's edited.
            if existing.kind == .create { coalesced.kind = .create }
            // oldCheckin/oldImageURLs describe the last state the cloud saw, so the
            // original values are the correct ones to keep.
            coalesced.oldCheckin    = existing.oldCheckin ?? op.oldCheckin
            coalesced.oldImageURLs  = existing.oldImageURLs.isEmpty ? op.oldImageURLs : existing.oldImageURLs
            coalesced.imagesChanged = existing.imagesChanged || op.imagesChanged
            coalesced.queuedAt      = existing.queuedAt
            coalesced.attempts      = 0     // fresh content earns a fresh run of retries
            coalesced.lastError     = nil
            pendingOperations[idx]  = coalesced
        } else {
            pendingOperations.append(op)
        }
        saveOutbox()
        notifySync()
    }

    /// Removes an operation once it has succeeded (or been discarded).
    func dequeue(id: String) {
        guard let idx = pendingOperations.firstIndex(where: { $0.id == id }) else { return }
        let op = pendingOperations.remove(at: idx)
        saveOutbox()

        // A completed deletion is the point at which its photos are safe to remove.
        if op.kind == .delete, !checkins.contains(where: { $0.checkin.id == id }) {
            op.placeCheckin.checkin.imagePaths.forEach { deleteImage(named: $0) }
        }
        notifySync()
    }

    func recordFailure(id: String, message: String) {
        guard let idx = pendingOperations.firstIndex(where: { $0.id == id }) else { return }
        pendingOperations[idx].attempts += 1
        pendingOperations[idx].lastError = message
        saveOutbox()
        notifySync()
    }

    func isPending(id: String) -> Bool {
        pendingOperations.contains { $0.id == id }
    }

    func pendingOperation(id: String) -> PendingOperation? {
        pendingOperations.first { $0.id == id }
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

    /// On-disk location of a saved photo, for callers that decode it themselves
    /// (e.g. ImageLoader's downsampled thumbnails).
    func imageFileURL(named name: String) -> URL? {
        imageURL(for: name)
    }

    private func deleteImage(named name: String) {
        guard let url = imageURL(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func imageURL(for name: String) -> URL? {
        documentsDirectory()?.appendingPathComponent(name)
    }

    private func documentsDirectory() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
    }

    // MARK: – Orphaned photos

    /// Saved photos that no entry and no queued upload references any more.
    ///
    /// These accumulate when a cloud fetch drops a locally-saved entry: the entry's
    /// metadata is gone but its JPEG is still on disk. Newest file first.
    func orphanedImageFilenames() -> [String] {
        guard let dir = documentsDirectory() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []

        var referenced = Set(checkins.flatMap { $0.checkin.imagePaths })
        pendingOperations.forEach { referenced.formUnion($0.placeCheckin.checkin.imagePaths) }

        return files
            .filter { $0.hasSuffix(".jpg") && !referenced.contains($0) }
            .sorted { (imageFileDate(named: $0) ?? .distantPast) > (imageFileDate(named: $1) ?? .distantPast) }
    }

    /// When the file was written — the closest available stand-in for the lost entry's
    /// date. The photo's own capture time is not recoverable: `UIImage.jpegData` strips
    /// EXIF, so these files carry no original metadata.
    func imageFileDate(named name: String) -> Date? {
        guard let url = imageURL(for: name) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.creationDate] as? Date
    }

    /// Permanently removes an orphaned photo.
    func discardImageFile(named name: String) {
        deleteImage(named: name)
    }

    // MARK: – Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(checkins) else { return }
        UserDefaults.standard.set(data, forKey: checkinsKey)
    }

    private func savePins() {
        UserDefaults.standard.set(pinnedIDs, forKey: pinnedKey)
    }

    private func saveSyncedIDs() {
        UserDefaults.standard.set(Array(syncedIDs), forKey: syncedKey)
    }

    private func saveOutbox() {
        guard let data = try? JSONEncoder().encode(pendingOperations) else { return }
        UserDefaults.standard.set(data, forKey: outboxKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: checkinsKey),
           let saved = try? JSONDecoder().decode([PlaceCheckin].self, from: data) {
            checkins = saved
        }
        if let data = UserDefaults.standard.data(forKey: outboxKey),
           let saved = try? JSONDecoder().decode([PendingOperation].self, from: data) {
            pendingOperations = saved
        }
        pinnedIDs = UserDefaults.standard.stringArray(forKey: pinnedKey) ?? []
        syncedIDs = Set(UserDefaults.standard.stringArray(forKey: syncedKey) ?? [])
    }

    private func notify() {
        NotificationCenter.default.post(name: .entriesDidChange, object: nil)
    }

    private func notifySync() {
        NotificationCenter.default.post(name: .syncStateDidChange, object: nil)
    }
}

extension Notification.Name {
    static let entriesDidChange = Notification.Name("entriesDidChange")
}
