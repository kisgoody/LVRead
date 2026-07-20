import CryptoKit
import Foundation
import Security

/// Creates one local CA per installation and uses it to issue the HTTPS identity.
/// Private keys stay in the device Keychain; only the public root certificate is exportable.
final class WebSyncIdentityManager {
    struct Identity {
        let secIdentity: SecIdentity
        let hostName: String
        let rootCertificateURL: URL
        let rootFingerprint: String
    }

    enum IdentityError: LocalizedError {
        case keychain(OSStatus)
        case invalidStoredCertificate
        case keyCreation(String)
        case certificateCreation(String)
        case identityCreation
        case export(String)

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                return "安全证书存储失败（错误码 \(status)）"
            case .invalidStoredCertificate:
                return "已保存的安全证书无效"
            case .keyCreation(let message):
                return "安全密钥创建失败：\(message)"
            case .certificateCreation(let message):
                return "安全证书创建失败：\(message)"
            case .identityCreation:
                return "无法创建 HTTPS 服务身份"
            case .export(let message):
                return "根证书导出失败：\(message)"
            }
        }
    }

    static let shared = WebSyncIdentityManager()

    private enum StorageKey {
        static let service = "com.lvread.websync.identity"
        static let hostName = "host-name"
        static let rootCertificate = "root-certificate-v3"
        static let rootPrivateKeyTag = Data("com.lvread.websync.root-key.v3".utf8)
        static let leafPrivateKeyTag = Data("com.lvread.websync.leaf-key.v3".utf8)
    }

    private init() {}

    func makeIdentity() throws -> Identity {
        let hostName = try loadOrCreateHostName()
        let rootKey = try loadOrCreatePrivateKey(tag: StorageKey.rootPrivateKeyTag)
        let rootCertificate = try loadOrCreateRootCertificate(privateKey: rootKey, hostName: hostName)
        let leafKey = try loadOrCreatePrivateKey(tag: StorageKey.leafPrivateKeyTag)
        let leafCertificate = try makeLeafCertificate(
            privateKey: leafKey,
            hostName: hostName,
            rootPrivateKey: rootKey
        )

        guard let identity = SecIdentityCreate(nil, leafCertificate, leafKey) else {
            throw IdentityError.identityCreation
        }

        let rootData = SecCertificateCopyData(rootCertificate) as Data
        let certificateURL = try exportRootCertificate(rootData)
        return Identity(
            secIdentity: identity,
            hostName: hostName,
            rootCertificateURL: certificateURL,
            rootFingerprint: Self.fingerprint(for: rootData)
        )
    }

    private func loadOrCreateHostName() throws -> String {
        if let data = try loadData(account: StorageKey.hostName),
           let hostName = String(data: data, encoding: .utf8),
           !hostName.isEmpty {
            return hostName
        }
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            .prefix(8).lowercased()
        let hostName = "lvread-\(suffix).local"
        try saveData(Data(hostName.utf8), account: StorageKey.hostName)
        return hostName
    }

    private func loadOrCreatePrivateKey(tag: Data) throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let key = item as! SecKey? { return key }
        guard status == errSecItemNotFound else { throw IdentityError.keychain(status) }

        let privateKeyAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tag,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: privateKeyAttributes
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "未知错误"
            throw IdentityError.keyCreation(message)
        }
        return key
    }

    private func loadOrCreateRootCertificate(
        privateKey: SecKey,
        hostName: String
    ) throws -> SecCertificate {
        if let data = try loadData(account: StorageKey.rootCertificate) {
            guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
                throw IdentityError.invalidStoredCertificate
            }
            return certificate
        }

        do {
            let secCertificate = try LocalCertificateBuilder.makeRoot(
                privateKey: privateKey,
                commonName: "LVRead Local Root CA \(hostName)"
            )
            try saveData(SecCertificateCopyData(secCertificate) as Data, account: StorageKey.rootCertificate)
            return secCertificate
        } catch {
            throw IdentityError.certificateCreation(String(describing: error))
        }
    }

    private func makeLeafCertificate(
        privateKey: SecKey,
        hostName: String,
        rootPrivateKey: SecKey
    ) throws -> SecCertificate {
        do {
            return try LocalCertificateBuilder.makeServer(
                privateKey: privateKey,
                hostName: hostName,
                issuerCommonName: "LVRead Local Root CA \(hostName)",
                issuerPrivateKey: rootPrivateKey
            )
        } catch {
            throw IdentityError.certificateCreation(String(describing: error))
        }
    }

    private func exportRootCertificate(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LVRead-Root-CA", isDirectory: false)
            .appendingPathExtension("cer")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw IdentityError.export(error.localizedDescription)
        }
    }

    private func loadData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: StorageKey.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw IdentityError.keychain(status)
        }
        return data
    }

    private func saveData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: StorageKey.service,
            kSecAttrAccount as String: account
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw IdentityError.keychain(updateStatus) }

        var insert = query
        values.forEach { insert[$0.key] = $0.value }
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw IdentityError.keychain(insertStatus) }
    }

    private static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// Minimal X.509 v3 certificate encoder. Security.framework owns key generation and signing;
