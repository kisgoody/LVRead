import Foundation
import UIKit

struct LanDevice: Codable, Identifiable, Equatable {
    let id: String
    var deviceName: String
    let deviceModel: String
    let platform: String
    let ipAddress: String
    let port: Int
    var lastSeenTimestamp: Date
    var isOnline: Bool

    init(id: String = UUID().uuidString,
         deviceName: String,
         deviceModel: String = UIDevice.current.model,
         platform: String = "IOS",
         ipAddress: String,
         port: Int = 29877,
         lastSeenTimestamp: Date = Date(),
         isOnline: Bool = true) {
        self.id = id
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.platform = platform
        self.ipAddress = ipAddress
        self.port = port
        self.lastSeenTimestamp = lastSeenTimestamp
        self.isOnline = isOnline
    }
}
