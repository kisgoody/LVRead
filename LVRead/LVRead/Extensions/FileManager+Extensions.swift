import Foundation

extension FileManager {
    func appDocumentsDirectory() -> String {
        NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    }

    func appCachesDirectory() -> String {
        NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
    }

    func fileSize(at path: String) -> Int64 {
        (try? attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }

    func diskFreeSpace() -> Int64 {
        guard let attrs = try? attributesOfFileSystem(forPath: appDocumentsDirectory()) else { return 0 }
        return (attrs[.systemFreeSize] as? Int64) ?? 0
    }
}