/// this type only builds the DER structure needed by SecCertificate.
private enum LocalCertificateBuilder {
    enum BuilderError: LocalizedError {
        case publicKey(String)
        case random(OSStatus)
        case signing(String)
        case invalidCertificate

        var errorDescription: String? {
            switch self {
            case .publicKey(let message): return "无法读取证书公钥：\(message)"
            case .random(let status): return "证书序列号生成失败（错误码 \(status)）"
            case .signing(let message): return "证书签名失败：\(message)"
            case .invalidCertificate: return "生成的证书格式无效"
            }
        }
    }

    private static let signatureAlgorithm = DER.sequence([
        DER.oid([1, 2, 840, 10045, 4, 3, 2]) // ecdsa-with-SHA256
    ])

    static func makeRoot(privateKey: SecKey, commonName: String) throws -> SecCertificate {
        let now = Date()
        let expiry = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: now)
            ?? now.addingTimeInterval(10 * 365 * 24 * 60 * 60)
        let name = distinguishedName(commonName: commonName)
        return try makeCertificate(
            publicKey: privateKey,
            issuer: name,
            subject: name,
            notBefore: now.addingTimeInterval(-300),
            notAfter: expiry,
            extensions: [
                extensionValue(
                    oid: [2, 5, 29, 19],
                    critical: true,
                    value: DER.sequence([DER.boolean(true), DER.integer(Data([0]))])
                ),
                extensionValue(
                    oid: [2, 5, 29, 15],
                    critical: true,
                    value: DER.bitString(Data([0x06]), unusedBits: 1)
                )
            ],
            signingKey: privateKey
        )
    }

    static func makeServer(
        privateKey: SecKey,
        hostName: String,
        issuerCommonName: String,
        issuerPrivateKey: SecKey
    ) throws -> SecCertificate {
        let now = Date()
        return try makeCertificate(
            publicKey: privateKey,
            issuer: distinguishedName(commonName: issuerCommonName),
            subject: distinguishedName(commonName: hostName),
            notBefore: now.addingTimeInterval(-300),
            notAfter: now.addingTimeInterval(90 * 24 * 60 * 60),
            extensions: [
                extensionValue(
                    oid: [2, 5, 29, 19],
                    critical: true,
                    value: DER.sequence([])
                ),
                extensionValue(
                    oid: [2, 5, 29, 15],
                    critical: true,
                    value: DER.bitString(Data([0x80]), unusedBits: 7)
                ),
                extensionValue(
                    oid: [2, 5, 29, 37],
                    critical: false,
                    value: DER.sequence([DER.oid([1, 3, 6, 1, 5, 5, 7, 3, 1])])
                ),
                extensionValue(
                    oid: [2, 5, 29, 17],
                    critical: false,
                    value: DER.sequence([DER.element(tag: 0x82, content: Data(hostName.utf8))])
                )
            ],
            signingKey: issuerPrivateKey
        )
    }

    private static func makeCertificate(
        publicKey: SecKey,
        issuer: Data,
        subject: Data,
        notBefore: Date,
        notAfter: Date,
        extensions: [Data],
        signingKey: SecKey
    ) throws -> SecCertificate {
        let tbsCertificate = DER.sequence([
            DER.element(tag: 0xA0, content: DER.integer(Data([2]))),
            try serialNumber(),
            signatureAlgorithm,
            issuer,
            DER.sequence([DER.utcTime(notBefore), DER.utcTime(notAfter)]),
            subject,
            try subjectPublicKeyInfo(for: publicKey),
            DER.element(tag: 0xA3, content: DER.sequence(extensions))
        ])

        var signingError: Unmanaged<CFError>?
        guard SecKeyIsAlgorithmSupported(signingKey, .sign, .ecdsaSignatureMessageX962SHA256),
              let signature = SecKeyCreateSignature(
                signingKey,
                .ecdsaSignatureMessageX962SHA256,
                tbsCertificate as CFData,
                &signingError
              ) as Data? else {
            let message = signingError?.takeRetainedValue().localizedDescription ?? "不支持 ECDSA SHA-256"
            throw BuilderError.signing(message)
        }

        let encoded = DER.sequence([
            tbsCertificate,
            signatureAlgorithm,
            DER.bitString(signature, unusedBits: 0)
        ])
        guard let certificate = SecCertificateCreateWithData(nil, encoded as CFData) else {
            throw BuilderError.invalidCertificate
        }
        return certificate
    }

    private static func distinguishedName(commonName: String) -> Data {
        let organization = DER.set([
            DER.sequence([DER.oid([2, 5, 4, 10]), DER.utf8String("LVRead")])
        ])
        let commonName = DER.set([
            DER.sequence([DER.oid([2, 5, 4, 3]), DER.utf8String(commonName)])
        ])
        return DER.sequence([organization, commonName])
    }

    private static func subjectPublicKeyInfo(for privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let bytes = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "公钥不存在"
            throw BuilderError.publicKey(message)
        }
        let algorithm = DER.sequence([
            DER.oid([1, 2, 840, 10045, 2, 1]),
            DER.oid([1, 2, 840, 10045, 3, 1, 7])
        ])
        return DER.sequence([algorithm, DER.bitString(bytes, unusedBits: 0)])
    }

    private static func extensionValue(
        oid: [UInt64],
        critical: Bool,
        value: Data
    ) -> Data {
        var fields = [DER.oid(oid)]
        if critical { fields.append(DER.boolean(true)) }
        fields.append(DER.octetString(value))
        return DER.sequence(fields)
    }

    private static func serialNumber() throws -> Data {
        var bytes = Data(count: 16)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw BuilderError.random(status) }
        bytes[bytes.startIndex] &= 0x7F
        if bytes.allSatisfy({ $0 == 0 }) { bytes[bytes.index(before: bytes.endIndex)] = 1 }
        return DER.integer(bytes)
    }
}

