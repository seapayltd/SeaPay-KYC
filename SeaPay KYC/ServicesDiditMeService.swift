//
//  VerificationAPIService.swift
//  SeaPay KYC
//
//  Standalone verification API v3
//  All endpoints use x-api-key header + accept: application/json
//

import Foundation
import os

actor VerificationAPIService {
    static let shared = VerificationAPIService()

    private let network = NetworkService.shared
    private let baseURL = AppConfiguration.verificationBaseURL
    private let apiLogger = Logger(subsystem: "com.seapay.kyc", category: "API")

    private func key() throws -> String {
        let k = AppConfiguration.apiKey
        guard !k.isEmpty else {
            throw AppError.missingRequiredField("API Key — go to Settings and enter your key")
        }
        return k
    }

    // MARK: - ID Verification

    func verifyID(
        frontImage: Data,
        backImage: Data? = nil,
        vendorData: String? = nil,
        documentLiveness: Bool = true
    ) async throws -> (IDVerificationResponse, Data) {
        let apiKey = try key()
        guard let url = URL(string: "\(baseURL)/id-verification/") else { throw AppError.invalidURL }

        apiLogger.info("ID verification — front: \(frontImage.count) bytes, back: \(backImage?.count ?? 0) bytes")

        var fields: [(name: String, value: String)] = [
            ("perform_document_liveness", documentLiveness ? "true" : "false"),
            ("expiration_date_not_detected_action", "NO_ACTION"),
            ("invalid_mrz_action", "NO_ACTION"),
            ("inconsistent_data_action", "NO_ACTION")
        ]
        if let v = vendorData { fields.append(("vendor_data", v)) }

        var files: [(name: String, filename: String, mimeType: String, data: Data)] = [
            ("front_image", "front.jpg", "image/jpeg", frontImage)
        ]
        if let b = backImage { files.append(("back_image", "back.jpg", "image/jpeg", b)) }

        let (data, _) = try await network.performMultipart(
            url: url, fields: fields, files: files, token: apiKey, isAPIKey: true
        )

        do {
            let decoded = try JSONDecoder().decode(IDVerificationResponse.self, from: data)
            apiLogger.info("ID result: \(decoded.idVerification?.status ?? "no status"), type: \(decoded.idVerification?.documentType ?? "unknown")")
            return (decoded, data)
        } catch {
            let raw = String(data: data.prefix(300), encoding: .utf8) ?? ""
            apiLogger.error("Failed to decode ID response: \(error.localizedDescription)\nRaw: \(raw)")
            throw AppError.verificationFailed("Could not parse ID verification response. Raw: \(raw.prefix(100))")
        }
    }

    // MARK: - AML Screening

    struct AMLOptions {
        var includeAdverseMedia: Bool = true
        var includeMonitoring: Bool = false
        var approveThreshold: Int = 80
        var reviewThreshold: Int = 100
        var matchScoreThreshold: Int = 93
    }

    func screenAML(
        fullName: String,
        dateOfBirth: String? = nil,
        nationality: String? = nil,
        documentNumber: String? = nil,
        vendorData: String? = nil,
        options: AMLOptions = AMLOptions()
    ) async throws -> (AMLScreeningResponse, Data) {
        let apiKey = try key()
        guard let url = URL(string: "\(baseURL)/aml/") else { throw AppError.invalidURL }

        apiLogger.info("AML screening for: \(fullName), monitoring: \(options.includeMonitoring)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        var payload: [String: Any] = [
            "full_name": fullName,
            "entity_type": "person",
            "include_adverse_media": options.includeAdverseMedia,
            "include_ongoing_monitoring": options.includeMonitoring,
            "save_api_request": true,
            "aml_score_approve_threshold": options.approveThreshold,
            "aml_score_review_threshold": options.reviewThreshold,
            "aml_match_score_threshold": options.matchScoreThreshold
        ]
        if let v = dateOfBirth { payload["date_of_birth"] = v }
        if let v = nationality { payload["nationality"] = v }
        if let v = documentNumber { payload["document_number"] = v }
        if let v = vendorData { payload["vendor_data"] = v }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await network.perform(request)

        do {
            let decoded = try JSONDecoder().decode(AMLScreeningResponse.self, from: data)
            apiLogger.info("AML result: \(decoded.aml?.status ?? "no status"), score: \(decoded.aml?.score ?? -1)")
            return (decoded, data)
        } catch {
            let raw = String(data: data.prefix(300), encoding: .utf8) ?? ""
            apiLogger.error("Failed to decode AML response: \(error.localizedDescription)\nRaw: \(raw)")
            throw AppError.verificationFailed("Could not parse AML response. Raw: \(raw.prefix(100))")
        }
    }

    // MARK: - Proof of Address

    func verifyAddress(
        document: Data,
        expectedName: String? = nil,
        expectedAddress: String? = nil,
        vendorData: String? = nil
    ) async throws -> (PoAResponse, Data) {
        let apiKey = try key()
        guard let url = URL(string: "\(baseURL)/poa/") else { throw AppError.invalidURL }

        // Detect file type from magic bytes
        let (filename, mime) = detectFileType(document)
        apiLogger.info("PoA verification — doc: \(document.count) bytes, type: \(mime)")

        var fields: [(name: String, value: String)] = []
        if let v = expectedName {
            let parts = v.split(separator: " ", maxSplits: 1)
            if parts.count >= 1 { fields.append(("expected_first_name", String(parts[0]))) }
            if parts.count >= 2 { fields.append(("expected_last_name", String(parts[1]))) }
        }
        if let v = expectedAddress { fields.append(("expected_address", v)) }
        if let v = vendorData { fields.append(("vendor_data", v)) }

        let files: [(name: String, filename: String, mimeType: String, data: Data)] = [
            ("document", filename, mime, document)
        ]

        let (data, _) = try await network.performMultipart(
            url: url, fields: fields, files: files, token: apiKey, isAPIKey: true
        )

        do {
            let decoded = try JSONDecoder().decode(PoAResponse.self, from: data)
            apiLogger.info("PoA result: \(decoded.poa?.status ?? "no status")")
            return (decoded, data)
        } catch {
            let raw = String(data: data.prefix(300), encoding: .utf8) ?? ""
            apiLogger.error("Failed to decode PoA response: \(error.localizedDescription)\nRaw: \(raw)")
            throw AppError.verificationFailed("Could not parse PoA response. Raw: \(raw.prefix(100))")
        }
    }

    // MARK: - Face Match

    func matchFace(
        userImage: Data,
        refImage: Data,
        vendorData: String? = nil
    ) async throws -> (FaceMatchResponse, Data) {
        let apiKey = try key()
        guard let url = URL(string: "\(baseURL)/face-match/") else { throw AppError.invalidURL }

        var fields: [(name: String, value: String)] = []
        if let v = vendorData { fields.append(("vendor_data", v)) }

        let files: [(name: String, filename: String, mimeType: String, data: Data)] = [
            ("user_image", "user.jpg", "image/jpeg", userImage),
            ("ref_image", "ref.jpg", "image/jpeg", refImage)
        ]

        let (data, _) = try await network.performMultipart(
            url: url, fields: fields, files: files, token: apiKey, isAPIKey: true
        )

        do {
            let decoded = try JSONDecoder().decode(FaceMatchResponse.self, from: data)
            return (decoded, data)
        } catch {
            let raw = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw AppError.verificationFailed("Could not parse face match response. Raw: \(raw.prefix(100))")
        }
    }

    // MARK: - Validate Key (lightweight, no credits)

    /// Sends a minimal request to check if the API key is valid.
    /// Uses a HEAD-like approach — a malformed request that returns 400 (valid key) vs 401 (invalid key).
    func validateAPIKey() async throws {
        let apiKey = try key()
        guard let url = URL(string: "\(baseURL)/aml/") else { throw AppError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        // Send empty body — will get 400 (key is valid) or 401 (key is invalid)
        request.httpBody = "{}".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }

            switch http.statusCode {
            case 200...299, 400, 422:
                // Key is valid (400/422 = bad request body, but auth passed)
                return
            case 401:
                throw AppError.unauthorized
            case 403:
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AppError.insufficientCredits(body)
            default:
                throw AppError.serverError(http.statusCode, String(data: data, encoding: .utf8))
            }
        }
    }

    // MARK: - Session-Based Flow (for invites)

    /// Creates a hosted verification session. Returns session ID + verification URL.
    func createSession(workflowID: String, vendorData: String? = nil, callbackURL: String? = nil) async throws -> SessionResponse {
        let apiKey = try key()
        guard let url = URL(string: "\(baseURL)/session/") else { throw AppError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        var payload: [String: Any] = ["workflow_id": workflowID]
        if let v = vendorData { payload["vendor_data"] = v }
        if let c = callbackURL { payload["callback"] = c }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        apiLogger.info("Creating session for workflow: \(workflowID)")
        let (data, _) = try await network.perform(request)
        return try JSONDecoder().decode(SessionResponse.self, from: data)
    }

    /// Retrieves decision for a completed session.
    func getSessionDecision(sessionId: String) async throws -> SessionDecision {
        let apiKey = try key()
        guard let url = URL(string: "\(baseURL)/session/\(sessionId)/decision/") else { throw AppError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let (data, _) = try await network.perform(request)
        return try JSONDecoder().decode(SessionDecision.self, from: data)
    }

    // MARK: - File Type Detection

    /// Detects file type from magic bytes and returns (filename, mimeType).
    private func detectFileType(_ data: Data) -> (String, String) {
        guard data.count > 4 else { return ("document.bin", "application/octet-stream") }
        let h = [UInt8](data.prefix(8))

        // PDF: %PDF
        if h[0] == 0x25 && h[1] == 0x50 && h[2] == 0x44 && h[3] == 0x46 {
            return ("document.pdf", "application/pdf")
        }
        // PNG: 89 50 4E 47
        if h[0] == 0x89 && h[1] == 0x50 && h[2] == 0x4E && h[3] == 0x47 {
            return ("document.png", "image/png")
        }
        // JPEG: FF D8 FF
        if h[0] == 0xFF && h[1] == 0xD8 && h[2] == 0xFF {
            return ("document.jpg", "image/jpeg")
        }
        // TIFF: 49 49 or 4D 4D
        if (h[0] == 0x49 && h[1] == 0x49) || (h[0] == 0x4D && h[1] == 0x4D) {
            return ("document.tiff", "image/tiff")
        }
        // WebP: RIFF....WEBP
        if h[0] == 0x52 && h[1] == 0x49 && h[2] == 0x46 && h[3] == 0x46 && data.count > 12 {
            let webp = [UInt8](data[8..<12])
            if webp == [0x57, 0x45, 0x42, 0x50] { return ("document.webp", "image/webp") }
        }

        // Default to JPEG (most common for camera captures)
        return ("document.jpg", "image/jpeg")
    }
}
