//
//  NetworkService.swift
//  SeaPay KYC
//
//  Centralized networking with retry, error parsing, debug logging
//

import Foundation
import os

actor NetworkService {
    static let shared = NetworkService()

    private let session: URLSession
    private let maxRetries = 2
    private let baseRetryDelay: TimeInterval = 1.5
    private let networkLogger = Logger(subsystem: "com.seapay.kyc", category: "Network")

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: config)
    }

    // MARK: - JSON Request

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var req = request
        // Always expect JSON back
        if req.value(forHTTPHeaderField: "accept") == nil {
            req.setValue("application/json", forHTTPHeaderField: "accept")
        }

        #if DEBUG
        logRequest(req)
        #endif

        return try await performWithRetry(req, attempt: 0)
    }

    // MARK: - Multipart Request

    func performMultipart(
        url: URL,
        fields: [(name: String, value: String)],
        files: [(name: String, filename: String, mimeType: String, data: Data)],
        token: String,
        isAPIKey: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.timeoutInterval = 180

        if isAPIKey {
            request.setValue(token, forHTTPHeaderField: "x-api-key")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        for field in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            body.append("\(field.value)\r\n")
        }
        for file in files {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        #if DEBUG
        networkLogger.info("MULTIPART \(url.absoluteString) — \(fields.count) fields, \(files.count) files (\(body.count) bytes)")
        #endif

        return try await perform(request)
    }

    // MARK: - Retry Logic

    private func performWithRetry(_ request: URLRequest, attempt: Int) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw AppError.invalidResponse
            }

            #if DEBUG
            logResponse(http, data: data)
            #endif

            switch http.statusCode {
            case 200...299:
                return (data, http)

            case 400:
                // Client error — don't retry, surface the API message
                throw AppError.apiClientError(http.statusCode, parseBody(data))

            case 401:
                throw AppError.unauthorized

            case 403:
                throw AppError.insufficientCredits(parseBody(data))

            case 429:
                if attempt < maxRetries {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performWithRetry(request, attempt: attempt + 1)
                }
                throw AppError.rateLimited

            case 500...599:
                if attempt < maxRetries {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performWithRetry(request, attempt: attempt + 1)
                }
                throw AppError.serverError(http.statusCode, parseBody(data))

            default:
                throw AppError.serverError(http.statusCode, parseBody(data))
            }
        } catch let error as AppError {
            throw error
        } catch {
            if attempt < maxRetries, (error as NSError).domain == NSURLErrorDomain {
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performWithRetry(request, attempt: attempt + 1)
            }
            throw AppError.network(error)
        }
    }

    // MARK: - Error Parsing

    private func parseBody(_ data: Data) -> String {
        // Try JSON first — Didit uses "detail", "error", or "message"
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? String { return detail }
            if let error = json["error"] as? String { return error }
            if let message = json["message"] as? String { return message }
            // Array of errors
            if let detail = json["detail"] as? [[String: Any]],
               let first = detail.first, let msg = first["msg"] as? String { return msg }
        }
        // Fallback to raw text
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    // MARK: - Debug Logging

    #if DEBUG
    private func logRequest(_ req: URLRequest) {
        let method = req.httpMethod ?? "?"
        let url = req.url?.absoluteString ?? "?"
        let headers = req.allHTTPHeaderFields?.filter { $0.key != "x-api-key" } ?? [:]
        let hasKey = req.value(forHTTPHeaderField: "x-api-key") != nil
        networkLogger.info("→ \(method) \(url)\n  headers: \(headers)\(hasKey ? " +x-api-key" : "")\n  body: \(req.httpBody?.count ?? 0) bytes")
    }

    private func logResponse(_ http: HTTPURLResponse, data: Data) {
        let url = http.url?.absoluteString ?? "?"
        let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
        networkLogger.info("← \(http.statusCode) \(url)\n  body: \(preview)")
    }
    #endif
}

// MARK: - Error Types

enum AppError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case insufficientCredits(String)
    case rateLimited
    case apiClientError(Int, String)
    case serverError(Int, String?)
    case network(Error)
    case invalidCredentials
    case signupFailed(String?)
    case notAuthenticated
    case imageTooLarge(Int)
    case invalidImageFormat
    case imageTooSmall(Int, Int)
    case missingRequiredField(String)
    case verificationFailed(String)
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Invalid API Key. Check your key in Settings."
        case .insufficientCredits(let detail):
            return "Insufficient API credits. \(detail)"
        case .rateLimited:
            return "Rate limited. Wait a moment and try again."
        case .apiClientError(let code, let detail):
            return "Request rejected (\(code)): \(detail)"
        case .serverError(let code, let msg):
            return "Server error (\(code))\(msg.map { ": \($0)" } ?? "")"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidCredentials:
            return "Invalid email or password"
        case .signupFailed(let reason):
            return reason ?? "Failed to create account"
        case .notAuthenticated:
            return "Please sign in to continue"
        case .imageTooLarge(let maxMB):
            return "Image exceeds \(maxMB)MB limit"
        case .invalidImageFormat:
            return "Use JPEG or PNG format"
        case .imageTooSmall(let w, let h):
            return "Image must be at least \(w)x\(h) pixels"
        case .missingRequiredField(let field):
            return "\(field) is required"
        case .verificationFailed(let reason):
            return reason
        case .sessionExpired:
            return "Session expired. Please start again."
        }
    }
}

// MARK: - Data Helper

extension Data {
    nonisolated mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
