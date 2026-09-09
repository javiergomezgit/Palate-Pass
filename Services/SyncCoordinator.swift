// MARK: – Service
// Owns the outbox: any write that cannot reach Firebase is kept on disk and replayed
// automatically the next time the device is online.
//
// ViewModels submit operations here instead of calling EntryService directly, so a
// failed write always leaves a durable, retryable record rather than a local-only
// entry that the next Firestore fetch would silently overwrite.

import UIKit
import Network
import FirebaseAuth

// MARK: – Pending operation

/// One queued write. Persisted by DataManager so it survives relaunches.
struct PendingOperation: Codable, Identifiable {

    enum Kind: String, Codable {
        case create, update, delete

        var label: String {
            switch self {
            case .create: return "New entry"
            case .update: return "Edit"
            case .delete: return "Deletion"
            }
        }
    }

    /// Checkin/place id — at most one pending operation per entry.
    var id:            String
    var kind:          Kind
    var placeCheckin:  PlaceCheckin
    /// The last state the cloud saw. EntryService.update needs it to recalculate
    /// the place's rolling average.
    var oldCheckin:    Checkin?
    /// Storage URLs to remove once replacement images upload successfully.
    var oldImageURLs:  [String]
    /// False when only text/rating changed, so a retry doesn't re-upload photos.
    var imagesChanged: Bool
    var queuedAt:      Date
    var attempts:      Int
    var lastError:     String?

    /// Stops a permanently failing operation from blocking everything queued behind it.
    static let maxAutomaticAttempts = 5

    var hasExhaustedRetries: Bool { attempts >= PendingOperation.maxAutomaticAttempts }
}

// MARK: – Submission result

enum SubmitResult {
    /// The write reached Firebase.
    case synced
    /// The write is stored locally and will be retried automatically.
    case queued(reason: String)
}

// MARK: – SyncCoordinator

final class SyncCoordinator {

    static let shared = SyncCoordinator()

    // MARK: – Connectivity

    private let monitor      = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.palatepass.sync.monitor")

    /// Starts optimistic: the first write attempts the network rather than queueing
    /// blind, since NWPathMonitor's first callback is not synchronous.
    private(set) var isOnline = true

    // MARK: – State

    private(set) var isFlushing = false

    /// Firestore does not time out a commit while offline — it waits indefinitely for
    /// the server. Without this the save spinner would hang forever.
    private let writeTimeout: TimeInterval = 20

    // MARK: – Init

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let cameOnline = online && !self.isOnline
                self.isOnline = online
                self.notifyStateChanged()
                if cameOnline { self.flush() }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Call once at launch so connectivity monitoring starts before the first save.
    func start() {}

    // MARK: – Status (read by the UI)

    var pendingCount: Int { DataManager.shared.pendingOperations.count }

    var hasPending: Bool { pendingCount > 0 }

    var statusSummary: String {
        if !isOnline { return hasPending ? "Offline · \(pendingCount) waiting" : "Offline" }
        if isFlushing { return "Syncing…" }
        if hasPending { return "\(pendingCount) waiting to upload" }
        return "All entries synced"
    }

    // MARK: – Submit

    /// Records the operation durably, then tries to push it straight away.
    /// The caller has already updated the local cache — this only handles the cloud.
    func submit(kind: PendingOperation.Kind,
                placeCheckin: PlaceCheckin,
                oldCheckin: Checkin? = nil,
                oldImageURLs: [String] = [],
                imagesChanged: Bool = false,
                completion: ((SubmitResult) -> Void)? = nil) {

        let op = PendingOperation(
            id:            placeCheckin.checkin.id,
            kind:          kind,
            placeCheckin:  placeCheckin,
            oldCheckin:    oldCheckin,
            oldImageURLs:  oldImageURLs,
            imagesChanged: imagesChanged,
            queuedAt:      Date(),
            attempts:      0,
            lastError:     nil
        )

        // Enqueue *before* attempting the write. If the app is killed mid-upload the
        // operation is still on disk and gets replayed on the next launch.
        DataManager.shared.enqueue(op)

        guard isOnline else {
            completion?(.queued(reason: "No internet connection."))
            return
        }

        perform(op) { [weak self] error in
            if let error {
                DataManager.shared.recordFailure(id: op.id, message: error.localizedDescription)
                completion?(.queued(reason: error.localizedDescription))
            } else {
                DataManager.shared.dequeue(id: op.id)
                completion?(.synced)
            }
            self?.notifyStateChanged()
        }
    }

