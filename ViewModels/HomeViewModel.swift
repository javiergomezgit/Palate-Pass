import Foundation
import FirebaseAuth

// MARK: – MVVM | ViewModel
// Owns the filtered entry list for the Home tab (shared by ListViewController and MapViewController).
// On init: shows local cache immediately, then fetches from Firestore in the background.
// Manual refresh is available via fetchFromFirestore().

final class HomeViewModel {

    // MARK: – Output callbacks

    /// Called on the main thread whenever the filtered entries change (local or cloud).
    var onEntriesUpdated: (() -> Void)?
    /// Called when a Firestore fetch fails. Local cache remains visible.
    var onFetchError: ((String) -> Void)?

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
        reload()                // show local cache immediately
        fetchFromFirestore()    // then sync from cloud
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
        DataManager.shared.delete(entry)                          // local — instant
        EntryService.shared.delete(entryId: entry.id.uuidString) // cloud — async
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

    @objc private func reload() {
        var result = DataManager.shared.entries

        // 1. Category filter
        if let cat = activeFilter {
            result = result.filter { $0.category == cat }
        }

        // 2. Search query — matches place name, comment, or category
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter { entry in
                entry.placeName.localizedCaseInsensitiveContains(q)
                || entry.comment.localizedCaseInsensitiveContains(q)
                || entry.category.rawValue.localizedCaseInsensitiveContains(q)
            }
        }

        entries = result
        DispatchQueue.main.async { self.onEntriesUpdated?() }
    }
}
