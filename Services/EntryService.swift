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

    /// Uploads all images then writes the Firestore document.
    /// Calls completion on the main thread.
    func save(_ entry: FoodEntry,
              images: [UIImage],
              oldImageURLs: [String] = [],
              isNew: Bool,
              completion: @escaping (Error?) -> Void) {

        guard let uid = Auth.auth().currentUser?.uid else {
            completion(serviceError("Not signed in."))
            return
        }

        guard !images.isEmpty else {
            // No new images — preserve existing Firebase URLs so they aren't wiped on edit
            writeDocument(entry: entry, uid: uid, imageURLs: entry.imageURLs, isNew: isNew, completion: completion)
            return
        }

        // Delete old Storage files before uploading replacements
        deleteStorageFiles(urls: oldImageURLs)

        uploadImages(images, entryId: entry.id.uuidString, userId: uid) { [weak self] result in
            switch result {
            case .success(let urls):
                self?.writeDocument(entry: entry, uid: uid,
                                    imageURLs: urls.map { $0.absoluteString },
                                    isNew: isNew, completion: completion)
            case .failure(let error):
                DispatchQueue.main.async { completion(error) }
            }
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

    func delete(entry: FoodEntry, completion: ((Error?) -> Void)? = nil) {
        deleteStorageFiles(urls: entry.imageURLs)
        db.collection("entries").document(entry.id.uuidString).delete { error in
            DispatchQueue.main.async { completion?(error) }
        }
    }

    private func deleteStorageFiles(urls: [String]) {
        for urlString in urls {
            guard !urlString.isEmpty else { continue }
            storage.reference(forURL: urlString).delete(completion: nil)
        }
    }

    // MARK: – Private: image upload

    /// Uploads all images sequentially, collecting download URLs. Fails fast on first error.
    private func uploadImages(_ images: [UIImage],
                              entryId: String,
                              userId: String,
                              completion: @escaping (Result<[URL], Error>) -> Void) {
        var urls: [URL] = []
        func uploadNext(index: Int) {
            guard index < images.count else {
                completion(.success(urls))
                return
            }
            uploadSingleImage(images[index], index: index, entryId: entryId, userId: userId) { result in
                switch result {
                case .success(let url):
                    urls.append(url)
                    uploadNext(index: index + 1)
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
        uploadNext(index: 0)
    }

    private func uploadSingleImage(_ image: UIImage,
                                   index: Int,
                                   entryId: String,
                                   userId: String,
                                   completion: @escaping (Result<URL, Error>) -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(serviceError("Could not compress image \(index).")))
            return
        }

        let ref = storage.reference().child("entries/\(userId)/\(entryId)_\(index).jpg")
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
        self.imagePaths  = []
        self.imageURLs   = doc["imageURLs"] as? [String] ?? []
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
