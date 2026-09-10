import Foundation
import FirebaseAuth

// MARK: – MVVM | ViewModel
// Owns the filtered checkin list for the Home tab (shared by ListViewController and MapViewController).
// On init: shows local cache immediately, then fetches from Firestore in the background.

final class HomeViewModel {

    static let maxPins = 3

    // MARK: – Output callbacks
    // Lists of handlers, not single closures: ListViewController and MapViewController
    // share one view model, so a lone `var onEntriesUpdated` let whichever loaded
    // last silently clobber the other — the list then never reloaded its table again.

    private var entriesUpdatedHandlers:  [() -> Void]       = []
    private var fetchErrorHandlers:      [(String) -> Void] = []
    private var pinLimitReachedHandlers: [() -> Void]       = []

    /// Registers a handler called on the main thread whenever the entry lists change.
    func addEntriesUpdatedHandler(_ handler: @escaping () -> Void) {
        entriesUpdatedHandlers.append(handler)
    }

    func addFetchErrorHandler(_ handler: @escaping (String) -> Void) {
        fetchErrorHandlers.append(handler)
    }

    func addPinLimitReachedHandler(_ handler: @escaping () -> Void) {
        pinLimitReachedHandlers.append(handler)
    }

    /// Pinned checkins in pin order (max 3). Respects active filter/search.
    private(set) var pinnedEntries: [PlaceCheckin] = []
    /// All non-pinned checkins, sorted newest first. Respects active filter/search.
    private(set) var entries: [PlaceCheckin] = []

    private(set) var activeFilter: FoodCategory?
    /// Minimum personal rating an entry must have to be listed. nil = no rating filter.
    private(set) var activeRatingFilter: Double?
    private(set) var searchQuery:  String = ""
    private(set) var isFetching    = false

    // MARK: – Init

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload),
            name: .entriesDidChange, object: nil
        )
        // Redraws the "not synced" badges as the outbox drains.
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload),
            name: .syncStateDidChange, object: nil
        )
        reload()
        fetchFromFirestore()
        fetchPinnedIDs()
    }

    // MARK: – Input

    func applyFilter(_ category: FoodCategory?) {
        activeFilter = category
        reload()
    }

    func applyRatingFilter(_ minimumRating: Double?) {
        activeRatingFilter = minimumRating
        reload()
    }

    func applySearch(_ query: String) {
        searchQuery = query
        reload()
    }

    func delete(_ pc: PlaceCheckin) {
        DataManager.shared.unpin(pc)
        DataManager.shared.delete(pc)
        SyncCoordinator.shared.submit(kind: .delete, placeCheckin: pc)
        syncPinsToFirestore()
    }

    /// Changes an entry's privacy. Queued, so it survives being done offline.
    func setVisibility(_ visibility: Visibility, for pc: PlaceCheckin) {
        let previous = pc.checkin
        var updated = pc
        updated.checkin.visibility = visibility
        DataManager.shared.update(updated)
        SyncCoordinator.shared.submit(kind: .update, placeCheckin: updated, oldCheckin: previous)
    }

    /// True when this entry has changes that have not reached Firebase yet.
    func isPending(_ pc: PlaceCheckin) -> Bool {
        DataManager.shared.isPending(id: pc.checkin.id)
    }

    func togglePin(_ pc: PlaceCheckin) {
        let id = pc.checkin.id
        if DataManager.shared.pinnedIDs.contains(id) {
            DataManager.shared.unpin(pc)
        } else {
            guard DataManager.shared.pinnedIDs.count < HomeViewModel.maxPins else {
                pinLimitReachedHandlers.forEach { $0() }
                return
            }
            DataManager.shared.pin(pc)
        }
        syncPinsToFirestore()
    }

    func isPinned(_ pc: PlaceCheckin) -> Bool {
        DataManager.shared.isPinned(pc)
    }

    func fetchFromFirestore() {
        guard !isFetching else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isFetching = true
        EntryService.shared.fetchCheckins(for: uid) { [weak self] result in
            guard let self else { return }
            self.isFetching = false
            switch result {
            case .success(let fetched):
                // merge, not replace: entries still queued for upload must survive.
                // Anything the cloud has never seen gets queued rather than dropped.
                let stranded = DataManager.shared.merge(cloud: fetched)
                SyncCoordinator.shared.adopt(stranded)
                SyncCoordinator.shared.flush()
            case .failure(let error):
                let message = error.localizedDescription
                DispatchQueue.main.async { self.fetchErrorHandlers.forEach { $0(message) } }
            }
        }
    }

    // MARK: – Private

    private func fetchPinnedIDs() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserService.shared.fetchPinnedIDs(uid: uid) { ids in
            // nil = the read failed; keep whatever is pinned locally rather than
            // clearing it. Local pins are re-uploaded on the next togglePin.
            guard let ids else { return }
            DataManager.shared.replacePinnedIDs(ids)
        }
    }

    private func syncPinsToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserService.shared.updatePinnedIDs(DataManager.shared.pinnedIDs, uid: uid)
    }

    @objc private func reload() {
        // Sync and Firestore callbacks post .entriesDidChange from background threads.
        // The lists below are read by the table view on the main thread, so all
        // mutation has to happen there too — otherwise counts and contents can
        // disagree mid-render (duplicated rows) or crash.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reload() }
            return
        }

        var result = DataManager.shared.checkins

        if let cat = activeFilter {
            result = result.filter { FoodCategory(rawValue: $0.place.category) == cat }
        }

        if let minRating = activeRatingFilter {
            result = result.filter { $0.checkin.personalRating >= minRating }
        }

        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter { pc in
                pc.place.name.localizedCaseInsensitiveContains(q)
                || pc.checkin.personalComment.localizedCaseInsensitiveContains(q)
                || pc.place.category.localizedCaseInsensitiveContains(q)
            }
        }

        let pinnedIDs = DataManager.shared.pinnedIDs
        pinnedEntries = result
            .filter  { pinnedIDs.contains($0.checkin.id) }
            .sorted  { (pinnedIDs.firstIndex(of: $0.checkin.id) ?? 0) <
                       (pinnedIDs.firstIndex(of: $1.checkin.id) ?? 0) }
        entries = result.filter { !pinnedIDs.contains($0.checkin.id) }

        // Deferred one tick, as before: `reload()` can run inside a swipe-action or
        // alert handler, and reloading the table synchronously from there is fragile.
        // The lists themselves are already updated, and the table renders from its own
        // snapshot, so nothing can observe an inconsistent state in the meantime.
        DispatchQueue.main.async { [weak self] in
            self?.entriesUpdatedHandlers.forEach { $0() }
        }
    }
}
