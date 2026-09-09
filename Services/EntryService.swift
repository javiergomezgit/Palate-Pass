// MARK: – Service
// Handles all Firestore and Firebase Storage operations.
// Firestore: places/{placeID}  +  users/{uid}/checkins/{placeID}
// Storage:   checkins/{uid}/{placeID}_{index}.jpg

import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

final class EntryService {

    static let shared = EntryService()
    private init() {}

    private let db      = Firestore.firestore()
    private let storage = Storage.storage()

    // MARK: – Fetch

    /// Fetches all of the user's checkins, resolves each place, and returns sorted PlaceCheckins.
    func fetchCheckins(for uid: String,
                       completion: @escaping (Result<[PlaceCheckin], Error>) -> Void) {
        db.collection("users").document(uid).collection("checkins")
            .getDocuments { [weak self] snapshot, error in
                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                let docs = snapshot?.documents ?? []
                guard !docs.isEmpty else {
                    DispatchQueue.main.async { completion(.success([])) }
                    return
                }
                let checkins = docs.compactMap { Checkin(firestoreDocument: $0.data(), id: $0.documentID) }
                let placeIDs = checkins.map { $0.placeRef }
                self?.fetchPlaces(ids: placeIDs) { placesResult in
                    switch placesResult {
                    case .failure(let error):
                        DispatchQueue.main.async { completion(.failure(error)) }
                    case .success(let placesById):
                        let combined = checkins.compactMap { checkin -> PlaceCheckin? in
                            guard let place = placesById[checkin.placeRef] else { return nil }
                            return PlaceCheckin(place: place, checkin: checkin)
                        }.sorted { $0.checkin.checkedInAt > $1.checkin.checkedInAt }
                        DispatchQueue.main.async { completion(.success(combined)) }
                    }
                }
            }
    }

    // MARK: – Create

    /// Uploads images then batch-writes place + checkin atomically.
    func create(_ pc: PlaceCheckin,
                images: [UIImage],
                uid: String,
                completion: @escaping (Error?) -> Void) {
        guard !images.isEmpty else {
            // Keep whatever URLs the entry already knows about: a re-queued entry may
            // have uploaded its photos on an earlier attempt but lost its local copies.
            batchCreate(pc, imageURLs: pc.checkin.imageURLs, uid: uid, completion: completion)
            return
        }
        uploadImages(images, placeID: pc.place.id, userId: uid) { [weak self] result in
            switch result {
            case .failure(let error):
                // Storage has no offline queue, but losing the whole entry because its
                // photos failed is far worse than losing the photos. Write the check-in
                // anyway, then report the error so SyncCoordinator keeps the operation
                // queued and retries the images later.
                self?.batchCreate(pc, imageURLs: [], uid: uid) { writeError in
                    completion(writeError ?? error)
                }
            case .success(let urls):
                var updated = pc
                let urlStrings = urls.map { $0.absoluteString }
                updated.checkin.imageURLs = urlStrings
                if pc.checkin.visibility == .public {
                    updated.place.publicImageURLs = urlStrings
                }
                self?.batchCreate(updated, imageURLs: urlStrings, uid: uid, completion: completion)
            }
        }
    }

    // MARK: – Update

