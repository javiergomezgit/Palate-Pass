import UIKit
import CoreLocation
import FirebaseAuth

// MARK: – MVVM | ViewModel
// Wraps a single PlaceCheckin and exposes formatted display values and mutating actions.

final class EntryDetailViewModel {

    // MARK: – Output

    var onEntryUpdated: (() -> Void)?

    // MARK: – Formatted display values

    var placeName:       String     { placeCheckin.place.name.isEmpty ? "Unknown place" : placeCheckin.place.name }
    var categoryBadge:   String     { "\(placeCheckin.place.foodCategory.emoji) \(placeCheckin.place.category)" }
    var rating:          Double     { placeCheckin.checkin.personalRating }
    var formattedRating: String     { String(format: "%.1f / 5.0", placeCheckin.checkin.personalRating) }
    var comment:         String     { placeCheckin.checkin.personalComment }
    var hasComment:      Bool       { !placeCheckin.checkin.personalComment.isEmpty }
    var visibility:      Visibility { placeCheckin.checkin.visibility }
    var visibilityText:  String     { placeCheckin.checkin.visibility.label }
    var category:        FoodCategory { placeCheckin.place.foodCategory }

    var coordinate: (latitude: Double, longitude: Double)? {
        guard let c = placeCheckin.place.coordinate else { return nil }
        return (c.latitude, c.longitude)
    }

    var localPhotos: [UIImage] {
        placeCheckin.checkin.imagePaths.compactMap { DataManager.shared.loadImage(named: $0) }
    }

    var remoteImageURLs: [String] { placeCheckin.checkin.imageURLs }

    var hasImage: Bool {
        !placeCheckin.checkin.imagePaths.isEmpty || !placeCheckin.checkin.imageURLs.isEmpty
    }

    var totalImageCount: Int {
        max(placeCheckin.checkin.imagePaths.count, placeCheckin.checkin.imageURLs.count)
    }

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .short
        return fmt.string(from: placeCheckin.checkin.checkedInAt)
    }

    var editViewModel: AddEntryViewModel { AddEntryViewModel(editing: placeCheckin) }

    // MARK: – Private

    private(set) var placeCheckin: PlaceCheckin

    // MARK: – Init

    init(placeCheckin: PlaceCheckin) {
        self.placeCheckin = placeCheckin
    }

    // MARK: – Input

    /// Cycles visibility: public → shared → private → public
    func cycleVisibility() {
        let next: Visibility
        switch placeCheckin.checkin.visibility {
        case .public:  next = .shared
        case .shared:  next = .private
        case .private: next = .public
        }
        applyVisibility(next)
    }

    func setVisibility(_ visibility: Visibility) {
        applyVisibility(visibility)
    }

    func delete() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        DataManager.shared.delete(placeCheckin)
        EntryService.shared.delete(pc: placeCheckin, uid: uid)
    }

    // MARK: – Private

    private func applyVisibility(_ newVisibility: Visibility) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var updated = placeCheckin
        updated.checkin.visibility = newVisibility
        DataManager.shared.update(updated)
        placeCheckin = updated
        onEntryUpdated?()
        EntryService.shared.changeVisibility(placeCheckin, to: newVisibility, uid: uid)
    }
}
