import UIKit
import CoreLocation

// MARK: – MVVM | ViewModel
// Owns all form state and business logic for creating or editing a FoodEntry.
// Validates input, drives saves through DataManager, and reports outcomes via closures.

final class AddEntryViewModel {

    // MARK: – Form state (View writes these)

    var name: String = ""
    var placeName: String = ""
    var category: FoodCategory = .food
    var rating: Double = 0
    var comment: String = ""
    // Reads the user's default privacy preference from Settings; falls back to public
    var isPublic: Bool = UserDefaults.standard.object(forKey: "defaultPublic") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "defaultPublic")
    var location: CLLocationCoordinate2D?
    var selectedImage: UIImage?

    // MARK: – Output (View binds to these)

    var onSaveSuccess: (() -> Void)?
    var onValidationError: ((String) -> Void)?

    // MARK: – Read-only context

    var isEditing: Bool { editingEntry != nil }

    var initialLocationText: String? {
        guard let lat = editingEntry?.latitude, let lon = editingEntry?.longitude else { return nil }
        return String(format: "%.4f, %.4f", lat, lon)
    }

    var initialImage: UIImage? {
        guard let path = editingEntry?.imagePath else { return nil }
        return DataManager.shared.loadImage(named: path)
    }

    // MARK: – Private

    private let editingEntry: FoodEntry?

    // MARK: – Init

    init(editing entry: FoodEntry? = nil) {
        editingEntry = entry
        guard let e = entry else { return }
        name      = e.name
        placeName = e.placeName
        category  = e.category
        rating    = e.rating
        comment   = e.comment
        isPublic  = e.isPublic
        if let lat = e.latitude, let lon = e.longitude {
            location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    // MARK: – Input (View calls this)

    func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            onValidationError?("Item name is required.")
            return
        }
        guard rating > 0 else {
            onValidationError?("Please tap at least one star.")
            return
        }

        var imagePath = editingEntry?.imagePath
        if let img = selectedImage {
            imagePath = DataManager.shared.saveImage(img)
        }

        let entry = FoodEntry(
            id:        editingEntry?.id ?? UUID(),
            name:      name,
            placeName: placeName,
            category:  category,
            rating:    rating,
            comment:   comment,
            isPublic:  isPublic,
            latitude:  location?.latitude,
            longitude: location?.longitude,
            date:      editingEntry?.date ?? Date(),
            imagePath: imagePath
        )

        if editingEntry != nil {
            DataManager.shared.update(entry)
        } else {
            DataManager.shared.add(entry)
        }
        onSaveSuccess?()
    }
}
