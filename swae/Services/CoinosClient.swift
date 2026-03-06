//
//  CoinosClient.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import CryptoKit
import Foundation
import NostrSDK

/// Implements a client that can talk to the Coinos API server with a deterministic account derived from the user's private key.
///
/// This is NOT a general-purpose Coinos client, and only works with the user's own deterministic "one-click setup" Coinos wallet account.
class CoinosClient {
    // MARK: - Constants

    /// Custom User-Agent sent with every Coinos request so the server can identify (and whitelist) Swae.
    private static let userAgent = "swae/iOS"

    // MARK: - State

    /// The user's normal keypair for using Nostr
    private let userKeypair: Keypair
    /// The JWT authentication token with Coinos
    private var jwtAuthToken: String? = nil

    // MARK: - Computed properties for a deterministic wallet

    /// A deterministic keypair for the NWC connection derived from the user's private key
    private var nwcKeypair: Keypair? {
        guard userKeypair.privateKey.dataRepresentation != nil else {
            print("❌ CoinosClient: userKeypair.privateKey.dataRepresentation is nil")
            return nil
        }

        let nwcPrivateKeyDigest = SHA256.hash(data: userKeypair.privateKey.dataRepresentation)
        let nwcPrivateKeyData = Data(nwcPrivateKeyDigest)

        guard let nwcPrivateKey = PrivateKey(dataRepresentation: nwcPrivateKeyData) else {
            print("❌ CoinosClient: Failed to create PrivateKey from nwcPrivateKeyData")
            return nil
        }

        let keypair = Keypair(privateKey: nwcPrivateKey)
        print("🔍 CoinosClient: Derived NWC keypair (pubkey: \(keypair?.publicKey.hex.prefix(8) ?? "nil")...)")

        return keypair
    }

    /// Public getter for the NWC keypair
    var publicNWCKeypair: Keypair? {
        return nwcKeypair
    }

    /// A deterministic username for a Coinos account
    private var username: String? {
        // Derive from private key because deriving from a pubkey would mean that anyone could compute the username and take that username before our user
        // Add some prefix so that we can ensure this will NOT match the password nor the NWC keypair
        guard userKeypair.privateKey.dataRepresentation != nil else { return nil }
        let usernameDigest = SHA256.hash(
            data: ("coinos_username:" + userKeypair.privateKey.hex).data(using: .utf8) ?? Data())
        let usernameData = Data(usernameDigest)
        let usernameHex = usernameData.map { String(format: "%02x", $0) }.joined()
        // Use first 16 characters to avoid birthday attacks
        return String(usernameHex.prefix(16))
    }

    var expectedLud16: String? {
        guard let username else { return nil }
        return username + "@coinos.io"
    }

    /// A deterministic password for a Coinos account
    private var password: String? {
        // Add some prefix so that we can ensure this will NOT match the user nor the NWC private key
        guard userKeypair.privateKey.dataRepresentation != nil else { return nil }
        let passwordDigest = SHA256.hash(
            data: ("coinos_password:" + userKeypair.privateKey.hex).data(using: .utf8) ?? Data())
        let passwordData = Data(passwordDigest)
        return passwordData.map { String(format: "%02x", $0) }.joined()
    }

    /// A deterministic NWC app connection name
    private var nwcConnectionName: String { return "Swae" }

    // MARK: - Initialization

    /// Initializes the client with the user's keypair
    init(userKeypair: Keypair) {
        self.userKeypair = userKeypair
    }

    // MARK: - Authentication and registration

    /// Tries to login to the user's deterministic account. If it cannot be found, it will register for one and log into that.
    func loginOrRegister() async throws {
        do {
            // Check if client has an account
            try await self.login()
        } catch {
            guard let error = error as? ClientError, error == .unauthorized else { throw error }
            // Client does not seem to have an account, create one
            try await self.register()
            try await self.login()
        }
    }

