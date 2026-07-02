// MARK: – MVVM | Models
// Pure data — no business logic, no UI.

import Foundation
import CoreLocation

// MARK: – Visibility

enum Visibility: String, Codable, CaseIterable {
    case `private` = "private"
    case shared    = "shared"
    case `public`  = "public"

    var label: String {
        switch self {
        case .private: return "🔒 Private"
        case .shared:  return "👥 Share"
        case .public:  return "🌍 Public"
        }
    }

    var segmentIndex: Int {
        switch self {
        case .private: return 0
        case .shared:  return 1
        case .public:  return 2
        }
    }

    static func from(segmentIndex index: Int) -> Visibility {
        switch index {
        case 0:  return .private
        case 1:  return .shared
        default: return .public
        }
    }
}

// MARK: – Category

enum FoodCategory: String, Codable, CaseIterable {
    case food          = "Food"
    case coffee        = "Coffee"
    case drink         = "Drink"
    case dessert       = "Dessert"
    case entertainment = "Entertainment"
    case other         = "Other"

    var emoji: String {
        switch self {
        case .food:          return "🍽️"
        case .coffee:        return "☕"
        case .drink:         return "🍹"
        case .dessert:       return "🍰"
        case .entertainment: return "🎭"
        case .other:         return "📍"
        }
    }
}

// MARK: – Place (public, no userId)

struct Place: Codable, Identifiable {
    var id:              String         // placeID
    var name:            String
    var category:        String         // FoodCategory.rawValue
    var latitude:        Double
    var longitude:       Double
    var rating:          Double         // rolling avg across all checkins
    var checkinCount:    Int
    var publicImageURLs: [String]
    var claimedBusiness: Bool
    var phone:           String?
    var website:         String?
    var updatedAt:       Date

    var foodCategory: FoodCategory { FoodCategory(rawValue: category) ?? .food }

    var coordinate: CLLocationCoordinate2D? {
        guard latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: – Checkin (private, under users/{uid}/checkins/{placeID})

struct Checkin: Codable, Identifiable {
    var id:              String         // placeID — matches the document ID
    var placeRef:        String         // same as id
    var personalRating:  Double
    var personalComment: String
    var imageURLs:       [String]       // Firebase Storage download URLs
    var imagePaths:      [String]       // local Documents/ filenames — NOT written to Firestore
    var checkedInAt:     Date
    var visibility:      Visibility
    var sharedWith:      [String]       // UIDs, empty by default
}

// MARK: – PlaceCheckin (composite — used throughout ViewModels and Views)

struct PlaceCheckin: Codable {
    var place:   Place
    var checkin: Checkin

    /// Convenience: coordinate from the place.
    var coordinate: CLLocationCoordinate2D? { place.coordinate }
}
