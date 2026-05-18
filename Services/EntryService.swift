// MARK: – Service
// Handles all Firestore and Firebase Storage operations for FoodEntry.
// Storage path : entries/{userId}/{entryId}.jpg
// Firestore    : entries/{entryId}

import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

final class EntryService {

    static let shared = EntryService()
    private init() {}

    private let db      = Firestore.firestore()
    private let storage = Storage.storage()

    // MARK: – Save (create or update)

    /// Uploads image (if any) then writes the Firestore document.
    /// Calls completion on the main thread.
    func save(_ entry: FoodEntry,
              image: UIImage?,
              isNew: Bool,
              completion: @escaping (Error?) -> Void) {

        guard let uid = Auth.auth().currentUser?.uid else {
            completion(serviceError("Not signed in."))
            return
        }

        if let image {
            uploadImage(image, entryId: entry.id.uuidString, userId: uid) { [weak self] result in
                switch result {
                case .success(let url):
                    self?.writeDocument(entry: entry, uid: uid,
                                        imageURLs: [url.absoluteString],
                                        isNew: isNew, completion: completion)
                case .failure(let error):
                    DispatchQueue.main.async { completion(error) }
                }
            }
        } else {
            writeDocument(entry: entry, uid: uid,
                          imageURLs: [],
                          isNew: isNew, completion: completion)
        }
    }

    // MARK: – Fetch (current user's entries)

    /// Fetches all entries belonging to the signed-in user, sorted newest first.
    func fetchEntries(for uid: String,
                      completion: @escaping (Result<[FoodEntry], Error>) -> Void) {
        db.collection("entries")
            .whereField("userId", isEqualTo: uid)
            .getDocuments { snapshot, error in
                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                let entries = (snapshot?.documents ?? [])
                    .compactMap { FoodEntry(firestoreDocument: $0.data()) }
                    .sorted { $0.checkInDate > $1.checkInDate }
                DispatchQueue.main.async { completion(.success(entries)) }
            }
    }

    // MARK: – Delete

    func delete(entryId: String, completion: ((Error?) -> Void)? = nil) {
        db.collection("entries").document(entryId).delete { error in
            DispatchQueue.main.async { completion?(error) }
        }
    }

    // MARK: – Private: image upload

    private func uploadImage(_ image: UIImage,
                             entryId: String,
                             userId: String,
                             completion: @escaping (Result<URL, Error>) -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(serviceError("Could not compress image.")))
            return
        }

        let ref = storage.reference().child("entries/\(userId)/\(entryId).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        ref.putData(data, metadata: meta) { _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            ref.downloadURL { url, error in
                DispatchQueue.main.async {
                    if let error { completion(.failure(error)) }
                    else if let url { completion(.success(url)) }
                }
            }
        }
    }

    // MARK: – Private: Firestore write

    private func writeDocument(entry: FoodEntry,
                               uid: String,
                               imageURLs: [String],
                               isNew: Bool,
                               completion: @escaping (Error?) -> Void) {
        var doc = entry.firestoreDocument(userId: uid, imageURLs: imageURLs)

        // createdAt is written only once — preserved via setData(merge:) on updates
        if isNew {
            doc["createdAt"] = FieldValue.serverTimestamp()
        }

        db.collection("entries")
            .document(entry.id.uuidString)
            .setData(doc, merge: !isNew) { error in
                DispatchQueue.main.async { completion(error) }
            }
    }

    // MARK: – Helpers

    private func serviceError(_ message: String) -> NSError {
        NSError(domain: "EntryService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: – Firestore document → FoodEntry

fileprivate extension FoodEntry {
    /// Failable init that maps a raw Firestore document dictionary to a FoodEntry.
    /// Returns nil if any required field is missing or has an unexpected type.
    init?(firestoreDocument doc: [String: Any]) {
        guard
            let idString   = doc["id"]        as? String,
            let id         = UUID(uuidString: idString),
            let placeName  = doc["placeName"] as? String,
            let catRaw     = doc["category"]  as? String,
            let category   = FoodCategory(rawValue: catRaw),
            let rating     = doc["rating"]    as? Double,
            let visRaw     = doc["visibility"] as? String,
            let visibility = EntryVisibility(rawValue: visRaw)
        else { return nil }

        self.id          = id
        self.placeName   = placeName
        self.category    = category
        self.rating      = rating
        self.comment     = doc["comment"]   as? String ?? ""
        self.visibility  = visibility
        self.latitude    = doc["latitude"]  as? Double
        self.longitude   = doc["longitude"] as? Double
        self.checkInDate = (doc["checkInDate"] as? Timestamp)?.dateValue() ?? Date()
        self.imagePath   = nil   // no local path for cloud-fetched entries
        self.imageURL    = (doc["imageURLs"] as? [String])?.first  // first Storage download URL
    }
}

// MARK: – FoodEntry → Firestore document

private extension FoodEntry {
    /// Builds the Firestore dictionary. imageURLs is passed in separately
    /// because Storage upload happens before this call.
    func firestoreDocument(userId: String, imageURLs: [String]) -> [String: Any] {
        var doc: [String: Any] = [
            "id":          id.uuidString,
            "userId":      userId,
            "placeName":   placeName,
            "category":    category.rawValue,
            "rating":      rating,
            "comment":     comment,
            "visibility":  visibility.rawValue,
            "checkInDate": Timestamp(date: checkInDate),
            "updatedAt":   FieldValue.serverTimestamp(),
            "imageURLs":   imageURLs
        ]
        if let lat = latitude  { doc["latitude"]  = lat }
        if let lon = longitude { doc["longitude"] = lon }
        return doc
    }
}
