// MARK: – Service
// Single point of contact for all Firestore operations on the users collection.
// Controllers and ViewModels call this — nothing touches Firestore directly elsewhere.

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class UserService {

    static let shared = UserService()
    private init() {}

    private let db = Firestore.firestore()
    private var usersCollection: CollectionReference { db.collection("users") }

    // MARK: – Create (sign-up)

    /// Writes a new user document the first time someone signs up.
    /// Uses `setData(merge: false)` so it doesn't overwrite an existing document.
    func createProfile(for user: User,
                       provider: String,
                       completion: ((Error?) -> Void)? = nil) {
        let profile = UserProfile(user: user, provider: provider)
        usersCollection.document(user.uid).setData(profile.asDocument) { error in
            completion?(error)
        }
    }

    // MARK: – Read (fetch)

    /// Fetches the user document. Returns nil if it doesn't exist yet.
    func fetchProfile(uid: String,
                      completion: @escaping (UserProfile?) -> Void) {
        usersCollection.document(uid).getDocument { snapshot, error in
            guard
                error == nil,
                let data = snapshot?.data()
            else {
                completion(nil)
                return
            }
            completion(UserProfile(document: data))
        }
    }

    // MARK: – Update helpers

    /// Called on every sign-in so we always have a fresh timestamp.
    func updateLastSignIn(uid: String) {
        usersCollection.document(uid).updateData([
            "lastSignInAt":   Timestamp(date: Date()),
            "isEmailVerified": Auth.auth().currentUser?.isEmailVerified ?? false
        ])
    }

    /// Called when the user edits their display name in Settings.
    func updateDisplayName(_ name: String,
                           uid: String,
                           completion: ((Error?) -> Void)? = nil) {
        usersCollection.document(uid).updateData(["displayName": name]) { error in
            completion?(error)
        }
    }

    /// Stored now, used later when FCM is wired up.
    func updateFCMToken(_ token: String, uid: String) {
        usersCollection.document(uid).updateData(["fcmToken": token])
    }
}
