import UIKit

final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let diskCachePath: String

    private let maxDiskCacheSize: UInt64 = 100 * 1024 * 1024
    private let maxIdleAge: TimeInterval = 30 * 24 * 60 * 60
    private let maxFullImageMemoryCost = 4 * 1024 * 1024

    private init() {
        memoryCache.countLimit = 12
        memoryCache.totalCostLimit = 24 * 1024 * 1024
        thumbnailCache.countLimit = 60
        thumbnailCache.totalCostLimit = 12 * 1024 * 1024
        let cachesDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        diskCachePath = (cachesDir as NSString).appendingPathComponent("ImageCache")
        try? FileManager.default.createDirectory(atPath: diskCachePath, withIntermediateDirectories: true)
        cleanupDiskCache()
    }

    func getImage(forKey key: String) -> UIImage? {
        if let image = memoryCache.object(forKey: key as NSString) {
            return image
        }
        let path = cacheFilePath(for: key)
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let image = UIImage(data: data) {
            storeInMemory(image, forKey: key)
            touchDiskFile(at: path)
            return image
        }
        return nil
    }

    func getThumbnail(forKey key: String, maxPixel: CGFloat = 360) -> UIImage? {
        let thumbnailKey = "\(key)_thumb" as NSString
        if let image = thumbnailCache.object(forKey: thumbnailKey) {
            return image
        }
        guard let image = getImage(forKey: key) else { return nil }
        let thumbnail = image.scaledDown(maxPixel: maxPixel)
        thumbnailCache.setObject(thumbnail, forKey: thumbnailKey, cost: thumbnail.memoryCost)
        return thumbnail
    }

    func cacheImage(_ image: UIImage, forKey key: String) {
        storeInMemory(image, forKey: key)
        DispatchQueue.global(qos: .utility).async {
            let path = self.cacheFilePath(for: key)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: URL(fileURLWithPath: path))
                self.touchDiskFile(at: path)
                self.cleanupDiskCache()
            }
        }
    }

    func removeImage(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        thumbnailCache.removeObject(forKey: "\(key)_thumb" as NSString)
        try? FileManager.default.removeItem(atPath: cacheFilePath(for: key))
    }

    func clearBookCache(_ bookId: String) {
        memoryCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: diskCachePath) else { return }
        for file in files where file.contains(bookId) {
            try? FileManager.default.removeItem(atPath: (diskCachePath as NSString).appendingPathComponent(file))
        }
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    func handleBackgroundTransition() {
        clearMemoryCache()
        cleanupDiskCache()
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        try? FileManager.default.removeItem(atPath: diskCachePath)
        try? FileManager.default.createDirectory(atPath: diskCachePath, withIntermediateDirectories: true)
    }

    private func cacheFilePath(for key: String) -> String {
        let filename = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return (diskCachePath as NSString).appendingPathComponent(filename)
    }

    private func storeInMemory(_ image: UIImage, forKey key: String) {
        let cost = image.memoryCost
        if cost <= maxFullImageMemoryCost {
            memoryCache.setObject(image, forKey: key as NSString, cost: cost)
        }
        let thumbnail = image.scaledDown(maxPixel: 360)
        thumbnailCache.setObject(thumbnail, forKey: "\(key)_thumb" as NSString, cost: thumbnail.memoryCost)
    }

    private func touchDiskFile(at path: String) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
    }

    private func cleanupDiskCache() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: diskCachePath) else { return }

        let now = Date()
        var entries: [(path: String, size: UInt64, date: Date)] = []
        var totalSize: UInt64 = 0

        for file in files {
            let path = (diskCachePath as NSString).appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            let date = attrs[.modificationDate] as? Date ?? .distantPast
            if now.timeIntervalSince(date) > maxIdleAge {
                try? fm.removeItem(atPath: path)
                continue
            }
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            entries.append((path, size, date))
            totalSize += size
        }

        guard totalSize > maxDiskCacheSize else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fm.removeItem(atPath: entry.path)
            totalSize = totalSize > entry.size ? totalSize - entry.size : 0
            if totalSize <= maxDiskCacheSize { break }
        }
    }
}

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    func scaledDown(maxPixel: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxPixel, longest > 0 else { return self }
        let scale = maxPixel / longest
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
