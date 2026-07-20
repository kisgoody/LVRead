import Darwin
import Foundation
import dnssd

/// Publishes the installation-specific `.local` hostname on the active local network.
final class BonjourHostPublisher {
    enum PublisherError: LocalizedError {
        case invalidAddress
        case dnsService(DNSServiceErrorType)

        var errorDescription: String? {
            switch self {
            case .invalidAddress: return "当前 Wi-Fi 地址无效"
            case .dnsService(let code): return "本地域名发布失败（错误码 \(code)）"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.lvread.websync.bonjour")
    private var serviceRef: DNSServiceRef?
    private var recordRef: DNSRecordRef?

    func start(hostName: String, ipv4Address: String) throws {
        stop()

        var address = in_addr()
        guard inet_pton(AF_INET, ipv4Address, &address) == 1 else {
            throw PublisherError.invalidAddress
        }

        var service: DNSServiceRef?
        var status = DNSServiceCreateConnection(&service)
        guard status == kDNSServiceErr_NoError, let service else {
            throw PublisherError.dnsService(status)
        }
        status = DNSServiceSetDispatchQueue(service, queue)
        guard status == kDNSServiceErr_NoError else {
            DNSServiceRefDeallocate(service)
            throw PublisherError.dnsService(status)
        }

        var record: DNSRecordRef?
        let fullName = hostName.hasSuffix(".") ? hostName : "\(hostName)."
        status = withUnsafeBytes(of: &address) { bytes in
            DNSServiceRegisterRecord(
                service,
                &record,
                DNSServiceFlags(kDNSServiceFlagsUnique),
                UInt32(kDNSServiceInterfaceIndexAny),
                fullName,
                UInt16(kDNSServiceType_A),
                UInt16(kDNSServiceClass_IN),
                UInt16(bytes.count),
                bytes.baseAddress,
                0,
                { _, _, _, error, _ in
                    if error != kDNSServiceErr_NoError {
                        LVLogger.error("mDNS hostname registration failed: \(error)", category: .network)
                    }
                },
                nil
            )
        }
        guard status == kDNSServiceErr_NoError else {
            queue.async { DNSServiceRefDeallocate(service) }
            throw PublisherError.dnsService(status)
        }

        serviceRef = service
        recordRef = record
    }

    func stop() {
        guard let service = serviceRef else { return }
        serviceRef = nil
        recordRef = nil
        queue.async {
            DNSServiceRefDeallocate(service)
        }
    }

    deinit {
        stop()
    }
}
