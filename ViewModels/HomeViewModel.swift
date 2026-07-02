import Foundation
import FirebaseAuth

// MARK: – MVVM | ViewModel
// Owns the filtered entry list for the Home tab (shared by ListViewController and MapViewController).
// On init: shows local cache immediately, then fetches from Firestore in the background.
// Manual refresh is available via fetchFromFirestore().

final class HomeViewModel {

    static let maxPins = 3

    // MARK: – Output callbacks

    /// Called on the main thread whenever the filtered entries change (local or cloud).
    var onEntriesUpdated: (() -> Void)?
    /// Called when a Firestore fetch fails. Local cache remains visible.
    var onFetchError: ((String) -> Void)?
    /// Called when the user tries to pin a 4th entry.
    var onPinLimitReached: (() -> Void)?

    /// Pinned entries in pin order (max 3). Respects active filter/search.
    private(set) var pinnedEntries: [FoodEntry] = []
    /// All non-pinned entries, sorted newest first. Respects active filter/search.
    private(set) var entries: [FoodEntry] = []

    private(set) var activeFilter: FoodCategory?
    private(set) var searchQuery: String = ""
    private(set) var isFetching = false

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

    /// Removes the entry from the local cache immediately, then deletes it from
    /// Firestore in the background. The UI updates right away via NotificationCenter.
    func delete(_ entry: FoodEntry) {
        DataManager.shared.unpin(entry)
        DataManager.shared.delete(entry)
        EntryService.shared.delete(entry: entry)
        syncPinsToFirestore()
    }

    /// Pins or unpins an entry. Enforces the 3-pin cap via onPinLimitReached.
    func togglePin(_ entry: FoodEntry) {
        let id = entry.id.uuidString
        if DataManager.shared.pinnedIDs.contains(id) {
            DataManager.shared.unpin(entry)
        } else {
            guard DataManager.shared.pinnedIDs.count < HomeViewModel.maxPins else {
                onPinLimitReached?()
                return
            }
            DataManager.shared.pin(entry)
        }
        syncPinsToFirestore()
    }

    func isPinned(_ entry: FoodEntry) -> Bool {
        DataManager.shared.pinnedIDs.contains(entry.id.uuidString)
    }

    /// Downloads the current user's entries from Firestore and refreshes the list.
    /// Safe to call multiple times (guards against concurrent fetches).
    func fetchFromFirestore() {
        guard !isFetching else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        isFetching = true

        EntryService.shared.fetchEntries(for: uid) { [weak self] result in
            guard let self else { return }
            self.isFetching = false

            switch result {
            case .success(let fetched):
                DataManager.shared.replaceEntries(fetched)
                // reload() fires automatically via NotificationCenter → entriesDidChange

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
        var result = DataManager.shared.entries

        if let cat = activeFilter {
            result = result.filter { $0.category == cat }
        }

        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter { entry in
                entry.placeName.localizedCaseInsensitiveContains(q)
                || entry.comment.localizedCaseInsensitiveContains(q)
                || entry.category.rawValue.localizedCaseInsensitiveContains(q)
            }
        }

        let pinnedIDs = DataManager.shared.pinnedIDs
        // Preserve pin order by sorting pinned entries by their index in pinnedIDs
        pinnedEntries = result
            .filter  { pinnedIDs.contains($0.id.uuidString) }
            .sorted  { (pinnedIDs.firstIndex(of: $0.id.uuidString) ?? 0) <
                       (pinnedIDs.firstIndex(of: $1.id.uuidString) ?? 0) }
        entries = result.filter { !pinnedIDs.contains($0.id.uuidString) }

        DispatchQueue.main.async { self.onEntriesUpdated?() }
    }
}