    /// Optionally re-uploads images, then updates checkin + recalculates place rating via transaction.
    func update(_ pc: PlaceCheckin,
                oldCheckin: Checkin,
                images: [UIImage],
                oldImageURLs: [String],
                uid: String,
                completion: @escaping (Error?) -> Void) {
        let imagesChanged = !images.isEmpty
        if imagesChanged {
            deleteStorageFiles(urls: oldImageURLs)
            uploadImages(images, placeID: pc.place.id, userId: uid) { [weak self] result in
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async { completion(error) }
                case .success(let urls):
                    var updated = pc
                    updated.checkin.imageURLs = urls.map { $0.absoluteString }
                    self?.commitUpdate(updated, oldCheckin: oldCheckin, uid: uid, completion: completion)
                }
            }
        } else {
            commitUpdate(pc, oldCheckin: oldCheckin, uid: uid, completion: completion)
        }
    }

    // MARK: – Delete

    /// Deletes the checkin, decrements the place's rating/count, removes Storage files.
    /// Does NOT delete the place document.
    func delete(pc: PlaceCheckin, uid: String, completion: ((Error?) -> Void)? = nil) {
        let placeID = pc.place.id
        let placeRef = db.collection("places").document(placeID)
        let checkinRef = db.collection("users").document(uid).collection("checkins").document(placeID)

        db.runTransaction({ [weak self] transaction, errorPointer in
            guard let self else { return nil }
            let placeSnap: DocumentSnapshot
            do { placeSnap = try transaction.getDocument(placeRef) }
            catch let err as NSError { errorPointer?.pointee = err; return nil }

            let oldAvg   = placeSnap.data()?["rating"]       as? Double ?? 0
            let oldCount = placeSnap.data()?["checkinCount"]  as? Int    ?? 1
            let newCount = max(0, oldCount - 1)

            if newCount == 0 {
                transaction.updateData(["rating": 0, "checkinCount": 0,
                                        "updatedAt": FieldValue.serverTimestamp()], forDocument: placeRef)
            } else {
                let newAvg = ((oldAvg * Double(oldCount)) - pc.checkin.personalRating) / Double(newCount)
                transaction.updateData(["rating": newAvg, "checkinCount": newCount,
                                        "updatedAt": FieldValue.serverTimestamp()], forDocument: placeRef)
            }

            // Remove this user's images from publicImageURLs if they were public
            if pc.checkin.visibility == .public && !pc.checkin.imageURLs.isEmpty {
                transaction.updateData(
                    ["publicImageURLs": FieldValue.arrayRemove(pc.checkin.imageURLs)],
                    forDocument: placeRef
                )
            }

            transaction.deleteDocument(checkinRef)
            return nil
        }) { [weak self] _, error in
            self?.deleteStorageFiles(urls: pc.checkin.imageURLs)
            DispatchQueue.main.async { completion?(error) }
        }
    }

    // MARK: – Private: batch create

    private func batchCreate(_ pc: PlaceCheckin,
                              imageURLs: [String],
                              uid: String,
                              completion: @escaping (Error?) -> Void) {
        print("🔥 batchCreate: name=\(pc.place.name), claimed=\(pc.place.claimedBusiness), uid=\(uid)")
        let placeID    = pc.place.id
        let batch      = db.batch()
        let placeRef   = db.collection("places").document(placeID)
        let checkinRef = db.collection("users").document(uid).collection("checkins").document(placeID)

        var placeDoc = pc.place.firestoreDocument()
        placeDoc["rating"]       = pc.checkin.personalRating
        placeDoc["checkinCount"] = 1
        placeDoc["publicImageURLs"] = pc.checkin.visibility == .public ? imageURLs : []
        placeDoc["createdAt"]    = FieldValue.serverTimestamp()
        batch.setData(placeDoc, forDocument: placeRef)

        // checkedInAt comes from firestoreDocument() — it is the date the user picked,
        // which may be backdated, so it must not be replaced with the server clock.
        var checkinDoc = pc.checkin.firestoreDocument()
        checkinDoc["imageURLs"] = imageURLs
        batch.setData(checkinDoc, forDocument: checkinRef)

        batch.commit { error in
            if let error {
                print("❌ batchCreate failed: \(error.localizedDescription)")
            } else {
                print("✅ batchCreate succeeded")
            }
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: – Private: commit update

    private func commitUpdate(_ pc: PlaceCheckin,
                               oldCheckin: Checkin,
                               uid: String,
                               completion: @escaping (Error?) -> Void) {
        let placeID    = pc.place.id
        let placeRef   = db.collection("places").document(placeID)
        let checkinRef = db.collection("users").document(uid).collection("checkins").document(placeID)
        let imageURLs  = pc.checkin.imageURLs

        // Update checkin doc
        var checkinUpdates = pc.checkin.firestoreDocument()
        checkinUpdates["imageURLs"] = imageURLs

        // Transaction updates place rating + publicImageURLs atomically.
        // Uses setData(merge:true) for the place so it works even if the document
        // was only saved locally (never reached Firestore due to prior rules issues).
        db.runTransaction({ transaction, errorPointer in
            let placeSnap: DocumentSnapshot
            do { placeSnap = try transaction.getDocument(placeRef) }
            catch let err as NSError { errorPointer?.pointee = err; return nil }

            let oldAvg   = placeSnap.data()?["rating"]      as? Double ?? 0
            let count    = placeSnap.data()?["checkinCount"] as? Int    ?? 1

            // Preserve the existing claimedBusiness from Firestore when the doc already exists.
            // Editing visibility/rating/comment must never downgrade a claimed business.
            // Only fall back to the local value when creating the doc for the first time.
            let claimedBusiness: Bool = placeSnap.exists
                ? (placeSnap.data()?["claimedBusiness"] as? Bool ?? pc.place.claimedBusiness)
                : pc.place.claimedBusiness

            var placeUpdates: [String: Any] = [
                "name":            pc.place.name,
                "category":        pc.place.category,
                "latitude":        pc.place.latitude,
                "longitude":       pc.place.longitude,
                "claimedBusiness": claimedBusiness,
                "updatedAt":       FieldValue.serverTimestamp()
            ]

            if pc.checkin.personalRating != oldCheckin.personalRating {
                let newAvg = ((oldAvg * Double(count)) - oldCheckin.personalRating + pc.checkin.personalRating) / Double(count)
                placeUpdates["rating"] = newAvg
            }

            // publicImageURLs: handle visibility transitions
            let oldVis = oldCheckin.visibility
            let newVis = pc.checkin.visibility
            if oldVis != newVis && !imageURLs.isEmpty {
                if newVis == .public {
                    placeUpdates["publicImageURLs"] = FieldValue.arrayUnion(imageURLs)
                } else if oldVis == .public {
                    placeUpdates["publicImageURLs"] = FieldValue.arrayRemove(imageURLs)
                }
            }

            // setData(merge:true) creates the document if it doesn't exist yet
            transaction.setData(placeUpdates, forDocument: placeRef, merge: true)
            transaction.setData(checkinUpdates, forDocument: checkinRef, merge: true)
            return nil
        }) { _, error in
            if let error {
                print("❌ commitUpdate failed: \(error.localizedDescription)")
            } else {
                print("✅ commitUpdate succeeded")
            }
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: – Private: fetch places by IDs

    private func fetchPlaces(ids: [String],
                             completion: @escaping (Result<[String: Place], Error>) -> Void) {
        guard !ids.isEmpty else { completion(.success([:])); return }
        var result: [String: Place] = [:]
        let group = DispatchGroup()
        var fetchError: Error?

        for id in ids {
            group.enter()
            db.collection("places").document(id).getDocument { snapshot, error in
                defer { group.leave() }
                if let error { fetchError = error; return }
                if let data = snapshot?.data(),
                   let place = Place(firestoreDocument: data, id: id) {
                    result[id] = place
                }
            }
        }
        group.notify(queue: .main) {
            if let error = fetchError { completion(.failure(error)) }
            else { completion(.success(result)) }
        }
    }

    // MARK: – Private: image upload

    private func uploadImages(_ images: [UIImage],
                              placeID: String,
                              userId: String,
                              completion: @escaping (Result<[URL], Error>) -> Void) {
        var urls: [URL] = []
        func uploadNext(index: Int) {
            guard index < images.count else { completion(.success(urls)); return }
            uploadSingleImage(images[index], index: index, placeID: placeID, userId: userId) { result in
                switch result {
                case .success(let url): urls.append(url); uploadNext(index: index + 1)
                case .failure(let error): DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
        uploadNext(index: 0)
    }

    private func uploadSingleImage(_ image: UIImage,
                                   index: Int,
                                   placeID: String,
                                   userId: String,
                                   completion: @escaping (Result<URL, Error>) -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(serviceError("Could not compress image \(index).")))
            return
        }
        let ref = storage.reference().child("checkins/\(userId)/\(placeID)_\(index).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        ref.putData(data, metadata: meta) { _, error in
            if let error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            ref.downloadURL { url, error in
                DispatchQueue.main.async {
                    if let error { completion(.failure(error)) }
                    else if let url { completion(.success(url)) }
                }
            }
        }
    }

    // MARK: – Private: storage cleanup

    func deleteStorageFiles(urls: [String]) {
        for urlString in urls {
            guard !urlString.isEmpty else { continue }
            storage.reference(forURL: urlString).delete(completion: nil)
        }
    }

    private func serviceError(_ message: String) -> NSError {
        NSError(domain: "EntryService", code: 0,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: – Firestore ↔ Place

private extension Place {
    func firestoreDocument() -> [String: Any] {
        var doc: [String: Any] = [
            "name":            name,
            "category":        category,
            "latitude":        latitude,
            "longitude":       longitude,
            "publicImageURLs": publicImageURLs,
            "claimedBusiness": claimedBusiness,
            "updatedAt":       FieldValue.serverTimestamp()
        ]
        if let phone   { doc["phone"]   = phone }
        if let website { doc["website"] = website }
        return doc
    }

    init?(firestoreDocument doc: [String: Any], id: String) {
        guard
            let name     = doc["name"]     as? String,
            let category = doc["category"] as? String
        else { return nil }
        self.id              = id
        self.name            = name
        self.category        = category
        self.latitude        = doc["latitude"]        as? Double ?? 0
        self.longitude       = doc["longitude"]       as? Double ?? 0
        self.rating          = doc["rating"]          as? Double ?? 0
        self.checkinCount    = doc["checkinCount"]    as? Int    ?? 0
        self.publicImageURLs = doc["publicImageURLs"] as? [String] ?? []
        self.claimedBusiness = doc["claimedBusiness"] as? Bool   ?? false
        self.phone           = doc["phone"]    as? String
        self.website         = doc["website"]  as? String
        self.updatedAt       = (doc["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}

// MARK: – Firestore ↔ Checkin

private extension Checkin {
    /// Builds the Firestore dict — imagePaths is intentionally excluded (local-only).
    func firestoreDocument() -> [String: Any] {
        [
            "placeRef":        placeRef,
            "personalRating":  personalRating,
            "personalComment": personalComment,
            "imageURLs":       imageURLs,
            "checkedInAt":     Timestamp(date: checkedInAt),
            "visibility":      visibility.rawValue,
            "sharedWith":      sharedWith
        ]
    }

    init?(firestoreDocument doc: [String: Any], id: String) {
        guard
            let placeRef   = doc["placeRef"]       as? String,
            let visRaw     = doc["visibility"]     as? String,
            let visibility = Visibility(rawValue: visRaw)
        else { return nil }
        self.id              = id
        self.placeRef        = placeRef
        self.personalRating  = doc["personalRating"]  as? Double ?? 0
        self.personalComment = doc["personalComment"] as? String ?? ""
        self.imageURLs       = doc["imageURLs"]       as? [String] ?? []
        self.imagePaths      = []   // local-only — never stored in Firestore
        self.checkedInAt     = (doc["checkedInAt"] as? Timestamp)?.dateValue() ?? Date()
        self.visibility      = visibility
        self.sharedWith      = doc["sharedWith"]      as? [String] ?? []
    }
}
