// MARK: – Model
// Represents a user document stored in Firestore under users/{uid}.
// Constructed either from a Firebase User (at sign-up) or from a Firestore snapshot.

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct UserProfile {

    // MARK: – Fields

    let uid:            String
    let email:          String
    var displayName:    String      // editable later from Settings
    let createdAt:      Date        // first sign-up timestamp
    var lastSignInAt:   Date        // updated on every sign-in
    let authProvider:   String      // "email" | "phone" | "apple"
    let appVersion:     String      // app version at sign-up time
    let platform:       String      // "iOS" — useful if Android is added later
    let locale:         String      // device locale (e.g. "en_US")
    var isEmailVerified: Bool
    var fcmToken:       String?     // populated later when FCM is wired up

    // MARK: – Init from Firebase User (sign-up)

    init(user: User, provider: String) {
        self.uid          = user.uid
        self.email        = user.email ?? ""
        self.displayName  = UserProfile.nameFromEmail(user.email)
        self.createdAt    = Date()
        self.lastSignInAt = Date()
        self.authProvider = provider
        self.appVersion   = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.platform     = "iOS"
        self.locale       = Locale.current.identifier
        self.isEmailVerified = user.isEmailVerified
        self.fcmToken     = nil
    }

    // MARK: – Init from Firestore document

    init?(document: [String: Any]) {
        guard
            let uid   = document["uid"]   as? String,
            let email = document["email"] as? String
        else { return nil }

        self.uid            = uid
        self.email          = email
        self.displayName    = document["displayName"]  as? String ?? UserProfile.nameFromEmail(email)
        self.createdAt      = (document["createdAt"]   as? Timestamp)?.dateValue() ?? Date()
        self.lastSignInAt   = (document["lastSignInAt"] as? Timestamp)?.dateValue() ?? Date()
        self.authProvider   = document["authProvider"] as? String ?? "email"
        self.appVersion     = document["appVersion"]   as? String ?? ""
        self.platform       = document["platform"]     as? String ?? "iOS"
        self.locale         = document["locale"]       as? String ?? ""
        self.isEmailVerified = document["isEmailVerified"] as? Bool ?? false
        self.fcmToken       = document["fcmToken"]     as? String
    }

    // MARK: – Firestore serialisation

    var asDocument: [String: Any] {
        var doc: [String: Any] = [
            "uid":              uid,
            "email":            email,
            "displayName":      displayName,
            "createdAt":        Timestamp(date: createdAt),
            "lastSignInAt":     Timestamp(date: lastSignInAt),
            "authProvider":     authProvider,
            "appVersion":       appVersion,
            "platform":         platform,
            "locale":           locale,
            "isEmailVerified":  isEmailVerified
        ]
        if let token = fcmToken { doc["fcmToken"] = token }
        return doc
    }

    // MARK: – Helpers

    /// Derives a friendly name from an email address: "john.doe@mail.com" → "john.doe"
    static func nameFromEmail(_ email: String?) -> String {
        guard let email else { return "" }
        return String(email.split(separator: "@").first ?? "")
    }

    /// Formatted "Member since" string, e.g. "May 2026"
    var memberSinceText: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: createdAt)
    }
}
