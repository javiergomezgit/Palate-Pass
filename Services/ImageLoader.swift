// MARK: – Service
// Lightweight async image loader backed by an in-memory NSCache.
// Used by cells and detail views to display Firebase Storage images
// without re-downloading on every scroll.

import UIKit

final class ImageLoader {

    static let shared = ImageLoader()
    private init() {}

    private let cache = NSCache<NSString, UIImage>()

    // MARK: – Load

    /// Returns the cached image synchronously if available, otherwise starts a
    /// background download and calls `completion` on the main thread when done.
    /// Returns the `URLSessionDataTask` so callers can cancel stale requests on reuse.
    @discardableResult
    func load(urlString: String,
              completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {

        let key = urlString as NSString

        // Cache hit — return immediately (no task)
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return nil
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return nil
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard error == nil, let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self?.cache.setObject(image, forKey: key)
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }

    /// Synchronous cache lookup — use to avoid a flicker when the image was
    /// already loaded once during this session.
    func cachedImage(for urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }
}
