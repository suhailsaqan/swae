import Combine
import Foundation
import NostrSDK

// MARK: - Zap Stream Core API Models

struct ZapStreamCoreConfig {
    let baseUrl: String
    let streamTitle: String?
    let streamDescription: String?
    let isPublic: Bool

    init(
        baseUrl: String = defaultZapStreamCoreBaseUrl,
        streamTitle: String? = nil, streamDescription: String? = nil,
        isPublic: Bool = true
    ) {
        self.baseUrl = baseUrl
        self.streamTitle = streamTitle
        self.streamDescription = streamDescription
        self.isPublic = isPublic
    }
}

struct ZapStreamCoreStreamInfo: Codable {
    let id: String
    let title: String
    let description: String?
    let streamKey: String
    let rtmpUrl: String
    let srtUrl: String?
    let isLive: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct ZapStreamCoreResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
    let message: String?
}

struct ZapStreamCoreStreamResponse: Codable {
    let stream: ZapStreamCoreStreamInfo
}

struct ZapStreamCoreStreamsResponse: Codable {
    let streams: [ZapStreamCoreStreamInfo]
    let total: Int
    let page: Int
    let limit: Int
}

// MARK: - Payment Operations Models

struct ZapStreamCoreTopupResponse: Codable {
    let pr: String  // Payment request
}

struct ZapStreamCoreWithdrawRequest: Codable {
    let invoice: String  // Payment request to pay
}

struct ZapStreamCoreWithdrawResponse: Codable {
    let fee: Int
    let preimage: String
}

// Legacy models for backward compatibility (can be removed if not needed)
struct ZapStreamCoreInvoice: Codable, Equatable {
    let id: String
    let amount: Double
    let currency: String
    let status: String
    let paymentRequest: String
    let paymentHash: String
    let createdAt: Date
    let expiresAt: Date
    let paidAt: Date?

    // Original initializer for backward compatibility
    init(
        id: String,
        amount: Double,
        currency: String,
        status: String,
        paymentRequest: String,
        paymentHash: String,
        createdAt: Date,
        expiresAt: Date,
        paidAt: Date?
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.status = status
        self.paymentRequest = paymentRequest
        self.paymentHash = paymentHash
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.paidAt = paidAt
    }

    // Convenience initializer from topup response
    init(from topupResponse: ZapStreamCoreTopupResponse, amount: Double) {
        self.id = UUID().uuidString
        self.amount = amount
        self.currency = "sats"
        self.status = "pending"
        self.paymentRequest = topupResponse.pr
        self.paymentHash = ""
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(3600)  // 1 hour expiry
        self.paidAt = nil
    }
}

// Legacy models for methods that reference non-existent endpoints
struct ZapStreamCorePaymentHistoryItem: Codable, Identifiable {
    let id: String
    let amount: Double
    let currency: String
    let status: String
    let paymentRequest: String
    let paymentHash: String
    let createdAt: Date
    let paidAt: Date?
    let description: String?
}

struct ZapStreamCorePaymentHistoryResponse: Codable {
    let payments: [ZapStreamCorePaymentHistoryItem]
    let total: Int
    let page: Int
    let limit: Int
}

struct ZapStreamCoreInvoiceStatusResponse: Codable {
    let status: String
    let paid: Bool
    let amount: Double
    let currency: String
    let paidAt: Date?
}

struct ZapStreamCoreInvoiceResponse: Codable {
    let invoice: ZapStreamCoreInvoice
}

// Account History Models
struct ZapStreamCoreHistoryItem: Codable {
    let created: Int64  // Unix timestamp
    let type: Int  // 0 for credits, 1 for debits
    let amount: Double  // Amount in sats
    let desc: String?  // Description (optional since API can return null)
}

struct ZapStreamCoreHistoryResponse: Codable {
    let items: [ZapStreamCoreHistoryItem]
    let page: Int?
    let pageSize: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case page
        case pageSize = "page_size"
    }
}

struct ZapStreamCoreKeyResponse: Codable {
    let key: String
    let event: String
}

struct ZapStreamCoreAccountResponse: Codable {
    let endpoints: [ZapStreamCoreEndpoint]
    let balance: Int
    let tos: ZapStreamCoreTos?
    let forwards: [ZapStreamCoreForward]
    let details: ZapStreamCoreStreamDetails?
    let hasNwc: Bool

