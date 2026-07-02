import Foundation
import FirebaseAuth

// MARK: – MVVM | ViewModel
// Owns the filtered checkin list for the Home tab (shared by ListViewController and MapViewController).
// On init: shows local cache immediately, then fetches from Firestore in the background.

final class HomeViewModel {

    static let maxPins = 3

    // MARK: – Output callbacks

    var onEntriesUpdated: (() -> Void)?
    var onFetchError:     ((String) -> Void)?
    var onPinLimitReached: (() -> Void)?

    /// Pinned checkins in pin order (max 3). Respects active filter/search.
    private(set) var pinnedEntries: [PlaceCheckin] = []
    /// All non-pinned checkins, sorted newest first. Respects active filter/search.
    private(set) var entries: [PlaceCheckin] = []

    private(set) var activeFilter: FoodCategory?
    private(set) var searchQuery:  String = ""
    private(set) var isFetching    = false

    // MARK: – Init

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload),
            name: .entriesDidChange, object: nil
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

    func applySearch(_ query: String) {
        searchQuery = query
        reload()
    }

    func delete(_ pc: PlaceCheckin) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        DataManager.shared.unpin(pc)
        DataManager.shared.delete(pc)
        EntryService.shared.delete(pc: pc, uid: uid)
        syncPinsToFirestore()
    }

    func togglePin(_ pc: PlaceCheckin) {
        let id = pc.checkin.id
        if DataManager.shared.pinnedIDs.contains(id) {
            DataManager.shared.unpin(pc)
        } else {
            guard DataManager.shared.pinnedIDs.count < HomeViewModel.maxPins else {
                onPinLimitReached?()
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
                DataManager.shared.replaceAll(fetched)
            case .failure(let error):
                self.onFetchError?(error.localizedDescription)
            }
        }
    }

    // MARK: – Private

    private func fetchPinnedIDs() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserService.shared.fetchPinnedIDs(uid: uid) { ids in
            DataManager.shared.replacePinnedIDs(ids)
        }
    }

    private func syncPinsToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserService.shared.updatePinnedIDs(DataManager.shared.pinnedIDs, uid: uid)
    }

    @objc private func reload() {
        var result = DataManager.shared.checkins

        if let cat = activeFilter {
            result = result.filter { FoodCategory(rawValue: $0.place.category) == cat }
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

        DispatchQueue.main.async { self.onEntriesUpdated?() }
    }
}