    /// Registers for a Coinos account using deterministic account details.
    ///
    /// It succeeds if it returns without throwing errors.
    func register() async throws {
        guard let username, let password else { throw ClientError.errorFormingRequest }
        let registerPayload = RegisterRequest(
            user: UserCredentials(username: username, password: password))
        let jsonData = try JSONEncoder().encode(registerPayload)

        let url = URL(string: "https://coinos.io/api/register")!
        let (data, response) = try await makeRequest(
            method: .post, url: url, payload: jsonData, payload_type: .json)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return
        } else {
            throw ClientError.unexpectedHTTPResponse(
                status_code: (response as? HTTPURLResponse)?.statusCode ?? -1, response: data)
        }
    }

    /// Logs into the deterministic account, if an auth token is not present
    func loginIfNeeded() async throws {
        if self.jwtAuthToken == nil { try await self.login() }
    }

    /// Logs into to our deterministic account.
    ///
    /// Succeeds if it returns without returning errors.
    ///
    /// Mutating function, will update the client's internal state.
    func login() async throws {
        self.jwtAuthToken = try await sendLoginRequest().token
    }

    /// Sends the login request and return the response
    ///
    /// Does NOT update the internal login state.
    private func sendLoginRequest() async throws -> AuthResponse {
        guard let url = URL(string: "https://coinos.io/api/login") else {
            throw ClientError.errorFormingRequest
        }
        guard let username, let password else { throw ClientError.errorFormingRequest }
        let credentials = UserCredentials(username: username, password: password)
        let jsonData = try JSONEncoder().encode(credentials)

        let (data, response) = try await makeRequest(
            method: .post, url: url, payload: jsonData, payload_type: .json)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200: return try JSONDecoder().decode(AuthResponse.self, from: data)
            case 401: throw ClientError.unauthorized
            default:
                throw ClientError.unexpectedHTTPResponse(
                    status_code: httpResponse.statusCode, response: data)
            }
        }
        throw ClientError.errorProcessingResponse
    }

    // MARK: - Managing NWC connections

    /// Creates a new NWC connection
    ///
    /// Note: Account must exist before calling this endpoint
    func createNWCConnection() async throws -> WalletConnectURL {
        print("🔍 CoinosClient: createNWCConnection called")
        guard let nwcKeypair else {
            print("❌ CoinosClient: nwcKeypair is nil in createNWCConnection")
            throw ClientError.errorFormingRequest
        }
        guard let urlEndpoint = URL(string: "https://coinos.io/api/app") else {
            throw ClientError.errorFormingRequest
        }

        print("🔧 CoinosClient: Creating NWC connection")
        print("🔧 CoinosClient: Using NWC keypair pubkey: \(nwcKeypair.publicKey.hex.prefix(8))...")

        try await self.loginIfNeeded()

        let config = try defaultWalletConnectionConfig()
        print("🔧 CoinosClient: NWC config - name: \(config.name)")
        print("🔧 CoinosClient: NWC config - max_amount: \(config.max_amount)")
        print("🔧 CoinosClient: NWC config - budget_renewal: \(config.budget_renewal)")

        let configData = try JSONEncoder().encode(config)
        let (data, response) = try await self.makeAuthenticatedRequest(
            method: .post,
            url: urlEndpoint,
            payload: configData,
            payload_type: .json
        )

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                guard let nwc = try await self.getNWCUrl() else {
                    throw ClientError.errorProcessingResponse
                }
                return nwc
            case 401: throw ClientError.unauthorized
            default:
                throw ClientError.unexpectedHTTPResponse(
                    status_code: httpResponse.statusCode, response: data)
            }
        }
        throw ClientError.errorProcessingResponse
    }

    /// Deletes the existing NWC connection
    ///
    /// Note: Account and NWC connection must exist before calling this endpoint
    func deleteNWCConnection() async throws {
        print("🔍 CoinosClient: deleteNWCConnection called")
        guard let nwcKeypair else {
            print("❌ CoinosClient: nwcKeypair is nil in deleteNWCConnection")
            throw ClientError.errorFormingRequest
        }
        guard let urlEndpoint = URL(string: "https://coinos.io/api/app/" + nwcKeypair.publicKey.hex)
        else {
            throw ClientError.errorFormingRequest
        }

        print("🔧 CoinosClient: Deleting NWC connection")
        print("🔧 CoinosClient: Using NWC keypair pubkey: \(nwcKeypair.publicKey.hex.prefix(8))...")

        try await self.loginIfNeeded()

        let (_, response) = try await self.makeAuthenticatedRequest(
            method: .delete,
            url: urlEndpoint,
            payload: nil,
            payload_type: nil
        )

        if let httpResponse = response as? HTTPURLResponse {
            print("🔧 CoinosClient: Delete response status: \(httpResponse.statusCode)")
            switch httpResponse.statusCode {
            case 200, 204:
                print("🔧 CoinosClient: Successfully deleted NWC connection")
                return
            case 401: throw ClientError.unauthorized
            case 404:
                print("🔧 CoinosClient: NWC connection not found (already deleted)")
                return
            default:
                throw ClientError.unexpectedHTTPResponse(
                    status_code: httpResponse.statusCode, response: Data())
            }
        }
        throw ClientError.errorProcessingResponse
    }

    /// Updates an existing NWC connection with a new maximum budget
    ///
    /// Note: Account and NWC connection must exist before calling this endpoint
    func updateNWCConnection(maxAmount: UInt64) async throws -> WalletConnectURL {
        guard let nwcKeypair else { throw ClientError.errorFormingRequest }
        guard let urlEndpoint = URL(string: "https://coinos.io/api/app") else {
            throw ClientError.errorFormingRequest
        }

        try await self.loginIfNeeded()

        // Get existing config first
        guard let existingConfig = try await self.getNWCAppConnectionConfig() else {
            throw ClientError.errorProcessingResponse
        }

        // Create updated config with new max amount
        let updatedConfig = NewWalletConnectionConfig(
            name: existingConfig.name ?? self.nwcConnectionName,
            secret: existingConfig.secret ?? nwcKeypair.privateKey.hex,
            pubkey: existingConfig.pubkey ?? nwcKeypair.publicKey.hex,
            max_amount: maxAmount,
            budget_renewal: .weekly
        )

        let configData = try JSONEncoder().encode(updatedConfig)

        let (data, response) = try await self.makeAuthenticatedRequest(
            method: .post,
            url: urlEndpoint,
            payload: configData,
            payload_type: .json
        )

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                guard let nwc = try await self.getNWCUrl() else {
                    throw ClientError.errorProcessingResponse
                }
                return nwc
            case 401: throw ClientError.unauthorized
            default:
                throw ClientError.unexpectedHTTPResponse(
                    status_code: httpResponse.statusCode, response: data)
            }
        }
        throw ClientError.errorProcessingResponse
    }

    /// Returns the default wallet connection config
    private func defaultWalletConnectionConfig() throws -> NewWalletConnectionConfig {
        guard let nwcKeypair else { throw ClientError.errorFormingRequest }
        return NewWalletConnectionConfig(
            name: self.nwcConnectionName,
            secret: nwcKeypair.privateKey.hex,
            pubkey: nwcKeypair.publicKey.hex,
            max_amount: 30000,  // 30K sats per week maximum
            budget_renewal: .weekly
        )
    }

    /// Gets the NWC URL for the deterministic NWC app connection
    ///
    /// Account must already exist before calling this
    ///
    /// Returns `nil` if no NWC url is found, (e.g. if app connection has not been configured yet)
    func getNWCUrl() async throws -> WalletConnectURL? {
        guard let connectionConfig = try await self.getNWCAppConnectionConfig(),
            let nwc = connectionConfig.nwc
        else { return nil }

        // CRITICAL FIX: Always generate the NWC URI with the derived secret
        // The server might have a different secret stored, but we need to use our derived secret
        return try generateNWCUrlFromConfig(connectionConfig)
    }

    /// Generates a NWC URL using the derived secret from the user's private key
    private func generateNWCUrlFromConfig(_ config: WalletConnectionConfig) throws
        -> WalletConnectURL
    {
        guard let nwcKeypair = nwcKeypair else {
            throw ClientError.errorFormingRequest
        }

        // Use the derived secret, not the one from the server
        let derivedSecret = nwcKeypair.privateKey.hex

        // CRITICAL FIX: Parse the wallet pubkey from the server's NWC URI
        // The server knows the correct wallet pubkey, so we should use it
        // We only replace the secret with our derived one
        guard let serverNwcUri = config.nwc else {
            print("❌ CoinosClient: No NWC URI in config")
            throw ClientError.errorFormingRequest
        }
        
        print("🔧 CoinosClient: Server NWC URI present, parsing...")
        
        // Parse the wallet pubkey from the server's URI
        guard let serverWalletConnectURL = WalletConnectURL(str: serverNwcUri) else {
            print("❌ CoinosClient: Failed to parse server NWC URI")
            throw ClientError.errorFormingRequest
        }
        
        let walletPubkey = serverWalletConnectURL.pubkey.hex
        print("🔧 CoinosClient: Extracted wallet pubkey from server: \(walletPubkey.prefix(8))...")

        // Construct the NWC URI string with our derived secret but the server's wallet pubkey
        let nwcUriString =
            "nostr+walletconnect://\(walletPubkey)?relay=wss://relay.coinos.io&secret=\(derivedSecret)&lud16=\(expectedLud16 ?? "unknown@coinos.io")"

        print("🔧 CoinosClient: Generated NWC URI successfully")

        guard let walletConnectURL = WalletConnectURL(str: nwcUriString) else {
            throw ClientError.errorFormingRequest
        }

        return walletConnectURL
    }

    /// Gets the deterministic NWC app connection configuration details, if it exists
    ///
    /// Account must already exist before calling this
    ///
    /// Returns `nil` if no connection is found, (e.g. if app connection has not been configured yet)
    func getNWCAppConnectionConfig() async throws -> WalletConnectionConfig? {
        print("🔍 CoinosClient: getNWCAppConnectionConfig called")
        guard let nwcKeypair else {
            print("❌ CoinosClient: nwcKeypair is nil in getNWCAppConnectionConfig")
            throw ClientError.errorFormingRequest
        }
        guard let url = URL(string: "https://coinos.io/api/app/" + nwcKeypair.publicKey.hex) else {
            print("❌ CoinosClient: Failed to create URL for getNWCAppConnectionConfig")
            throw ClientError.errorFormingRequest
        }
        print("🔍 CoinosClient: Getting NWC config from URL: \(url.absoluteString)")

        try await self.loginIfNeeded()

        let (data, response) = try await self.makeAuthenticatedRequest(
            method: .get,
            url: url,
            payload: nil,
            payload_type: nil
        )

        if let httpResponse = response as? HTTPURLResponse {
            print(
                "🔍 CoinosClient: getNWCAppConnectionConfig response status: \(httpResponse.statusCode)"
            )
            switch httpResponse.statusCode {
            case 200:
                print("🔍 CoinosClient: Successfully retrieved NWC config")
                return try JSONDecoder().decode(WalletConnectionConfig.self, from: data)
            case 401:
                print("🔍 CoinosClient: Unauthorized error in getNWCAppConnectionConfig")
                throw ClientError.unauthorized
            case 404:
                print("🔍 CoinosClient: No NWC config found (404)")
                return nil
            default:
                print(
                    "🔍 CoinosClient: Unexpected HTTP response in getNWCAppConnectionConfig: \(httpResponse.statusCode)"
                )
                print(
                    "🔍 CoinosClient: Response data: \(String(data: data, encoding: .utf8) ?? "Failed to decode")"
                )
                throw ClientError.unexpectedHTTPResponse(
                    status_code: httpResponse.statusCode, response: data)
            }
        }
        print("🔍 CoinosClient: No HTTP response in getNWCAppConnectionConfig")
        throw ClientError.errorProcessingResponse
    }

    // MARK: - Lower level request convenience functions

    /// Applies common headers (User-Agent, API key) to every outgoing Coinos request.
    private func applyCommonHeaders(to request: inout URLRequest) {
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey = CoinosSecrets.getApiKey() {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
    }

    /// Makes a request without any authorization
    func makeRequest(method: HTTPMethod, url: URL, payload: Data?, payload_type: HTTPPayloadType?)
        async throws -> (data: Data, response: URLResponse)
    {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = payload

        applyCommonHeaders(to: &request)
        if let payload_type {
            request.setValue(payload_type.rawValue, forHTTPHeaderField: "Content-Type")
        }
        return try await URLSession.shared.data(for: request)
    }

    /// Makes an authenticated request with our JWT auth token.
    ///
    /// Client must be logged-in before calling this, otherwise an error will be thrown.
    func makeAuthenticatedRequest(
        method: HTTPMethod, url: URL, payload: Data?, payload_type: HTTPPayloadType?
    ) async throws -> (data: Data, response: URLResponse) {
        guard let jwtAuthToken else { throw ClientError.errorFormingRequest }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = payload

        applyCommonHeaders(to: &request)
        request.setValue("Bearer " + jwtAuthToken, forHTTPHeaderField: "Authorization")
        if let payload_type {
            request.setValue(payload_type.rawValue, forHTTPHeaderField: "Content-Type")
        }
        return try await URLSession.shared.data(for: request)
    }

    // MARK: - Helper structures

    /// Payload for registering for a new Coinos account
    struct RegisterRequest: Codable {
        /// New user credentials
        let user: UserCredentials
    }

    /// Payload for user credentials (sign-up and login)
    struct UserCredentials: Codable {
        /// The username
        let username: String
        /// The user password
        let password: String
    }

    /// A successful response to a login auth endpoint
    struct AuthResponse: Codable {
        /// The JWT token to be applied to any authenticated API calls
        let token: String
    }

    /// Used by the client to define new NWC configurations
    struct NewWalletConnectionConfig: Codable {
        /// The name of the connection
        let name: String
        /// 32 Hex-encoded bytes containing a shared private key secret
        let secret: String
        /// 32 Hex-encoded bytes containing the pubkey for the secret
        let pubkey: String
        /// Max amount that can be spent in each renewal period (measured in sats)
        let max_amount: UInt64
        /// The period of time it takes for the budget limits to reset
        let budget_renewal: BudgetRenewalPeriod
    }

    /// The NWC connection configuration details
    ///
    /// ## Implementation notes
    ///
    /// - All items defined as optionals because the Coinos API may change in the future, so this may help increase future compatibility.
    struct WalletConnectionConfig: Codable {
        /// The name of the connection
        let name: String?
        /// 32 Hex-encoded bytes containing a shared private key secret
        let secret: String?
        /// 32 Hex-encoded bytes containing the pubkey for the secret
        let pubkey: String?
        /// Max amount that can be spent in every renewal period (measured in sats)
        let max_amount: UInt64?
        /// The NWC url generated by the server
        let nwc: String?
        /// Budget renewal information
        let budget_renewal: BudgetRenewalPeriod?
    }

    /// A period of time it takes for budget limits to be reset
    enum BudgetRenewalPeriod: String, Codable {
        /// Resets once a week
        case weekly
    }

    /// A client error occured
    enum ClientError: Error, Equatable {
        /// Received an unexpected HTTP response
        ///
        /// Could be for a variety of reasons.
        case unexpectedHTTPResponse(status_code: Int, response: Data)
        /// Error forming the request, generally due to missing or inconsistent internal data
        ///
        /// Probably caused by a programming error.
        case errorFormingRequest
        /// The client could not process the response from the server
        ///
        /// Might be a sign of an incompatibility bug
        case errorProcessingResponse
        /// The action performed is not authorized
        /// Generally thrown if user does not exist, credentials do not match what Coinos has on file, or programming error
        case unauthorized
        /// Client not logged in on a call that expected login
        case notLoggedIn
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

enum HTTPPayloadType: String {
    case json = "application/json"
    case form = "application/x-www-form-urlencoded"
}