    enum CodingKeys: String, CodingKey {
        case endpoints, balance, tos, forwards, details
        case hasNwc = "has_nwc"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoints = (try? container.decode([ZapStreamCoreEndpoint].self, forKey: .endpoints)) ?? []
        balance = (try? container.decode(Int.self, forKey: .balance)) ?? 0
        tos = try? container.decode(ZapStreamCoreTos.self, forKey: .tos)
        forwards = (try? container.decode([ZapStreamCoreForward].self, forKey: .forwards)) ?? []
        details = try? container.decode(ZapStreamCoreStreamDetails.self, forKey: .details)
        hasNwc = (try? container.decode(Bool.self, forKey: .hasNwc)) ?? false
    }

    init(endpoints: [ZapStreamCoreEndpoint], balance: Int, tos: ZapStreamCoreTos?,
         forwards: [ZapStreamCoreForward], details: ZapStreamCoreStreamDetails?, hasNwc: Bool) {
        self.endpoints = endpoints
        self.balance = balance
        self.tos = tos
        self.forwards = forwards
        self.details = details
        self.hasNwc = hasNwc
    }
}

struct ZapStreamCoreEndpoint: Codable {
    let name: String
    let url: String
    let key: String
    let capabilities: [String]
    let cost: ZapStreamCoreCost

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        key = (try? container.decode(String.self, forKey: .key)) ?? ""
        capabilities = (try? container.decode([String].self, forKey: .capabilities)) ?? []
        cost = (try? container.decode(ZapStreamCoreCost.self, forKey: .cost))
            ?? ZapStreamCoreCost(unit: "min", rate: 0)
    }

    init(name: String, url: String, key: String, capabilities: [String], cost: ZapStreamCoreCost) {
        self.name = name
        self.url = url
        self.key = key
        self.capabilities = capabilities
        self.cost = cost
    }
}

struct ZapStreamCoreCost: Codable {
    let unit: String
    let rate: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unit = (try? container.decode(String.self, forKey: .unit)) ?? "min"
        rate = (try? container.decode(Double.self, forKey: .rate)) ?? 0
    }

    init(unit: String, rate: Double) {
        self.unit = unit
        self.rate = rate
    }
}

struct ZapStreamCoreTos: Codable {
    let accepted: Bool
    let link: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = (try? container.decode(Bool.self, forKey: .accepted)) ?? false
        link = (try? container.decode(String.self, forKey: .link)) ?? ""
    }

    init(accepted: Bool, link: String) {
        self.accepted = accepted
        self.link = link
    }
}

struct ZapStreamCoreForward: Codable {
    let id: Int
    let name: String
}

struct ZapStreamCoreStreamDetails: Codable {
    let title: String
    let summary: String
    let image: String
    let tags: [String]
    let contentWarning: String?
    let goal: String?

    enum CodingKeys: String, CodingKey {
        case title, summary, image, tags, goal
        case contentWarning = "content_warning"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        image = (try? container.decode(String.self, forKey: .image)) ?? ""
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        contentWarning = try? container.decode(String.self, forKey: .contentWarning)
        goal = try? container.decode(String.self, forKey: .goal)
    }

    init(title: String, summary: String, image: String, tags: [String],
         contentWarning: String?, goal: String?) {
        self.title = title
        self.summary = summary
        self.image = image
        self.tags = tags
        self.contentWarning = contentWarning
        self.goal = goal
    }
}

// MARK: - Zap Stream Core API Client

class ZapStreamCoreApiClient: ObservableObject {
    private let config: ZapStreamCoreConfig
    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()

    @Published var isConnected = false
    @Published var currentStream: ZapStreamCoreStreamInfo?
    @Published var error: String?
    
    // MARK: - Debug Mock Mode
    #if DEBUG
    /// Set to true to use mock responses instead of real API calls
    /// Useful when firewall blocks the API or for UI testing
    static var useMockResponses = true
    
    /// Simulated network delay for mock responses (in seconds)
    static var mockNetworkDelay: TimeInterval = 0.8
    
    /// Mock account balance in sats
    static var mockBalance: Int = 1000
    
