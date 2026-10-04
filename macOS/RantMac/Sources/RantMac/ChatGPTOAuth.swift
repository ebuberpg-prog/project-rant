import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct ChatGPTCredential: Codable {
    let email: String
    let subject: String
    let clientID: String
    let hostID: String
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]
}

@MainActor
final class ChatGPTOAuth: ObservableObject {
    @Published private(set) var credential: ChatGPTCredential?
    private let keychainKey = "chatgpt-plan-credential"
    private let hostDefaultsKey = "rant.openai.host-id"
    private let session = URLSession.shared
    private var refreshTask: Task<String, Error>?

    init() { credential = loadCredential() }

    var signedInEmail: String? { credential?.email }
    var isPlanEnabled: Bool { credential?.scopes.contains("chatgpt.tokens.use.direct") == true }

    func signIn() async throws {
        let hostID = UserDefaults.standard.string(forKey: hostDefaultsKey) ?? "urn:uuid:\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(hostID, forKey: hostDefaultsKey)
        let existing = credential
        let clientID = existing?.clientID ?? "dynamic_agent_client"
        let port = try Self.availableLoopbackPort()
        let redirectURI = "http://127.0.0.1:\(port)/auth/callback"
        let state = try Self.randomToken(byteCount: 32)
        let nonce = try Self.randomToken(byteCount: 32)
        let verifier = try Self.randomToken(byteCount: 48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64URLEncodedString()

        let callbackTask = Task { try await self.listenForCallback(port: port) }
        var ready = false
        for _ in 0..<30 {
            if callbackTask.isCancelled { break }
            if !Self.canBindLoopbackPort(port) { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard ready else { callbackTask.cancel(); throw OAuthError.callbackUnavailable }

        var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
            URLQueryItem(name: "resource", value: "https://api.openai.com/v1"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]
        if existing == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: "Rant"))
        } else if let existing {
            items.append(URLQueryItem(name: "id_token_hint", value: existing.idToken))
            items.append(URLQueryItem(name: "login_hint", value: existing.email))
        }
        components.queryItems = items
        guard let authorizationURL = components.url else { throw OAuthError.badAuthorizationURL }
        NSWorkspace.shared.open(authorizationURL)

        let callback: URL
        do { callback = try await callbackTask.value }
        catch { throw error }
        guard let response = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { throw OAuthError.badCallback }
        let values = Dictionary(response.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { first, _ in first })
        guard values["state"] == state else { throw OAuthError.stateMismatch }
        if let error = values["error"], !error.isEmpty { throw OAuthError.authorizationDenied(error) }
        guard let code = values["code"], !code.isEmpty else { throw OAuthError.missingCode }

        let issuedClientID = values["client_id"] ?? existing?.clientID
        guard let issuedClientID, !issuedClientID.isEmpty, issuedClientID != "dynamic_agent_client" else {
            throw OAuthError.registrationIncomplete
        }
        if let existing, issuedClientID != existing.clientID { throw OAuthError.clientMismatch }

        let tokens = try await exchangeCode(code, clientID: issuedClientID, verifier: verifier, redirectURI: redirectURI)
        let claims = try await validateIDToken(tokens.idToken, expectedClientID: issuedClientID, expectedNonce: nonce)
        let scopes = tokens.scope.split(whereSeparator: \.isWhitespace).map(String.init)
        guard scopes.contains("chatgpt.tokens.use.direct") else { throw OAuthError.planPermissionMissing }
        if let existing, claims.subject != existing.subject { throw OAuthError.accountMismatch }

        let saved = ChatGPTCredential(
            email: claims.email,
            subject: claims.subject,
            clientID: issuedClientID,
            hostID: hostID,
            idToken: tokens.idToken,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn)),
            scopes: scopes
        )
        try saveCredential(saved)
        credential = saved
    }

    func accessToken() async throws -> String {
        guard let current = credential else { throw OAuthError.notSignedIn }
        if current.expiresAt.timeIntervalSinceNow > 90 { return current.accessToken }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.refreshAccessToken() }
        refreshTask = task
        do {
            let token = try await task.value
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func refreshAccessToken() async throws -> String {
        guard var current = credential else { throw OAuthError.notSignedIn }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "grant_type": "refresh_token",
            "client_id": current.clientID,
            "refresh_token": current.refreshToken,
            "resource": "https://api.openai.com/v1"
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // Keep a valid refresh token when the service is temporarily unavailable.
            if let http = response as? HTTPURLResponse,
               (400..<500).contains(http.statusCode),
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               body["error"] as? String == "invalid_grant" {
                try? clearCredential()
                credential = nil
            }
            throw OAuthError.refreshFailed
        }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        current.accessToken = tokens.accessToken
        current.refreshToken = tokens.refreshToken
        current.idToken = tokens.idToken
        current.expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        current.scopes = tokens.scope.split(whereSeparator: \.isWhitespace).map(String.init)
        try saveCredential(current)
        credential = current
        return current.accessToken
    }

    @discardableResult
    func signOut() async -> Bool {
        if let refreshTask { _ = try? await refreshTask.value }
        refreshTask = nil
        var revoked = false
        if let current = credential {
            if let configurationURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration"),
               let (data, _) = try? await session.data(from: configurationURL),
               let configuration = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let endpointString = configuration["revocation_endpoint"] as? String,
               let endpoint = URL(string: endpointString) {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Self.formBody([
                    "token": current.refreshToken,
                    "token_type_hint": "refresh_token",
                    "client_id": current.clientID
                ])
                if let (_, response) = try? await session.data(for: request),
                   let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode) {
                    revoked = true
                }
            }
        }
        try? clearCredential()
        credential = nil
        return revoked
    }

    private func exchangeCode(_ code: String, clientID: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "resource": "https://api.openai.com/v1"
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw OAuthError.tokenExchangeFailed }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func validateIDToken(_ token: String, expectedClientID: String, expectedNonce: String) async throws -> IDClaims {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let headerData = Data(base64URL: String(parts[0])),
              let payloadData = Data(base64URL: String(parts[1])),
              let signature = Data(base64URL: String(parts[2])),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let kid = header["kid"] as? String,
              let algorithm = header["alg"] as? String,
              let issuer = claims["iss"] as? String,
              issuer == "https://auth.openai.com",
              let subject = claims["sub"] as? String,
              let nonce = claims["nonce"] as? String,
              nonce == expectedNonce,
              let expiresAt = claims["exp"] as? TimeInterval,
              expiresAt > Date().timeIntervalSince1970,
              let email = claims["email"] as? String else { throw OAuthError.invalidIDToken }

        let audienceMatches: Bool
        if let audience = claims["aud"] as? String { audienceMatches = audience == expectedClientID }
        else if let audiences = claims["aud"] as? [String] { audienceMatches = audiences.contains(expectedClientID) }
        else { audienceMatches = false }
        guard audienceMatches else { throw OAuthError.invalidIDToken }

        let configurationURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
        let (configurationData, _) = try await session.data(from: configurationURL)
        guard let configuration = try JSONSerialization.jsonObject(with: configurationData) as? [String: Any],
              let jwksURLText = configuration["jwks_uri"] as? String,
              let jwksURL = URL(string: jwksURLText) else { throw OAuthError.keySetUnavailable }
        let (keyData, _) = try await session.data(from: jwksURL)
        guard let keySet = try JSONSerialization.jsonObject(with: keyData) as? [String: Any],
              let keys = keySet["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              let modulus = key["n"] as? String,
              let exponent = key["e"] as? String,
              algorithm == "RS256" else { throw OAuthError.keySetUnavailable }
        guard let publicKey = Self.rsaPublicKey(modulus: modulus, exponent: exponent) else { throw OAuthError.keySetUnavailable }
        let signedPayload = Data("\(parts[0]).\(parts[1])".utf8)
        var error: Unmanaged<CFError>?
        guard SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, signedPayload as CFData, signature as CFData, &error) else {
            throw OAuthError.invalidIDToken
        }
        return IDClaims(subject: subject, email: email)
    }

    private func listenForCallback(port: UInt16) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let gate = CallbackGate()
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
            guard let listener = try? NWListener(using: parameters) else {
                continuation.resume(throwing: OAuthError.callbackUnavailable)
                return
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                    guard error == nil, let data,
                          let requestText = String(data: data, encoding: .utf8),
                          let requestLine = requestText.components(separatedBy: "\r\n").first,
                          let target = requestLine.split(separator: " ").dropFirst().first,
                          let url = URL(string: "http://127.0.0.1:\(port)\(target)"),
                          url.path == "/auth/callback" else {
                        let body = Data("Invalid callback".utf8)
                        let header = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
                        connection.send(content: header + body, completion: .contentProcessed { _ in connection.cancel() })
                        return
                    }
                    guard gate.claim() else { connection.cancel(); return }
                    let html = "<html><body style='font:16px -apple-system;padding:40px'>Rant is connected. You can return to the app.</body></html>"
                    let body = Data(html.utf8)
                    let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
                    connection.send(content: header + body, completion: .contentProcessed { _ in connection.cancel() })
                    listener.cancel()
                    continuation.resume(returning: url)
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed = state, gate.claim() {
                    continuation.resume(throwing: OAuthError.callbackUnavailable)
                }
            }
            listener.start(queue: .global())
        }
    }

    private func loadCredential() -> ChatGPTCredential? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Rant", kSecAttrAccount as String: keychainKey, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        query.removeAll(keepingCapacity: false)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ChatGPTCredential.self, from: data)
    }

    private func saveCredential(_ credential: ChatGPTCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Rant", kSecAttrAccount as String: keychainKey]
        SecItemDelete(key as CFDictionary)
        var attributes = key
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw OAuthError.credentialStorageFailed }
    }

    private func clearCredential() throws {
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Rant", kSecAttrAccount as String: keychainKey]
        let status = SecItemDelete(key as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OAuthError.credentialStorageFailed }
    }

    private static func availableLoopbackPort() throws -> UInt16 {
        for port in UInt16.random(in: 20_000...50_000)..<60_000 {
            if canBindLoopbackPort(port) { return port }
        }
        throw OAuthError.callbackUnavailable
    }

    private static func canBindLoopbackPort(_ port: UInt16) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }

    private static func randomToken(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else { throw OAuthError.randomGenerationFailed }
        return Data(bytes).base64URLEncodedString()
    }

    private static func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func rsaPublicKey(modulus: String, exponent: String) -> SecKey? {
        guard let n = Data(base64URL: modulus), let e = Data(base64URL: exponent) else { return nil }
        let rsa = derSequence(derInteger(n) + derInteger(e))
        let algorithm = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
        let bitString = derElement(0x03, Data([0x00]) + rsa)
        let spki = derSequence(algorithm + bitString)
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic, kSecAttrKeySizeInBits as String: n.count * 8]
        return SecKeyCreateWithData(spki as CFData, attributes as CFDictionary, nil)
    }

    private static func derSequence(_ content: Data) -> Data { derElement(0x30, content) }
    private static func derInteger(_ value: Data) -> Data {
        let normalized = value.first.map { $0 & 0x80 == 0 ? value : Data([0]) + value } ?? Data([0])
        return derElement(0x02, normalized)
    }
    private static func derElement(_ tag: UInt8, _ content: Data) -> Data {
        var output = Data([tag])
        if content.count < 128 { output.append(UInt8(content.count)) }
        else {
            var length = content.count
            var bytes: [UInt8] = []
            while length > 0 { bytes.insert(UInt8(length & 0xFF), at: 0); length >>= 8 }
            output.append(0x80 | UInt8(bytes.count))
            output.append(contentsOf: bytes)
        }
        output.append(content)
        return output
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let idToken: String
    let expiresIn: Int
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case scope
    }
}

