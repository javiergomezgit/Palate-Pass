import UIKit

// MARK: – MVVM | ViewModel
// Wraps a single FoodEntry and exposes formatted display values and mutating actions.
// The View never reads raw model fields — it asks the ViewModel for everything.

final class EntryDetailViewModel {

    // MARK: – Output (View binds to these)

    var onEntryUpdated: (() -> Void)?

    // MARK: – Formatted display values

    var itemName: String    { entry.name }
    var placeName: String   { entry.placeName.isEmpty ? "Unknown place" : entry.placeName }
    var categoryBadge: String { "\(entry.category.emoji) \(entry.category.rawValue)" }
    var rating: Double      { entry.rating }
    var formattedRating: String { String(format: "%.1f / 5.0", entry.rating) }
    var comment: String     { entry.comment }
    var hasComment: Bool    { !entry.comment.isEmpty }
    var isPublic: Bool      { entry.isPublic }
    var privacyText: String { entry.isPublic ? "🌍 Public" : "🔒 Private" }
    var category: FoodCategory { entry.category }
    var coordinate: (latitude: Double, longitude: Double)? {
        guard let lat = entry.latitude, let lon = entry.longitude else { return nil }
        return (lat, lon)
    }
    var photo: UIImage? {
        guard let path = entry.imagePath else { return nil }
        return DataManager.shared.loadImage(named: path)
    }
    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .short
        return fmt.string(from: entry.date)
    }

    /// A fully configured AddEntryViewModel seeded with this entry, ready to hand to the edit screen.
    var editViewModel: AddEntryViewModel { AddEntryViewModel(editing: entry) }

    // MARK: – Private

    private(set) var entry: FoodEntry

    // MARK: – Init

    init(entry: FoodEntry) {
        self.entry = entry
    }

    // MARK: – Input (View calls these)

    func togglePrivacy() {
        var updated = entry
        updated.isPublic = !entry.isPublic
        DataManager.shared.update(updated)
        entry = updated
        onEntryUpdated?()
    }

    func delete() {
        DataManager.shared.delete(entry)
    }
}