    /// Mock streaming cost rate
    static var mockCostRate: Double = 21.0
    #endif

    init(config: ZapStreamCoreConfig) {
        self.config = config

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Mock Data Generators
    #if DEBUG
    private func mockAccountResponse() -> ZapStreamCoreAccountResponse {
        ZapStreamCoreAccountResponse(
            endpoints: [
                ZapStreamCoreEndpoint(
                    name: "RTMP Ingest",
                    url: zapStreamCoreRtmpIngestBasic,
                    key: "mock_stream_key_\(UUID().uuidString.prefix(8))",
                    capabilities: ["rtmp", "srt"],
                    cost: ZapStreamCoreCost(unit: "sats/min", rate: Self.mockCostRate)
                )
            ],
            balance: Self.mockBalance,
            tos: ZapStreamCoreTos(accepted: true, link: "https://zap.stream/tos"),
            forwards: [],
            details: ZapStreamCoreStreamDetails(
                title: "",
                summary: "",
                image: "",
                tags: [],
                contentWarning: nil,
                goal: nil
            ),
            hasNwc: false
        )
    }
    
    private func mockTimeResponse() -> String {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        return "{\"time\":\(timestamp)}"
    }
    #endif

    // MARK: - Authentication

    private func createAuthHeaders(for url: URL, method: String, keypair: Keypair) throws
        -> [String: String]
    {
        print("ZapStreamCore Creating auth headers for URL: \(url), method: \(method)")

        let authEvent = try HTTPAuthEvent.Builder()
            .url(url)
            .method(method)
            .build(signedBy: keypair)

        // Convert Nostr event to HTTP header format
        let eventJson = try JSONEncoder().encode(authEvent)
        let eventString = String(data: eventJson, encoding: .utf8) ?? ""

        print("ZapStreamCore Auth event JSON: \(eventString)")
        print("ZapStreamCore Auth event base64: \(eventString.base64Encoded())")

        var headers = [
            "Authorization": "Nostr \(eventString.base64Encoded())",
        ]

        // Only set Content-Type for methods that carry a request body
        let upperMethod = method.uppercased()
        if upperMethod == "POST" || upperMethod == "PATCH" || upperMethod == "PUT" {
            headers["Content-Type"] = "application/json"
        }

        print("ZapStreamCore Final headers: \(headers)")
        return headers
    }

    func authenticate(appState: AppState) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/account")!

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    if httpResponse.statusCode == 200 {
                        DispatchQueue.main.async {
                            self.isConnected = true
                            self.error = nil
                        }
                        promise(.success(true))
                    } else {
                        promise(.failure(ZapStreamCoreError.authenticationFailed))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func testConnection() -> AnyPublisher<String, Error> {
        #if DEBUG
        if Self.useMockResponses {
            print("ZapStreamCore [MOCK] Testing connection...")
            return Future<String, Error> { [weak self] promise in
                guard self != nil else {
                    promise(.failure(ZapStreamCoreError.invalidConfiguration))
                    return
                }
                // Simulate network delay
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.mockNetworkDelay) {
                    let mockResponse = self?.mockTimeResponse() ?? "{\"time\":0}"
                    print("ZapStreamCore [MOCK] Connection test successful: \(mockResponse)")
                    promise(.success(mockResponse))
                }
            }.eraseToAnyPublisher()
        }
        #endif
        
        return Future<String, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/time")!
            print("ZapStreamCore Testing connection to: \(url)")

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("ZapStreamCore Test Error: \(error)")
                    promise(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("ZapStreamCore Test Error: Invalid response type")
                    promise(.failure(ZapStreamCoreError.invalidResponse))
                    return
                }

                print("ZapStreamCore Test Response Status: \(httpResponse.statusCode)")

                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("ZapStreamCore Test Response: \(responseString)")
                    promise(.success(responseString))
                } else {
                    promise(.failure(ZapStreamCoreError.invalidResponse))
                }
            }.resume()
        }.eraseToAnyPublisher()
    }

    // MARK: - Account NWC Configuration

    /// Update account settings via PATCH /api/v1/account.
    /// Used to configure server-side NWC auto-topup or accept TOS.
    func updateAccount(
        appState: AppState,
        acceptTos: Bool? = nil,
        nwcUri: String? = nil,
        removeNwc: Bool? = nil
    ) -> AnyPublisher<Bool, Error> {
        #if DEBUG
        if Self.useMockResponses {
            print("ZapStreamCore [MOCK] Updating account settings...")
            return Future<Bool, Error> { promise in
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.mockNetworkDelay) {
                    print("ZapStreamCore [MOCK] Account settings updated successfully")
                    promise(.success(true))
                }
            }.eraseToAnyPublisher()
        }
        #endif

        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/account")!

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "PATCH", keypair: keypair)

                var request = URLRequest(url: url)
                request.httpMethod = "PATCH"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                var body: [String: Any] = [:]
                if let acceptTos { body["accept_tos"] = acceptTos }
                if let nwcUri { body["nwc"] = nwcUri }
                if let removeNwc { body["remove_nwc"] = removeNwc }

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                print("ZapStreamCore PATCH /api/v1/account body: \(body)")

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("ZapStreamCore PATCH account error: \(error)")
                        promise(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    print("ZapStreamCore PATCH account response: \(httpResponse.statusCode)")

                    if httpResponse.statusCode == 200 {
                        promise(.success(true))
                    } else {
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("ZapStreamCore PATCH account error response: \(responseString)")
                        }
                        promise(.failure(ZapStreamCoreError.apiError(
                            "Failed to update account (HTTP \(httpResponse.statusCode))")))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func getAccountInfo(appState: AppState) -> AnyPublisher<ZapStreamCoreAccountResponse, Error> {
        #if DEBUG
        if Self.useMockResponses {
            print("ZapStreamCore [MOCK] Getting account info...")
            return Future<ZapStreamCoreAccountResponse, Error> { [weak self] promise in
                guard let self = self else {
                    promise(.failure(ZapStreamCoreError.invalidConfiguration))
                    return
                }
                
                guard appState.keypair != nil else {
                    promise(.failure(ZapStreamCoreError.authenticationFailed))
                    return
                }
                
                // Simulate network delay
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.mockNetworkDelay) {
                    let mockResponse = self.mockAccountResponse()
                    print("ZapStreamCore [MOCK] Account info received - balance: \(mockResponse.balance) sats")
                    self.isConnected = true
                    self.error = nil
                    promise(.success(mockResponse))
                }
            }.eraseToAnyPublisher()
        }
        #endif
        
        return Future<ZapStreamCoreAccountResponse, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/account")!

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)

                print("ZapStreamCore API Request URL: \(url)")
                print("ZapStreamCore API Auth Headers: \(authHeaders)")

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("ZapStreamCore API Error: \(error)")
                        promise(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("ZapStreamCore API Error: Invalid response type")
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    print("ZapStreamCore API Response Status: \(httpResponse.statusCode)")

                    guard httpResponse.statusCode == 200 else {
                        print("ZapStreamCore API Error: HTTP \(httpResponse.statusCode)")
                        if let data = data, let responseString = String(data: data, encoding: .utf8)
                        {
                            print("ZapStreamCore API Error Response: \(responseString)")
                        }
                        promise(.failure(ZapStreamCoreError.authenticationFailed))
                        return
                    }

                    guard let data = data else {
                        print("ZapStreamCore API Error: No data received")
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    // Debug: Print raw response
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("ZapStreamCore API Raw Response: \(responseString)")
                    }

                    do {
                        let accountResponse = try JSONDecoder().decode(
                            ZapStreamCoreAccountResponse.self, from: data)

                        print("ZapStreamCore API Success: Parsed account response")
                        DispatchQueue.main.async {
                            self.isConnected = true
                            self.error = nil
                        }
                        promise(.success(accountResponse))
                    } catch let decodingError as DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("ZapStreamCore API Missing key '\(key.stringValue)' at: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                        case .valueNotFound(let type, let context):
                            print("ZapStreamCore API Null value for \(type) at: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                        case .typeMismatch(let type, let context):
                            print("ZapStreamCore API Type mismatch: expected \(type) at: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                        default:
                            print("ZapStreamCore API Decoding error: \(decodingError)")
                        }
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("ZapStreamCore API Raw Response for debugging: \(responseString)")
                        }
                        promise(.failure(decodingError))
                    } catch {
                        print("ZapStreamCore API JSON Parse Error: \(error)")
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("ZapStreamCore API Raw Response for debugging: \(responseString)")
                        }
                        promise(.failure(error))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Stream Management

    func createStream(
        appState: AppState, title: String, description: String? = nil, isPublic: Bool = true
    )
        -> AnyPublisher<ZapStreamCoreStreamInfo, Error>
    {
        return Future<ZapStreamCoreStreamInfo, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/account")!

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                // No request body needed for GET request

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    do {
                        let accountResponse = try JSONDecoder().decode(
                            ZapStreamCoreAccountResponse.self, from: data)

                        // Get the primary stream key from the first endpoint
                        guard let primaryEndpoint = accountResponse.endpoints.first else {
                            promise(
                                .failure(
                                    ZapStreamCoreError.apiError("No streaming endpoints available"))
                            )
                            return
                        }

                        // Create a stream info object from the account response
                        let streamInfo = ZapStreamCoreStreamInfo(
                            id: UUID().uuidString,  // Generate a temporary ID
                            title: title,
                            description: description ?? "",
                            streamKey: primaryEndpoint.key,
                            rtmpUrl: primaryEndpoint.url,
                            srtUrl: nil,  // SRT URL not provided in account response
                            isLive: false,
                            createdAt: Date(),
                            updatedAt: Date()
                        )

                        DispatchQueue.main.async {
                            self.currentStream = streamInfo
                            self.error = nil
                        }
                        promise(.success(streamInfo))
                    } catch let decodingError as DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("ZapStreamCore createStream Missing key '\(key.stringValue)' at: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                        case .valueNotFound(let type, let context):
                            print("ZapStreamCore createStream Null value for \(type) at: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                        case .typeMismatch(let type, let context):
                            print("ZapStreamCore createStream Type mismatch: expected \(type) at: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                        default:
                            print("ZapStreamCore createStream Decoding error: \(decodingError)")
                        }
                        promise(.failure(decodingError))
                    } catch {
                        promise(.failure(error))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func startStream(appState: AppState, streamId: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/account")!

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    if httpResponse.statusCode == 200 {
                        promise(.success(true))
                    } else {
                        promise(.failure(ZapStreamCoreError.apiError("Failed to start stream")))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func stopStream(appState: AppState, streamId: String) -> AnyPublisher<Bool, Error> {
        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/stream/\(streamId)")!

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "DELETE", keypair: keypair)

                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    if httpResponse.statusCode == 200 {
                        DispatchQueue.main.async {
                            self.currentStream = nil
                            self.error = nil
                        }
                        promise(.success(true))
                    } else {
                        promise(.failure(ZapStreamCoreError.apiError("Failed to stop stream")))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func getStream(appState: AppState, streamId: String) -> AnyPublisher<
        ZapStreamCoreStreamInfo, Error
    > {
        return Future<ZapStreamCoreStreamInfo, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/account")!

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    do {
                        let response = try JSONDecoder().decode(
                            ZapStreamCoreResponse<ZapStreamCoreStreamResponse>.self, from: data)
                        if response.success, let streamData = response.data {
                            promise(.success(streamData.stream))
                        } else {
                            promise(
                                .failure(
                                    ZapStreamCoreError.apiError(response.error ?? "Unknown error"))
                            )
                        }
                    } catch {
                        promise(.failure(error))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    func listStreams(appState: AppState, page: Int = 1, limit: Int = 20) -> AnyPublisher<
        [ZapStreamCoreStreamInfo], Error
    > {
        return Future<[ZapStreamCoreStreamInfo], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/keys")!

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    do {
                        let response = try JSONDecoder().decode(
                            ZapStreamCoreResponse<ZapStreamCoreStreamsResponse>.self, from: data)
                        if response.success, let streamsData = response.data {
                            promise(.success(streamsData.streams))
                        } else {
                            promise(
                                .failure(
                                    ZapStreamCoreError.apiError(response.error ?? "Unknown error"))
                            )
                        }
                    } catch {
                        promise(.failure(error))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Payment Operations

    /// Create a payment request for account top-up using the correct API endpoint
    func createInvoice(
        appState: AppState,
        amount: Double,
        currency: String = "sats",
        description: String? = nil
    ) -> AnyPublisher<ZapStreamCoreInvoice, Error> {
        return Future<ZapStreamCoreInvoice, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            do {
                // API expects amount in sats (not millisats despite documentation)
                let amountSats = Int(amount)
                let url = URL(
                    string: "\(self.config.baseUrl)/api/v1/topup?amount=\(amountSats)")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"

                // Add Nostr authentication headers
                guard let keypair = appState.keypair else {
                    promise(.failure(ZapStreamCoreError.authenticationFailed))
                    return
                }

                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    // Log the raw response for debugging
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("ZapStreamCore topup raw response: \(responseString)")
                    }

                    do {
                        let topupResponse = try JSONDecoder().decode(
                            ZapStreamCoreTopupResponse.self, from: data)
                        let invoice = ZapStreamCoreInvoice(from: topupResponse, amount: amount)
                        promise(.success(invoice))
                    } catch {
                        print("ZapStreamCore topup JSON decode error: \(error)")
                        // Try to decode as a simple error response
                        if let errorResponse = try? JSONDecoder().decode(
                            [String: String].self, from: data)
                        {
                            let errorMessage =
                                errorResponse["error"] ?? errorResponse["message"]
                                ?? "Unknown API error"
                            promise(.failure(ZapStreamCoreError.apiError(errorMessage)))
                        } else {
                            // Check HTTP status code for more specific error handling
                            if let httpResponse = response as? HTTPURLResponse {
                                promise(
                                    .failure(
                                        ZapStreamCoreError.apiError(
                                            "HTTP \(httpResponse.statusCode): Unable to create topup request"
                                        )))
                            } else {
                                promise(
                                    .failure(
                                        ZapStreamCoreError.apiError(
                                            "Unable to create topup request")))
                            }
                        }
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    /// Withdraw funds by paying a Lightning Network invoice
    func withdrawFunds(
        appState: AppState,
        invoice: String
    ) -> AnyPublisher<ZapStreamCoreWithdrawResponse, Error> {
        return Future<ZapStreamCoreWithdrawResponse, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            do {
                let url = URL(
                    string:
                        "\(self.config.baseUrl)/api/v1/withdraw?invoice=\(invoice.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? invoice)"
                )!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"

                // Add Nostr authentication headers
                guard let keypair = appState.keypair else {
                    promise(.failure(ZapStreamCoreError.authenticationFailed))
                    return
                }

                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "POST", keypair: keypair)
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    // Log the raw response for debugging
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("ZapStreamCore withdraw raw response: \(responseString)")
                    }

                    do {
                        let withdrawResponse = try JSONDecoder().decode(
                            ZapStreamCoreWithdrawResponse.self, from: data)
                        promise(.success(withdrawResponse))
                    } catch {
                        print("ZapStreamCore withdraw JSON decode error: \(error)")
                        // Try to decode as a simple error response
                        if let errorResponse = try? JSONDecoder().decode(
                            [String: String].self, from: data)
                        {
                            let errorMessage =
                                errorResponse["error"] ?? errorResponse["message"]
                                ?? "Unknown API error"
                            promise(.failure(ZapStreamCoreError.apiError(errorMessage)))
                        } else {
                            // Check HTTP status code for more specific error handling
                            if let httpResponse = response as? HTTPURLResponse {
                                promise(
                                    .failure(
                                        ZapStreamCoreError.apiError(
                                            "HTTP \(httpResponse.statusCode): Unable to withdraw funds"
                                        )))
                            } else {
                                promise(
                                    .failure(
                                        ZapStreamCoreError.apiError("Unable to withdraw funds")))
                            }
                        }
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    /// Get payment history
    func getPaymentHistory(
        appState: AppState,
        page: Int = 1,
        limit: Int = 20
    ) -> AnyPublisher<[ZapStreamCorePaymentHistoryItem], Error> {
        return Future<[ZapStreamCorePaymentHistoryItem], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            do {
                var urlComponents = URLComponents(string: "\(self.config.baseUrl)/api/v1/payments")!
                urlComponents.queryItems = [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "limit", value: String(limit)),
                ]

                var request = URLRequest(url: urlComponents.url!)
                request.httpMethod = "GET"

                // Add Nostr authentication headers
                guard let keypair = appState.keypair else {
                    promise(.failure(ZapStreamCoreError.authenticationFailed))
                    return
                }

                let authHeaders = try self.createAuthHeaders(
                    for: urlComponents.url!, method: "GET", keypair: keypair)
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    do {
                        let response = try JSONDecoder().decode(
                            ZapStreamCoreResponse<ZapStreamCorePaymentHistoryResponse>.self,
                            from: data)
                        if response.success, let paymentData = response.data {
                            promise(.success(paymentData.payments))
                        } else {
                            promise(
                                .failure(
                                    ZapStreamCoreError.apiError(response.error ?? "Unknown error")))
                        }
                    } catch {
                        promise(.failure(error))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    /// Check invoice status
    func getInvoiceStatus(
        appState: AppState,
        invoiceId: String
    ) -> AnyPublisher<ZapStreamCoreInvoiceStatusResponse, Error> {
        return Future<ZapStreamCoreInvoiceStatusResponse, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            do {
                let url = URL(string: "\(self.config.baseUrl)/api/v1/invoices/\(invoiceId)/status")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"

                // Add Nostr authentication headers
                guard let keypair = appState.keypair else {
                    promise(.failure(ZapStreamCoreError.authenticationFailed))
                    return
                }

                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    do {
                        let response = try JSONDecoder().decode(
                            ZapStreamCoreResponse<ZapStreamCoreInvoiceStatusResponse>.self,
                            from: data)
                        if response.success, let statusData = response.data {
                            promise(.success(statusData))
                        } else {
                            promise(
                                .failure(
                                    ZapStreamCoreError.apiError(response.error ?? "Unknown error")))
                        }
                    } catch {
                        promise(.failure(error))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    /// Get specific invoice details
    func getInvoice(
        appState: AppState,
        invoiceId: String
    ) -> AnyPublisher<ZapStreamCoreInvoice, Error> {
        return Future<ZapStreamCoreInvoice, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            do {
                let url = URL(string: "\(self.config.baseUrl)/api/v1/invoices/\(invoiceId)")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"

                // Add Nostr authentication headers
                guard let keypair = appState.keypair else {
                    promise(.failure(ZapStreamCoreError.authenticationFailed))
                    return
                }

                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    do {
                        let response = try JSONDecoder().decode(
                            ZapStreamCoreResponse<ZapStreamCoreInvoiceResponse>.self, from: data)
                        if response.success, let invoiceData = response.data {
                            promise(.success(invoiceData.invoice))
                        } else {
                            promise(
                                .failure(
                                    ZapStreamCoreError.apiError(response.error ?? "Unknown error")))
                        }
                    } catch {
                        promise(.failure(error))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    /// Get account transaction history
    func getAccountHistory(
        appState: AppState,
        page: Int = 0,
        pageSize: Int = 50
    ) -> AnyPublisher<[ZapStreamCoreHistoryItem], Error> {
        return Future<[ZapStreamCoreHistoryItem], Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            do {
                let url = URL(string: "\(self.config.baseUrl)/api/v1/history")!
                var request = URLRequest(url: url)
                request.httpMethod = "GET"

                // Add Nostr authentication headers
                guard let keypair = appState.keypair else {
                    promise(.failure(ZapStreamCoreError.authenticationFailed))
                    return
                }

                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "GET", keypair: keypair)
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    guard let data = data else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    // Log the raw response for debugging
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("ZapStreamCore history raw response (\(httpResponse.statusCode)): \(responseString)")
                    }

                    guard httpResponse.statusCode == 200 else {
                        if let errorResponse = try? JSONDecoder().decode(
                            [String: String].self, from: data)
                        {
                            let errorMessage =
                                errorResponse["error"] ?? errorResponse["message"]
                                ?? "Unknown API error"
                            promise(.failure(ZapStreamCoreError.apiError(errorMessage)))
                        } else {
                            promise(
                                .failure(
                                    ZapStreamCoreError.apiError(
                                        "HTTP \(httpResponse.statusCode): Unable to get account history"
                                    )))
                        }
                        return
                    }

                    do {
                        let historyResponse = try JSONDecoder().decode(
                            ZapStreamCoreHistoryResponse.self, from: data)
                        promise(.success(historyResponse.items))
                    } catch {
                        print("ZapStreamCore history JSON decode error: \(error)")
                        promise(.failure(ZapStreamCoreError.apiError("Failed to parse history response")))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Stream Event Metadata

    /// Update stream event metadata on the server via PATCH /api/v1/event.
    /// - If `id` is provided, updates that specific stream event.
    /// - If `id` is nil, updates the account's default stream details.
    func updateStreamEvent(
        appState: AppState,
        id: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        image: String? = nil,
        tags: [String]? = nil,
        contentWarning: String? = nil,
        goal: String? = nil
    ) -> AnyPublisher<Bool, Error> {
        #if DEBUG
        if Self.useMockResponses {
            print("ZapStreamCore [MOCK] Updating stream event metadata...")
            return Future<Bool, Error> { promise in
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.mockNetworkDelay) {
                    print("ZapStreamCore [MOCK] Stream event metadata updated successfully")
                    promise(.success(true))
                }
            }.eraseToAnyPublisher()
        }
        #endif

        return Future<Bool, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(ZapStreamCoreError.invalidConfiguration))
                return
            }

            guard let keypair = appState.keypair else {
                promise(.failure(ZapStreamCoreError.authenticationFailed))
                return
            }

            let url = URL(string: "\(self.config.baseUrl)/api/v1/event")!

            do {
                let authHeaders = try self.createAuthHeaders(
                    for: url, method: "PATCH", keypair: keypair)

                var request = URLRequest(url: url)
                request.httpMethod = "PATCH"
                for (key, value) in authHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                // Build JSON body with only non-nil fields
                var body: [String: Any] = [:]
                if let id { body["id"] = id }
                if let title { body["title"] = title }
                if let summary { body["summary"] = summary }
                if let image { body["image"] = image }
                if let tags { body["tags"] = tags }
                if let contentWarning { body["content_warning"] = contentWarning }
                if let goal { body["goal"] = goal }

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                print("ZapStreamCore PATCH /api/v1/event body: \(body)")

                self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        print("ZapStreamCore PATCH event error: \(error)")
                        promise(.failure(error))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        promise(.failure(ZapStreamCoreError.invalidResponse))
                        return
                    }

                    print("ZapStreamCore PATCH event response: \(httpResponse.statusCode)")

                    if httpResponse.statusCode == 200 {
                        promise(.success(true))
                    } else {
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("ZapStreamCore PATCH event error response: \(responseString)")
                        }
                        promise(.failure(ZapStreamCoreError.apiError(
                            "Failed to update stream event (HTTP \(httpResponse.statusCode))")))
                    }
                }.resume()
            } catch {
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }

    /// Update both the specific stream event AND the account defaults.
    func updateStreamMetadata(
        appState: AppState,
        streamEventId: String? = nil,
        title: String,
        summary: String,
        image: String,
        tags: [String],
        contentWarning: String?,
        goal: String?
    ) -> AnyPublisher<Bool, Error> {
        // Always update account defaults (no id)
        let updateDefaults = updateStreamEvent(
            appState: appState,
            title: title,
            summary: summary,
            image: image,
            tags: tags,
            contentWarning: contentWarning,
            goal: goal
        )

        guard let eventId = streamEventId else {
            return updateDefaults
        }

        // If we have a stream event id, update that too
        let updateEvent = updateStreamEvent(
            appState: appState,
            id: eventId,
            title: title,
            summary: summary,
            image: image,
            tags: tags,
            contentWarning: contentWarning,
            goal: goal
        )

        return updateDefaults
            .flatMap { _ in updateEvent }
            .eraseToAnyPublisher()
    }
}

// MARK: - Error Types

enum ZapStreamCoreError: LocalizedError {
    case invalidConfiguration
    case authenticationFailed
    case invalidResponse
    case apiError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid configuration"
        case .authenticationFailed:
            return "Authentication failed"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return "API Error: \(message)"
        case .networkError(let error):
            return "Network Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - String Extension

extension String {
    fileprivate func base64Encoded() -> String {
        return Data(self.utf8).base64EncodedString()
    }
}
