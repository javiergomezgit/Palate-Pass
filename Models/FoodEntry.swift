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

struct FoodEntry: Identifiable {
    var id:          UUID
    var placeName:   String
    var category:    FoodCategory
    var rating:      Double              // 1.0 – 5.0, half-star precision
    var comment:     String
    var visibility:  EntryVisibility
    var latitude:    Double?
    var longitude:   Double?
    var checkInDate: Date
    var imagePaths:  [String]           // filenames saved in Documents/ (local)
    var imageURLs:   [String]           // Firebase Storage download URLs (cloud)

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
        imagePaths:  [String]        = [],
        imageURLs:   [String]        = []
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
        self.imagePaths  = imagePaths
        self.imageURLs   = imageURLs
    }
}

// MARK: – Codable (with migration from legacy single-image fields)

extension FoodEntry: Codable {

    enum CodingKeys: String, CodingKey {
        case id, placeName, category, rating, comment, visibility
        case latitude, longitude, checkInDate
        case imagePaths, imageURLs
        case imagePath, imageURL        // legacy — read only, never written
    }

    init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,          forKey: .id)
        placeName    = try c.decode(String.self,        forKey: .placeName)
        category     = try c.decode(FoodCategory.self,  forKey: .category)
        rating       = try c.decode(Double.self,        forKey: .rating)
        comment      = (try? c.decode(String.self,      forKey: .comment))  ?? ""
        visibility   = try c.decode(EntryVisibility.self, forKey: .visibility)
        latitude     = try? c.decode(Double.self,       forKey: .latitude)
        longitude    = try? c.decode(Double.self,       forKey: .longitude)
        checkInDate  = (try? c.decode(Date.self,        forKey: .checkInDate)) ?? Date()

        // Prefer new array fields; fall back to legacy single-value fields
        if let paths = try? c.decode([String].self, forKey: .imagePaths) {
            imagePaths = paths
        } else if let path = try? c.decode(String.self, forKey: .imagePath) {
            imagePaths = [path]
        } else {
            imagePaths = []
        }

        if let urls = try? c.decode([String].self, forKey: .imageURLs) {
            imageURLs = urls
        } else if let url = try? c.decode(String.self, forKey: .imageURL) {
            imageURLs = [url]
        } else {
            imageURLs = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,          forKey: .id)
        try c.encode(placeName,   forKey: .placeName)
        try c.encode(category,    forKey: .category)
        try c.encode(rating,      forKey: .rating)
        try c.encode(comment,     forKey: .comment)
        try c.encode(visibility,  forKey: .visibility)
        try c.encodeIfPresent(latitude,    forKey: .latitude)
        try c.encodeIfPresent(longitude,   forKey: .longitude)
        try c.encode(checkInDate, forKey: .checkInDate)
        try c.encode(imagePaths,  forKey: .imagePaths)
        try c.encode(imageURLs,   forKey: .imageURLs)
    }
}