    // MARK: – Flush

    /// Replays every queued operation, oldest first. Safe to call repeatedly.
    /// - Parameter force: also retry operations that have exhausted their automatic
    ///   attempts (used by the manual "Sync Now" button).
    func flush(force: Bool = false, completion: (() -> Void)? = nil) {
        guard !isFlushing, isOnline, Auth.auth().currentUser != nil else {
            completion?()
            return
        }

        var remaining = DataManager.shared.pendingOperations
            .filter { force || !$0.hasExhaustedRetries }
            .sorted { $0.queuedAt < $1.queuedAt }

        guard !remaining.isEmpty else { completion?(); return }

        isFlushing = true
        notifyStateChanged()

        func finish() {
            self.isFlushing = false
            self.notifyStateChanged()
            completion?()
        }

        func step() {
            guard !remaining.isEmpty else { finish(); return }
            let op = remaining.removeFirst()
            self.perform(op) { error in
                if let error {
                    DataManager.shared.recordFailure(id: op.id, message: error.localizedDescription)
                    // A failure here nearly always means the connection dropped again.
                    // Stop rather than burning an attempt on every remaining operation;
                    // the next reconnect or foreground resumes where this left off.
                    finish()
                } else {
                    DataManager.shared.dequeue(id: op.id)
                    step()
                }
            }
        }

        step()
    }

    /// Queues entries that exist only on this device: saved before the outbox existed,
    /// or stranded when an upload failed. Called after every merge so a stranded entry
    /// gets a retry record instead of waiting to be dropped by the next fetch.
    func adopt(_ entries: [PlaceCheckin]) {
        guard !entries.isEmpty else { return }
        for pc in entries where !DataManager.shared.isPending(id: pc.checkin.id) {
            DataManager.shared.enqueue(PendingOperation(
                id:            pc.checkin.id,
                kind:          .create,
                placeCheckin:  pc,
                oldCheckin:    nil,
                oldImageURLs:  [],
                imagesChanged: !pc.checkin.imagePaths.isEmpty,
                queuedAt:      pc.checkin.checkedInAt,
                attempts:      0,
                lastError:     nil
            ))
        }
        notifyStateChanged()
    }

    /// Drops a queued operation without running it. The local entry is left alone.
    func discard(id: String) {
        DataManager.shared.dequeue(id: id)
        notifyStateChanged()
    }

    // MARK: – Private: perform one operation

    private func perform(_ op: PendingOperation, completion: @escaping (Error?) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(syncError("Not signed in.")); return
        }

        // Guarantees `completion` runs exactly once, even if a Firebase callback never
        // fires because the connection died mid-write.
        var finished = false
        let done: (Error?) -> Void = { error in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(error)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + writeTimeout) { [weak self] in
            guard let self else { return }
            done(self.syncError("Timed out waiting for the network."))
        }

        let images = op.imagesChanged || op.kind == .create ? localImages(for: op) : []

        switch op.kind {
        case .create:
            EntryService.shared.create(op.placeCheckin, images: images, uid: uid, completion: done)

        case .update:
            EntryService.shared.update(op.placeCheckin,
                                       oldCheckin:   op.oldCheckin ?? op.placeCheckin.checkin,
                                       images:       images,
                                       oldImageURLs: op.oldImageURLs,
                                       uid:          uid,
                                       completion:   done)

        case .delete:
            EntryService.shared.delete(pc: op.placeCheckin, uid: uid) { done($0) }
        }
    }

    /// Re-reads the entry's photos from Documents/ so a queued upload survives a relaunch.
    private func localImages(for op: PendingOperation) -> [UIImage] {
        op.placeCheckin.checkin.imagePaths.compactMap { DataManager.shared.loadImage(named: $0) }
    }

    private func notifyStateChanged() {
        NotificationCenter.default.post(name: .syncStateDidChange, object: nil)
    }

    private func syncError(_ message: String) -> NSError {
        NSError(domain: "SyncCoordinator", code: 0,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: – Notification

extension Notification.Name {
    /// Posted whenever connectivity or the outbox changes, so badges can refresh.
    static let syncStateDidChange = Notification.Name("syncStateDidChange")
}
