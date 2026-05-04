import UIKit

// MARK: – MVVM | ViewModel
// Wraps a single FoodEntry and exposes formatted display values and mutating actions.
// The View never reads raw model fields — it asks the ViewModel for everything.

final class EntryDetailViewModel {

    // MARK: – Output

    var onEntryUpdated: (() -> Void)?

    // MARK: – Formatted display values

    var placeName:      String  { entry.placeName.isEmpty ? "Unknown place" : entry.placeName }
    var categoryBadge:  String  { "\(entry.category.emoji) \(entry.category.rawValue)" }
    var rating:         Double  { entry.rating }
    var formattedRating: String { String(format: "%.1f / 5.0", entry.rating) }
    var comment:        String  { entry.comment }
    var hasComment:     Bool    { !entry.comment.isEmpty }
    var visibility:     EntryVisibility { entry.visibility }
    var visibilityText: String  { entry.visibility.label }
    var category:       FoodCategory   { entry.category }

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
        return fmt.string(from: entry.checkInDate)
    }

    var editViewModel: AddEntryViewModel { AddEntryViewModel(editing: entry) }

    // MARK: – Private

    private(set) var entry: FoodEntry

    // MARK: – Init

    init(entry: FoodEntry) {
        self.entry = entry
    }

    // MARK: – Input

    /// Cycles visibility: public → friends → private → public
    func cycleVisibility() {
        var updated = entry
        switch entry.visibility {
        case .public:  updated.visibility = .friends
        case .friends: updated.visibility = .private
        case .private: updated.visibility = .public
        }
        DataManager.shared.update(updated)
        entry = updated
        onEntryUpdated?()
    }

    func setVisibility(_ visibility: EntryVisibility) {
        var updated = entry
        updated.visibility = visibility
        DataManager.shared.update(updated)
        entry = updated
        onEntryUpdated?()
    }

    func delete() {
        DataManager.shared.delete(entry)
    }
}
