// MARK: – MVVM | Model
// Pure data — no business logic, no UI.

import Foundation
import CoreLocation

// MARK: – Visibility

enum EntryVisibility: String, Codable, CaseIterable {
    case `private` = "private"
    case friends   = "friends"   // displayed as "Share" in UI
    case `public`  = "public"

    /// Human-readable label with icon, used in badges and detail views.
    var label: String {
        switch self {
        case .private: return "🔒 Private"
        case .friends: return "👥 Share"
        case .public:  return "🌍 Public"
        }
    }

    /// Maps to/from the 3-segment control index (0=Private, 1=Share, 2=Public).
    var segmentIndex: Int {
        switch self {
        case .private: return 0
        case .friends: return 1
        case .public:  return 2
        }
    }

    static func from(segmentIndex index: Int) -> EntryVisibility {
        switch index {
        case 0:  return .private
        case 1:  return .friends
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

// MARK: – Entry

struct FoodEntry: Codable, Identifiable {
    var id:          UUID
    var placeName:   String
    var category:    FoodCategory
    var rating:      Double              // 1.0 – 5.0, half-star precision
    var comment:     String
    var visibility:  EntryVisibility
    var latitude:    Double?
    var longitude:   Double?
    var checkInDate: Date                // when the user visited / logged
    var imagePath:   String?            // filename saved in Documents/

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(
        id:          UUID            = UUID(),
        placeName:   String,
        category:    FoodCategory,
        rating:      Double,
        comment:     String          = "",
        visibility:  EntryVisibility = .public,
        latitude:    Double?         = nil,
        longitude:   Double?         = nil,
        checkInDate: Date            = Date(),
        imagePath:   String?         = nil
    ) {
        self.id          = id
        self.placeName   = placeName
        self.category    = category
        self.rating      = rating
        self.comment     = comment
        self.visibility  = visibility
        self.latitude    = latitude
        self.longitude   = longitude
        self.checkInDate = checkInDate
        self.imagePath   = imagePath
    }
}