private enum DER {
    static func element(tag: UInt8, content: Data) -> Data {
        Data([tag]) + length(content.count) + content
    }

    static func sequence(_ values: [Data]) -> Data {
        element(tag: 0x30, content: values.reduce(into: Data()) { $0.append($1) })
    }

    static func set(_ values: [Data]) -> Data {
        element(tag: 0x31, content: values.reduce(into: Data()) { $0.append($1) })
    }

    static func integer(_ value: Data) -> Data {
        var bytes = value.drop { $0 == 0 }
        if bytes.isEmpty { bytes = Data([0])[...] }
        var content = Data(bytes)
        if content.first.map({ $0 & 0x80 != 0 }) == true { content.insert(0, at: 0) }
        return element(tag: 0x02, content: content)
    }

    static func boolean(_ value: Bool) -> Data {
        element(tag: 0x01, content: Data([value ? 0xFF : 0x00]))
    }

    static func bitString(_ value: Data, unusedBits: UInt8) -> Data {
        element(tag: 0x03, content: Data([unusedBits]) + value)
    }

    static func octetString(_ value: Data) -> Data {
        element(tag: 0x04, content: value)
    }

    static func utf8String(_ value: String) -> Data {
        element(tag: 0x0C, content: Data(value.utf8))
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return element(tag: 0x17, content: Data(formatter.string(from: date).utf8))
    }

    static func oid(_ components: [UInt64]) -> Data {
        precondition(components.count >= 2 && components[0] <= 2)
        var content = Data([UInt8(components[0] * 40 + components[1])])
        for component in components.dropFirst(2) {
            var value = component
            var encoded = [UInt8(value & 0x7F)]
            value >>= 7
            while value > 0 {
                encoded.append(UInt8(value & 0x7F) | 0x80)
                value >>= 7
            }
            content.append(contentsOf: encoded.reversed())
        }
        return element(tag: 0x06, content: content)
    }

    private static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var value = count
        var bytes = [UInt8]()
        while value > 0 {
            bytes.append(UInt8(value & 0xFF))
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes.reversed())
    }
}
