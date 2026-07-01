import UIKit

final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCachePath: String

    private let maxDiskCacheSize = 100 * 1024 * 1024 // 100MB

    private init() {
        memoryCache.countLimit = 30
        let cachesDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        diskCachePath = (cachesDir as NSString).appendingPathComponent("ImageCache")
        try? FileManager.default.createDirectory(atPath: diskCachePath, withIntermediateDirectories: true)
    }

    func getImage(forKey key: String) -> UIImage? {
        if let image = memoryCache.object(forKey: key as NSString) {
            return image
        }
        let path = cacheFilePath(for: key)
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: key as NSString)
            return image
        }
        return nil
    }

    func cacheImage(_ image: UIImage, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString)
        DispatchQueue.global(qos: .utility).async {
            let path = self.cacheFilePath(for: key)
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    func removeImage(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(atPath: cacheFilePath(for: key))
    }

    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(atPath: diskCachePath)
        try? FileManager.default.createDirectory(atPath: diskCachePath, withIntermediateDirectories: true)
    }

    private func cacheFilePath(for key: String) -> String {
        let filename = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return (diskCachePath as NSString).appendingPathComponent(filename)
    }
}
