import Foundation

// MARK: – MVVM | ViewModel
// Owns the filtered entry list for the Home tab (shared by ListViewController and MapViewController).
// Observes DataManager and re-publishes changes through a closure so the Views never touch the data layer.

final class HomeViewModel {

    // MARK: – Output (View binds to these)

    /// Called on the main thread whenever the filtered entries change.
    var onEntriesUpdated: (() -> Void)?

    private(set) var entries: [FoodEntry] = []
    private(set) var activeFilter: FoodCategory?

    // MARK: – Init

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload),
            name: .entriesDidChange, object: nil
        )
        reload()
    }

    // MARK: – Input (View calls these)

    func applyFilter(_ category: FoodCategory?) {
        activeFilter = category
        reload()
    }

    // MARK: – Private

    @objc private func reload() {
        let all = DataManager.shared.entries
        entries = activeFilter.map { cat in all.filter { $0.category == cat } } ?? all
        onEntriesUpdated?()
    }
}
