//
//  EmoteImageCache.swift
//  swae
//
//  Centralized emote image cache with synchronous access for the video overlay
//  and prefetching for all rendering surfaces.
//

import SDWebImage
import UIKit

final class EmoteImageCache {
    static let shared = EmoteImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 500
    }

    /// Synchronous lookup — returns nil if not cached.
    func image(for url: URL) -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        // Check SDWebImage's disk cache as fallback
        if let key = SDWebImageManager.shared.cacheKey(for: url),
           let diskImage = SDImageCache.shared.imageFromDiskCache(forKey: key) {
            cache.setObject(diskImage, forKey: url as NSURL)
            return diskImage
        }
        return nil
    }

    /// Async load + cache. Calls completion on main thread.
    func loadImage(for url: URL, completion: ((UIImage?) -> Void)? = nil) {
        if let cached = image(for: url) {
            completion?(cached)
            return
        }
        SDWebImageManager.shared.loadImage(
            with: url,
            options: [.retryFailed, .scaleDownLargeImages],
            progress: nil
        ) { [weak self] image, _, _, _, _, _ in
            if let image {
                self?.cache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async { completion?(image) }
        }
    }

    /// Batch prefetch URLs into both SDWebImage disk cache and our memory cache.
    func prefetch(urls: [URL]) {
        SDWebImagePrefetcher.shared.prefetchURLs(urls) { [weak self] _, _ in
            // After prefetch completes, warm our memory cache
            for url in urls {
                if let key = SDWebImageManager.shared.cacheKey(for: url),
                   let image = SDImageCache.shared.imageFromDiskCache(forKey: key) {
                    self?.cache.setObject(image, forKey: url as NSURL)
                }
            }
        }
    }
}
