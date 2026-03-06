//
//  NostrBuildUploadService.swift
//  swae
//
//  Uploads images to nostr.build v2 API with NIP-98 authentication.
//

import Foundation
import NostrSDK

// MARK: - Upload Result

struct NostrBuildUploadResult {
    let url: URL
    let sha256: String?
    let mimeType: String?
    let dimensions: String?
    let size: Int?
    let blurhash: String?
}

// MARK: - Upload Error

enum NostrBuildUploadError: LocalizedError {
    case invalidImageData
    case uploadFailed(String)
    case invalidResponse
    case fileTooLarge
    case unauthorized
    case noNetwork

    var errorDescription: String? {
        switch self {
        case .invalidImageData: return "Invalid image data."
        case .uploadFailed(let msg): return msg
        case .invalidResponse: return "Could not parse server response."
        case .fileTooLarge: return "Image is too large (max 10 MB)."
        case .unauthorized: return "Authentication failed."
        case .noNetwork: return "No internet connection."
        }
    }
}

// MARK: - Service

final class NostrBuildUploadService {

    static let shared = NostrBuildUploadService()
    private let endpoint = URL(string: "https://nostr.build/api/v2/upload/files")!

    private init() {}

    /// Uploads image data to nostr.build.
    func upload(
        imageData: Data,
        mimeType: String,
        filename: String,
        keypair: Keypair?
    ) async throws -> NostrBuildUploadResult {
        guard !imageData.isEmpty else { throw NostrBuildUploadError.invalidImageData }
        guard imageData.count <= 10_000_000 else { throw NostrBuildUploadError.fileTooLarge }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        // NIP-98 auth header
        if let keypair {
            let authHeader = try buildAuthHeader(keypair: keypair)
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        // Multipart body
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
            throw NostrBuildUploadError.noNetwork
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NostrBuildUploadError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200: break
        case 401, 403: throw NostrBuildUploadError.unauthorized
        case 413: throw NostrBuildUploadError.fileTooLarge
        default:
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw NostrBuildUploadError.uploadFailed(serverMessage ?? "Server returned \(httpResponse.statusCode)")
        }

        return try parseResponse(data)
    }

    // MARK: - Private

    private func buildAuthHeader(keypair: Keypair) throws -> String {
        let authEvent = try HTTPAuthEvent.Builder()
            .url(endpoint)
            .method("POST")
            .build(signedBy: keypair)

        let jsonData = try JSONEncoder().encode(authEvent)
        let base64 = jsonData.base64EncodedString()
        return "Nostr \(base64)"
    }

    private func parseResponse(_ data: Data) throws -> NostrBuildUploadResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw NostrBuildUploadError.invalidResponse
        }

        if status == "error" {
            let message = json["message"] as? String ?? "Upload failed."
            throw NostrBuildUploadError.uploadFailed(message)
        }

        // v2 API returns data as an array of file objects
        if let dataArray = json["data"] as? [[String: Any]], let file = dataArray.first {
            guard let urlStr = file["url"] as? String, let url = URL(string: urlStr) else {
                throw NostrBuildUploadError.invalidResponse
            }

            let dims = file["dimensions"] as? [String: Any]
            let dimString = file["dimensionsString"] as? String
                ?? dims.map { "\(Int($0["width"] as? Int ?? 0))x\(Int($0["height"] as? Int ?? 0))" }

            return NostrBuildUploadResult(
                url: url,
                sha256: file["original_sha256"] as? String ?? file["sha256"] as? String,
                mimeType: file["mime"] as? String,
                dimensions: dimString,
                size: file["size"] as? Int,
                blurhash: file["blurhash"] as? String
            )
        }

        // Fallback: nip94_event format (some endpoints may still use this)
        if let nip94 = json["nip94_event"] as? [String: Any],
           let tags = nip94["tags"] as? [[String]] {
            return try parseNip94Tags(tags)
        }

        throw NostrBuildUploadError.invalidResponse
    }

    private func parseNip94Tags(_ tags: [[String]]) throws -> NostrBuildUploadResult {
        var urlString: String?
        var sha256: String?
        var mime: String?
        var dim: String?
        var size: Int?
        var blurhash: String?

        for tag in tags {
            guard tag.count >= 2 else { continue }
            switch tag[0] {
            case "url": urlString = tag[1]
            case "ox": sha256 = tag[1]
            case "m": mime = tag[1]
            case "dim": dim = tag[1]
            case "size": size = Int(tag[1])
            case "blurhash": blurhash = tag[1]
            default: break
            }
        }

        guard let urlStr = urlString, let url = URL(string: urlStr) else {
            throw NostrBuildUploadError.invalidResponse
        }

        return NostrBuildUploadResult(
            url: url,
            sha256: sha256,
            mimeType: mime,
            dimensions: dim,
            size: size,
            blurhash: blurhash
        )
    }
}

// MARK: - Data + Append String

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
