// MARK: – MVVM | Model
// Pure data — no business logic, no UI. Describes a single tracked food/drink/coffee item.

import Foundation
import CoreLocation

enum FoodCategory: String, Codable, CaseIterable {
    case food = "Food"
    case coffee = "Coffee"
    case drink = "Drink"
    case dessert = "Dessert"
    case snack = "Snack"
    case other = "Other"

    var emoji: String {
        switch self {
        case .food: return "🍽️"
        case .coffee: return "☕"
        case .drink: return "🍹"
        case .dessert: return "🍰"
        case .snack: return "🍿"
        case .other: return "📍"
        }
    }
}

struct FoodEntry: Codable, Identifiable {
    var id: UUID
    var name: String
    var placeName: String
    var category: FoodCategory
    var rating: Double          // 1.0 – 5.0, supports half stars
    var comment: String
    var isPublic: Bool
    var latitude: Double?
    var longitude: Double?
    var date: Date
    var imagePath: String?      // filename saved in Documents/

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(
        id: UUID = UUID(),
        name: String,
        placeName: String,
        category: FoodCategory,
        rating: Double,
        comment: String = "",
        isPublic: Bool = true,
        latitude: Double? = nil,
        longitude: Double? = nil,
        date: Date = Date(),
        imagePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.placeName = placeName
        self.category = category
        self.rating = rating
        self.comment = comment
        self.isPublic = isPublic
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.imagePath = imagePath
    }
}