private final class CallbackGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

private struct IDClaims { let subject: String; let email: String }

enum OAuthError: LocalizedError {
    case callbackUnavailable, badAuthorizationURL, badCallback, stateMismatch, missingCode
    case authorizationDenied(String), registrationIncomplete, clientMismatch, tokenExchangeFailed
    case invalidIDToken, keySetUnavailable, planPermissionMissing, accountMismatch, credentialStorageFailed
    case notSignedIn, refreshFailed, randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .callbackUnavailable: "Couldn’t open the secure sign-in callback. Try again."
        case .badAuthorizationURL: "Couldn’t create the ChatGPT sign-in link."
        case .badCallback: "ChatGPT returned an invalid sign-in response."
        case .stateMismatch: "The sign-in response didn’t match this request. Try again."
        case .missingCode: "ChatGPT didn’t return an authorization code."
        case .authorizationDenied: "ChatGPT sign-in was cancelled or plan access wasn’t approved."
        case .registrationIncomplete: "The ChatGPT app registration didn’t finish. Try signing in again."
        case .clientMismatch: "ChatGPT returned a different app registration. Try signing in again."
        case .tokenExchangeFailed: "Couldn’t complete ChatGPT sign-in. Try again."
        case .invalidIDToken: "Couldn’t verify the ChatGPT account."
        case .keySetUnavailable: "Couldn’t verify the ChatGPT sign-in. Check your connection and retry."
        case .planPermissionMissing: "Allow Rant to use your ChatGPT plan during sign-in."
        case .accountMismatch: "The signed-in ChatGPT account doesn’t match the saved account."
        case .credentialStorageFailed: "Couldn’t securely save your ChatGPT sign-in on this Mac."
        case .notSignedIn: "Sign in with ChatGPT to use GPT cleanup."
        case .refreshFailed: "Your ChatGPT sign-in expired. Sign in again in Settings."
        case .randomGenerationFailed: "Couldn’t safely start ChatGPT sign-in. Try again."
        }
    }
}

private extension Data {
    init?(base64URL value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
