import Foundation
import Security

/// Credentials are scoped to the exact explicitly configured gateway base URL.
enum NativeBridgeCredential {
    static let service = "com.innoiso.tablescape.private-bridge"
    static func endpointKey(_ endpoint: String) -> String {
        guard var components = URLComponents(string: endpoint) else { return endpoint }
        components.scheme = components.scheme?.lowercased(); components.host = components.host?.lowercased()
        components.user = nil; components.password = nil; components.query = nil; components.fragment = nil
        if components.scheme == "https", components.port == 443 { components.port = nil }
        if components.scheme == "http", components.port == 80 { components.port = nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.string ?? endpoint
    }
    static func read(endpoint: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: endpointKey(endpoint), kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String?, endpoint: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: endpointKey(endpoint)]
        if let key {
            let fields: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let result = SecItemUpdate(query as CFDictionary, fields as CFDictionary)
            if result == errSecItemNotFound {
                var addition = query; fields.forEach { addition[$0] = $1 }
                guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw GameTransportError.invalid("The private connection key could not be saved securely.") }
            } else if result != errSecSuccess { throw GameTransportError.invalid("The private connection key could not be updated securely.") }
        } else {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw GameTransportError.invalid("The private connection key could not be removed.") }
        }
    }
}

/// A game bearer belongs to one exact gateway and character. This device-only
/// Keychain record survives process termination and is never written to reports.
@MainActor enum NativeSessionCredential {
    private static var operationStatuses: [String: Int] = [:]
    static func diagnosticsSnapshot() -> [String: Int] { operationStatuses }
    private static func recordStatus(_ operation: String, _ status: OSStatus) {
        operationStatuses[operation] = Int(status)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("SCAPE_NATIVE_KEYCHAIN operation=\(operation) status=\(status)")
        }
    }
    struct Record: Codable {
        var token: String?
        var previouslyConnected: Bool
    }
    static let service = "com.innoiso.tablescape.game-session"
    static func account(endpoint: String, username: String) -> String {
        // Length-delimited JSON avoids ambiguous separators in URL paths.
        let parts = [NativeBridgeCredential.endpointKey(endpoint), username.lowercased()]
        return String(data: try! JSONEncoder().encode(parts), encoding: .utf8)!
    }
    private static func query(endpoint: String, username: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account(endpoint: endpoint, username: username)]
    }
    static func read(endpoint: String, username: String) -> Record? {
        var request = query(endpoint: endpoint, username: username)
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        recordStatus("read", status)
        guard status == errSecSuccess, let bytes = result as? Data else { return nil }
        return try? JSONDecoder().decode(Record.self, from: bytes)
    }
    static func save(_ record: Record, endpoint: String, username: String) throws {
        let request = query(endpoint: endpoint, username: username)
        let fields: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(record),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(request as CFDictionary, fields as CFDictionary)
        recordStatus("update", status)
        if status == errSecItemNotFound {
            var addition = request; fields.forEach { addition[$0] = $1 }
            let added = SecItemAdd(addition as CFDictionary, nil)
            recordStatus("add", added)
            guard added == errSecSuccess else {
                throw GameTransportError.invalid("Session recovery could not be saved securely on this device.")
            }
        } else if status != errSecSuccess {
            throw GameTransportError.invalid("Session recovery could not be updated securely on this device.")
        }
    }
    static func clearToken(endpoint: String, username: String, matching token: String?) throws {
        guard var record = read(endpoint: endpoint, username: username), record.token == token else { return }
        record.token = nil
        try save(record, endpoint: endpoint, username: username)
    }
    /// Used only by isolated QA cleanup; normal logout preserves the character marker.
    static func removeRecord(endpoint: String, username: String) throws {
        let status = SecItemDelete(query(endpoint: endpoint, username: username) as CFDictionary)
        recordStatus("delete", status)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GameTransportError.invalid("The selected session recovery record could not be removed.")
        }
    }
}

/// A redirect must never carry either gateway credential to another destination.
final class NativeSessionTransportDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space=challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,let trust=space.serverTrust,
              let accepted=NativeBridgeDeployment.evaluate(trust,host:space.host,port:space.port) else {
            completionHandler(.performDefaultHandling,nil);return
        }
        completionHandler(accepted ? .useCredential:.cancelAuthenticationChallenge,accepted ? URLCredential(trust:trust):nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}


/// A one-use file copied through the paired developer connection provisions this
/// app's exact private endpoint. No system-wide CA or TLS exception is installed.
enum NativeBridgeDeployment {
    static let anchorsKey="TableScape.privateBridgeAnchors"
    static func importIfPresent(preferences:UserDefaults) throws {
        guard let directory=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else{return}
        let file=directory.appendingPathComponent("PrivateConnection.json")
        guard FileManager.default.fileExists(atPath:file.path) else{return}
        let size=(try file.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard size>0,size<=32768 else{throw GameTransportError.invalid("Invalid private connection file.")}
        let data=try Data(contentsOf:file)
        guard let value=try JSONSerialization.jsonObject(with:data) as? [String:String],
              let endpoint=value["endpoint"],let url=URL(string:endpoint),url.scheme=="https",
              let host=url.host,isPrivateIPv4(host),url.user==nil,url.password==nil,url.query==nil,url.fragment==nil,
              url.path.isEmpty || url.path=="/",
              let key=value["bridgeKey"],key.range(of:"^[a-fA-F0-9]{64}$",options:.regularExpression) != nil,
              let encoded=value["certificateAuthority"],let certificate=Data(base64Encoded:encoded),certificate.count<=16384,
              SecCertificateCreateWithData(nil,certificate as CFData) != nil else {
            throw GameTransportError.invalid("Invalid private connection file.")
        }
        let scope=NativeBridgeCredential.endpointKey(endpoint)
        try NativeBridgeCredential.save(key,endpoint:scope)
        var anchors=preferences.dictionary(forKey:anchorsKey) ?? [:]
        anchors[scope]=certificate;preferences.set(anchors,forKey:anchorsKey)
        preferences.set(scope,forKey:"TableScape.gameEndpoint")
        try FileManager.default.removeItem(at:file)
    }
    static func isPrivateIPv4(_ host:String)->Bool {
        let pieces=host.split(separator:".",omittingEmptySubsequences:false)
        guard pieces.count==4 else{return false}
        let bytes=pieces.compactMap{Int($0)}
        guard bytes.count==4,bytes.allSatisfy({(0...255).contains($0)}) else{return false}
        return bytes[0]==10 || (bytes[0]==172 && (16...31).contains(bytes[1])) || (bytes[0]==192 && bytes[1]==168)
    }
    static func evaluate(_ trust:SecTrust,host:String,port:Int,preferences:UserDefaults = .standard)->Bool? {
        var parts=URLComponents();parts.scheme="https";parts.host=host;parts.port=port
        guard let endpoint=parts.string,
              let data=preferences.dictionary(forKey:anchorsKey)?[NativeBridgeCredential.endpointKey(endpoint)] as? Data,
              let root=SecCertificateCreateWithData(nil,data as CFData) else{return nil}
        // Retain certificate validity, server-auth usage, and the actual IP SAN
        // check. Only this endpoint may chain to its explicitly installed root.
        guard SecTrustSetPolicies(trust,SecPolicyCreateSSL(true,host as CFString))==errSecSuccess,
              SecTrustSetAnchorCertificates(trust,[root] as CFArray)==errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust,true)==errSecSuccess else{return false}
        return SecTrustEvaluateWithError(trust,nil)
    }
}
