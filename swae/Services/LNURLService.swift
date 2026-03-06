//
//  LNURLService.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import Combine
import Foundation

/// Service for handling LNURL pay requests and Lightning address operations
class LNURLService: ObservableObject {
    @Published var isProcessing = false
    @Published var error: String?

    private let session = URLSession.shared

    /// LNURL Pay Request Response
    struct LNURLPayRequestResponse: Codable {
        let callback: String
        let maxSendable: Int64?
        let minSendable: Int64?
        let metadata: String
        let commentAllowed: Int?
        let tag: String

        enum CodingKeys: String, CodingKey {
            case callback
            case maxSendable = "maxSendable"
            case minSendable = "minSendable"
            case metadata
            case commentAllowed = "commentAllowed"
            case tag
        }
    }

    /// LNURL Pay Response
    struct LNURLPayResponse: Codable {
        let pr: String  // bolt11 invoice
        let routes: [[String]]?
        let disposable: Bool?
        let successAction: SuccessAction?

        enum CodingKeys: String, CodingKey {
            case pr
            case routes
            case disposable
            case successAction = "successAction"
        }
    }

    /// Success Action for LNURL
    struct SuccessAction: Codable {
        let tag: String
        let description: String?
        let url: String?
    }

    /// LNURL Metadata
    struct LNURLMetadata: Codable {
        let textPlain: String?
        let textLongDesc: String?
        let imagePngDataURI: String?
        let imageJpegDataURI: String?

        enum CodingKeys: String, CodingKey {
            case textPlain = "text/plain"
            case textLongDesc = "text/long-desc"
            case imagePngDataURI = "image/png;base64"
            case imageJpegDataURI = "image/jpeg;base64"
        }
    }

    /// Fetches LNURL pay request from a Lightning address
    /// - Parameter lightningAddress: The Lightning address (e.g., "user@domain.com")
    /// - Returns: LNURLPayRequestResponse or nil if failed
    func fetchLNURLPayRequest(from lightningAddress: String) async -> LNURLPayRequestResponse? {
        await MainActor.run {
            isProcessing = true
            error = nil
        }

        do {
            // Step 1: Decode Lightning address to get LNURL
            guard let lnurl = decodeLightningAddress(lightningAddress) else {
                await MainActor.run {
                    error = "Invalid Lightning address format"
                    isProcessing = false
                }
                return nil
            }

            // Step 2: Fetch LNURL pay request
            guard let url = URL(string: lnurl) else {
                await MainActor.run {
                    error = "Invalid LNURL"
                    isProcessing = false
                }
                return nil
            }

            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                await MainActor.run {
                    error = "Failed to fetch LNURL pay request"
                    isProcessing = false
                }
                return nil
            }

            let payRequest = try JSONDecoder().decode(LNURLPayRequestResponse.self, from: data)

            await MainActor.run {
                isProcessing = false
            }

            return payRequest

        } catch let fetchError {
            await MainActor.run {
                error = "Error fetching LNURL pay request: \(fetchError.localizedDescription)"
                isProcessing = false
            }
            return nil
        }
    }

    /// Creates a Lightning invoice via LNURL pay
    /// - Parameters:
    ///   - payRequest: The LNURL pay request response
    ///   - amount: Amount in millisats
    ///   - comment: Optional comment
    ///   - zapRequest: The zap request event (JSON encoded)
    /// - Returns: LNURLPayResponse with bolt11 invoice or nil if failed
    func createInvoice(
        from payRequest: LNURLPayRequestResponse,
        amount: Int64,
        comment: String? = nil,
        zapRequest: String
    ) async -> LNURLPayResponse? {
        await MainActor.run {
            isProcessing = true
            error = nil
        }

        do {
            // Validate amount constraints
            if let minSendable = payRequest.minSendable, amount < minSendable {
                await MainActor.run {
                    error = "Amount too small. Minimum: \(minSendable) millisats"
                    isProcessing = false
                }
                return nil
            }

            if let maxSendable = payRequest.maxSendable, amount > maxSendable {
                await MainActor.run {
                    error = "Amount too large. Maximum: \(maxSendable) millisats"
                    isProcessing = false
                }
                return nil
            }

            // Build callback URL with parameters
            var components = URLComponents(string: payRequest.callback)
            components?.queryItems = [
                URLQueryItem(name: "amount", value: String(amount)),
                URLQueryItem(name: "nostr", value: zapRequest),
            ]

            if let comment = comment, let commentAllowed = payRequest.commentAllowed,
                comment.count <= commentAllowed
            {
                components?.queryItems?.append(URLQueryItem(name: "comment", value: comment))
            }

            guard let callbackURL = components?.url else {
                await MainActor.run {
                    error = "Invalid callback URL"
                    isProcessing = false
                }
                return nil
            }

            // Make the callback request
            let (data, response) = try await session.data(from: callbackURL)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                await MainActor.run {
                    error = "Failed to create invoice"
                    isProcessing = false
                }
                return nil
            }

            let payResponse = try JSONDecoder().decode(LNURLPayResponse.self, from: data)

            await MainActor.run {
                isProcessing = false
            }

            return payResponse

        } catch let invoiceError {
            await MainActor.run {
                error = "Error creating invoice: \(invoiceError.localizedDescription)"
                isProcessing = false
            }
            return nil
        }
    }

    /// Decodes a Lightning address to LNURL
    /// - Parameter lightningAddress: The Lightning address (e.g., "user@domain.com")
    /// - Returns: The LNURL or nil if invalid
    private func decodeLightningAddress(_ lightningAddress: String) -> String? {
        // Split by @ to get user and domain
        let components = lightningAddress.components(separatedBy: "@")
        guard components.count == 2 else { return nil }

        let user = components[0]
        let domain = components[1]

        // Create LNURL by prepending "https://" to domain and appending user
        return "https://\(domain)/.well-known/lnurlp/\(user)"
    }

    /// Parses LNURL metadata
    /// - Parameter metadataString: JSON string containing metadata
    /// - Returns: Parsed LNURLMetadata or nil if failed
    func parseMetadata(_ metadataString: String) -> LNURLMetadata? {
        guard let data = metadataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LNURLMetadata.self, from: data)
    }
}
