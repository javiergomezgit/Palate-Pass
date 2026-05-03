// MARK: – MVVM | View (Shared Styling)
// Single source of truth for colors, corner radii, and shadows across the whole app.

import UIKit

enum Theme {

    // MARK: – Palette

    static let accent      = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 1) // vivid blue
    static let accentDeep  = UIColor(red: 0.10, green: 0.28, blue: 0.80, alpha: 1) // deeper blue
    static let accentLight = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 0.12)
    static let accentMid   = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 0.25)

    // MARK: – Cards

    static let cardRadius: CGFloat = 16

    static func applyCardStyle(to view: UIView) {
        view.backgroundColor    = .systemBackground
        view.layer.cornerRadius = cardRadius
        view.layer.shadowColor  = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 0.18).cgColor
        view.layer.shadowOpacity = 1
        view.layer.shadowRadius  = 10
        view.layer.shadowOffset  = CGSize(width: 0, height: 3)
        view.layer.masksToBounds = false
    }

    // MARK: – Category colours

    static func categoryColor(_ cat: FoodCategory) -> UIColor {
        switch cat {
        case .food:    return UIColor(red: 1.00, green: 0.45, blue: 0.20, alpha: 1)
        case .coffee:  return UIColor(red: 0.55, green: 0.33, blue: 0.18, alpha: 1)
        case .drink:   return UIColor(red: 0.18, green: 0.48, blue: 0.95, alpha: 1)
        case .dessert: return UIColor(red: 0.92, green: 0.25, blue: 0.52, alpha: 1)
        case .snack:   return UIColor(red: 0.18, green: 0.72, blue: 0.52, alpha: 1)
        case .other:   return UIColor(red: 0.44, green: 0.34, blue: 0.86, alpha: 1)
        }
    }
}
