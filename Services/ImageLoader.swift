// MARK: – Service
// Lightweight async image loader backed by an in-memory NSCache.
// Used by cells and detail views to display Firebase Storage images
// without re-downloading on every scroll.

import UIKit
import ImageIO

final class ImageLoader {

    static let shared = ImageLoader()
    private init() {}

    private let cache = NSCache<NSString, UIImage>()

    /// Serialises local-file decoding off the main thread.
    private let localQueue = DispatchQueue(label: "ImageLoader.local", qos: .userInitiated)

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

    // MARK: – Local thumbnails

    /// Cache-only lookup for a local thumbnail, so a reload of an already-seen row
    /// paints in the same runloop pass.
    func cachedThumbnail(named name: String, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: Self.thumbKey(name, maxPixel))
    }

    /// Decodes a photo from Documents/ **off the main thread**, downsampled to the size
    /// actually displayed, and caches the result. Photos are stored at full camera
    /// resolution, so decoding them inline in `cellForRowAt` stalled every table reload.
    func loadThumbnail(named name: String,
                       maxPixel: CGFloat,
                       completion: @escaping (UIImage?) -> Void) {

        let key = Self.thumbKey(name, maxPixel)
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        localQueue.async { [weak self] in
            let image = DataManager.shared.imageFileURL(named: name)
                .flatMap { Self.downsampledImage(at: $0, maxPixel: maxPixel) }
            if let image { self?.cache.setObject(image, forKey: key) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    private static func thumbKey(_ name: String, _ maxPixel: CGFloat) -> NSString {
        "thumb:\(Int(maxPixel)):\(name)" as NSString
    }

    /// ImageIO thumbnail generation — never allocates a full-resolution bitmap.
    private static func downsampledImage(at url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true,
            kCGImageSourceThumbnailMaxPixelSize:          maxPixel
        ] as [CFString: Any] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
