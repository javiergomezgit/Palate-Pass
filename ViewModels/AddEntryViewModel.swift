import UIKit
import CoreLocation

// MARK: – MVVM | ViewModel
// Owns all form state and business logic for creating or editing a FoodEntry.
// Saves locally first, then uploads to Firestore + Storage via EntryService.

final class AddEntryViewModel {

    // MARK: – Form state (View writes these)

    var placeName:     String          = ""
    var category:      FoodCategory    = .food
    var rating:        Double          = 0
    var comment:       String          = ""
    var visibility:    EntryVisibility = AddEntryViewModel.defaultVisibility
    var checkInDate:   Date            = Date()
    var location:      CLLocationCoordinate2D?
    var selectedImage: UIImage?

    // MARK: – Output callbacks

    var onSaveSuccess:     (() -> Void)?
    var onValidationError: ((String) -> Void)?
    /// Fires just before the async upload starts — use it to show a spinner.
    var onSaving:          (() -> Void)?
    /// Fires if the cloud upload fails. Entry is already saved locally.
    var onSaveError:       ((String) -> Void)?

    // MARK: – Read-only context

    var isEditing: Bool { editingEntry != nil }

    var initialImage: UIImage? {
        guard let path = editingEntry?.imagePath else { return nil }
        return DataManager.shared.loadImage(named: path)
    }

    // MARK: – Private

    private let editingEntry: FoodEntry?

    private static var defaultVisibility: EntryVisibility {
        let obj = UserDefaults.standard.object(forKey: "defaultPublic")
        guard let obj else { return .public }
        return UserDefaults.standard.bool(forKey: "defaultPublic") ? .public : .private
    }

    // MARK: – Init

    init(editing entry: FoodEntry? = nil) {
        editingEntry = entry
        guard let e = entry else { return }
        placeName   = e.placeName
        category    = e.category
        rating      = e.rating
        comment     = e.comment
        visibility  = e.visibility
        checkInDate = e.checkInDate
        if let lat = e.latitude, let lon = e.longitude {
            location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    // MARK: – Save

    func save() {
        // 1. Validate
        guard !placeName.trimmingCharacters(in: .whitespaces).isEmpty else {
            onValidationError?("Place name is required.")
            return
        }
        guard rating > 0 else {
            onValidationError?("Please tap at least one star.")
            return
        }

        // 2. Persist image locally so it's available offline
        var localImagePath = editingEntry?.imagePath
        if let img = selectedImage {
            localImagePath = DataManager.shared.saveImage(img)
        }

        let isNew = editingEntry == nil
        let entry = FoodEntry(
            id:          editingEntry?.id ?? UUID(),
            placeName:   placeName,
            category:    category,
            rating:      rating,
            comment:     comment,
            visibility:  visibility,
            latitude:    location?.latitude,
            longitude:   location?.longitude,
            checkInDate: checkInDate,
            imagePath:   localImagePath
        )

        // 3. Save to local store immediately (fast, offline-safe)
        if isNew {
            DataManager.shared.add(entry)
        } else {
            DataManager.shared.update(entry)
        }

        // 4. Signal the View to show a loading state
        onSaving?()

        // 5. Upload to Firebase (image → Storage, doc → Firestore)
        EntryService.shared.save(entry, image: selectedImage, isNew: isNew) { [weak self] error in
            if let error {
                // Entry is safe locally — inform the View but don't block navigation
                self?.onSaveError?("Saved locally. Cloud sync failed: \(error.localizedDescription)")
            } else {
                self?.onSaveSuccess?()
            }
        }
    }
}
