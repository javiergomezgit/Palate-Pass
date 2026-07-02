import UIKit
import CoreLocation
import FirebaseAuth

// MARK: – MVVM | ViewModel
// Owns all form state and business logic for creating or editing a PlaceCheckin.
// Saves locally first, then uploads to Firestore + Storage via EntryService.

final class AddEntryViewModel {

    // MARK: – Form state (View writes these)

    var placeName:      String     = ""
    var category:       FoodCategory = .food
    var rating:         Double     = 0
    var comment:        String     = ""
    var visibility:     Visibility = AddEntryViewModel.defaultVisibility
    var checkInDate:    Date       = Date()
    var location:       CLLocationCoordinate2D?
    var selectedImages: [UIImage]  = []
    /// Set to true only when the user explicitly adds or removes a photo.
    var imagesModified: Bool = false
    /// True when the place was selected from a real-business source (MKLocalSearch / map pin).
    var placeIsClaimed: Bool = false

    static let maxPhotos = 5

    // MARK: – Output callbacks

    var onSaveSuccess:     (() -> Void)?
    var onValidationError: ((String) -> Void)?
    /// Fires just before the async upload starts — use it to show a spinner.
    var onSaving:          (() -> Void)?
    /// Fires if the cloud upload fails. Entry is already saved locally.
    var onSaveError:       ((String) -> Void)?

    // MARK: – Read-only context

    var isEditing: Bool { editingPlaceCheckin != nil }

    var initialImages: [UIImage] {
        guard let pc = editingPlaceCheckin else { return [] }
        return pc.checkin.imagePaths.compactMap { DataManager.shared.loadImage(named: $0) }
    }

    /// Remote URLs to download when editing a cloud-fetched entry (no local paths available).
    var initialImageURLs: [String] {
        guard let pc = editingPlaceCheckin, pc.checkin.imagePaths.isEmpty else { return [] }
        return pc.checkin.imageURLs
    }

    // MARK: – Private

    private let editingPlaceCheckin: PlaceCheckin?

    private static var defaultVisibility: Visibility {
        let obj = UserDefaults.standard.object(forKey: "defaultPublic")
        guard obj != nil else { return .public }
        return UserDefaults.standard.bool(forKey: "defaultPublic") ? .public : .private
    }

    // MARK: – Init

    init(editing pc: PlaceCheckin? = nil) {
        editingPlaceCheckin = pc
        guard let pc else { return }
        placeName      = pc.place.name
        category       = pc.place.foodCategory
        rating         = pc.checkin.personalRating
        comment        = pc.checkin.personalComment
        visibility     = pc.checkin.visibility
        checkInDate    = pc.checkin.checkedInAt
        placeIsClaimed = pc.place.claimedBusiness
        if let coord = pc.place.coordinate {
            location = coord
        }
    }

    // MARK: – Save

    func save() {
        guard !placeName.trimmingCharacters(in: .whitespaces).isEmpty else {
            onValidationError?("Place name is required.")
            return
        }
        guard rating > 0 else {
            onValidationError?("Please tap at least one star.")
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            onValidationError?("Not signed in.")
            return
        }

        let imagesChanged = imagesModified
        var localImagePaths: [String]
        if imagesChanged {
            localImagePaths = selectedImages.compactMap { DataManager.shared.saveImage($0) }
        } else {
            localImagePaths = editingPlaceCheckin?.checkin.imagePaths ?? []
        }

        let isNew   = editingPlaceCheckin == nil
        let placeID = editingPlaceCheckin?.place.id ?? UUID().uuidString

        let place = Place(
            id:              placeID,
            name:            placeName,
            category:        category.rawValue,
            latitude:        location?.latitude  ?? 0,
            longitude:       location?.longitude ?? 0,
            rating:          rating,
            checkinCount:    editingPlaceCheckin?.place.checkinCount    ?? 1,
            publicImageURLs: editingPlaceCheckin?.place.publicImageURLs ?? [],
            claimedBusiness: placeIsClaimed,
            phone:           editingPlaceCheckin?.place.phone,
            website:         editingPlaceCheckin?.place.website,
            updatedAt:       Date()
        )

        let checkin = Checkin(
            id:              placeID,
            placeRef:        placeID,
            personalRating:  rating,
            personalComment: comment,
            imageURLs:       imagesChanged ? [] : (editingPlaceCheckin?.checkin.imageURLs ?? []),
            imagePaths:      localImagePaths,
            checkedInAt:     checkInDate,
            visibility:      visibility,
            sharedWith:      editingPlaceCheckin?.checkin.sharedWith ?? []
        )

        let pc = PlaceCheckin(place: place, checkin: checkin)

        if isNew {
            DataManager.shared.add(pc)
        } else {
            DataManager.shared.update(pc)
        }

        onSaving?()

        let oldURLs = imagesChanged ? (editingPlaceCheckin?.checkin.imageURLs ?? []) : []

        print("💾 save path: isNew=\(isNew), name=\(placeName), claimed=\(placeIsClaimed)")
        if isNew {
            EntryService.shared.create(pc, images: selectedImages, uid: uid) { [weak self] error in
                if let error {
                    self?.onSaveError?("Saved locally. Cloud sync failed: \(error.localizedDescription)")
                } else {
                    self?.onSaveSuccess?()
                }
            }
        } else {
            guard let oldCheckin = editingPlaceCheckin?.checkin else { return }
            EntryService.shared.update(pc, oldCheckin: oldCheckin, images: selectedImages,
                                       oldImageURLs: oldURLs, uid: uid) { [weak self] error in
                if let error {
                    self?.onSaveError?("Saved locally. Cloud sync failed: \(error.localizedDescription)")
                } else {
                    self?.onSaveSuccess?()
                }
            }
        }
    }
}
