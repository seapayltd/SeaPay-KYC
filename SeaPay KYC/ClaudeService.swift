//
//  ClaudeService.swift
//  OceanCheck
//
//  Claude Vision API for intelligent document extraction.
//  Sends certificate images to Claude, gets structured JSON back.
//

import Foundation
import UIKit
import os.log

actor ClaudeService {
    static let shared = ClaudeService()

    private let endpoint = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private let logger = Logger(subsystem: "com.seapay.kyc", category: "Claude")

    private var apiKey: String {
        KeychainService.get(.claudeAPIKey) ?? ""
    }

    // MARK: - API Key Validation

    func validateAPIKey() async -> (valid: Bool, error: String?) {
        guard !apiKey.isEmpty else { return (false, "No API key set") }
        guard let url = URL(string: endpoint) else { return (false, "Invalid endpoint URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 10,
            "messages": [["role": "user", "content": "Hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return (true, nil) }
            if status == 401 { return (false, "Invalid API key") }
            if status == 403 { return (false, "API key lacks permission") }
            return (false, "API error (status \(status))")
        } catch {
            return (false, "Connection failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CoR Extraction

    struct CoRExtraction: Codable {
        var vesselName: String?
        var officialNumber: String?
        var callSign: String?
        var imoNumber: String?
        var flagState: String?
        var flagStateCode: String?
        var portOfRegistry: String?
        var vesselType: String?
        var certificateNumber: String?
        var builder: String?
        var yearBuilt: String?
        var hullMaterial: String?
        var vesselDescription: String?
        var lengthOverall: String?
        var registeredLength: String?
        var breadth: String?
        var depth: String?
        var draught: String?
        var grossTonnage: String?
        var netTonnage: String?
        var propulsionType: String?
        var engineDescription: String?
        var engineMaker: String?
        var propulsionPower: String?
        var estimatedSpeed: String?
        var registeredOwner: String?
        var ownerAddress: String?
        var registrationDate: String?
        var certificateExpiry: String?
    }

    /// Extract from raw PDF data (best quality — sends actual PDF to Claude)
    func extractCoR(pdfData: Data) async throws -> CoRExtraction {
        guard !apiKey.isEmpty else { throw ClaudeError.noAPIKey }
        await MainActor.run { APIUsageTracker.track(.claudeOCR) }
        let base64 = pdfData.base64EncodedString()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": base64]],
                    ["type": "text", "text": Self.corPrompt]
                ]
            ]]
        ]
        return try await sendAndParse(body)
    }

    /// Extract from image data (photo or rendered page)
    func extractCoR(imageData: Data) async throws -> CoRExtraction {
        guard !apiKey.isEmpty else { throw ClaudeError.noAPIKey }
        await MainActor.run { APIUsageTracker.track(.claudeOCR) }
        let base64 = imageData.base64EncodedString()
        let mediaType = detectMediaType(imageData)
        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": base64]],
                    ["type": "text", "text": Self.corPrompt]
                ]
            ]]
        ]
        return try await sendAndParse(body)
    }

    private func sendAndParse(_ body: [String: Any]) async throws -> CoRExtraction {

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        guard let url = URL(string: endpoint) else { throw ClaudeError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        request.timeoutInterval = 60

        #if DEBUG
        logger.debug("Sending request (\(jsonData.count) bytes)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("Error \(http.statusCode): \(body.prefix(300))")
            throw ClaudeError.apiError(http.statusCode, body)
        }

        // Parse the response — extract text from content[0].text, then decode JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              var text = first["text"] as? String else {
            throw ClaudeError.invalidResponse
        }

        #if DEBUG
        logger.debug("Raw response: \(text.prefix(200))")
        #endif

        // Strip markdown code blocks if present
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json") { text = String(text.dropFirst(7)) }
        if text.hasPrefix("```") { text = String(text.dropFirst(3)) }
        if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let textData = text.data(using: .utf8) else { throw ClaudeError.invalidResponse }

        let extraction = try JSONDecoder().decode(CoRExtraction.self, from: textData)
        #if DEBUG
        logger.debug("Extracted vessel: \(extraction.vesselName ?? "nil")")
        #endif
        return extraction
    }

    // MARK: - Generic Document Extraction

    func extractDocument(imageData: Data, prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.noAPIKey }
        await MainActor.run { APIUsageTracker.track(.claudeOCR) }

        let base64 = imageData.base64EncodedString()
        let mediaType = detectMediaType(imageData)
        let isPDF = mediaType == "application/pdf"

        // PDFs must use "document" type, images use "image" type
        let contentBlock: [String: Any] = isPDF
            ? ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": base64]]
            : ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": base64]]

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 4096,
            "messages": [[
                "role": "user",
                "content": [
                    contentBlock,
                    ["type": "text", "text": prompt]
                ]
            ]]
        ]

        #if DEBUG
        logger.debug("extractDocument: \(isPDF ? "PDF" : "image") (\(imageData.count) bytes)")
        #endif

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        guard let url = URL(string: endpoint) else { throw ClaudeError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("extractDocument error \(http.statusCode): \(body.prefix(200))")
            throw ClaudeError.apiError(http.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw ClaudeError.invalidResponse
        }
        #if DEBUG
        logger.debug("extractDocument response: \(text.prefix(200))")
        #endif

        return text
    }

    // MARK: - Helpers

    private func detectMediaType(_ data: Data) -> String {
        guard data.count > 4 else { return "image/jpeg" }
        let h = [UInt8](data.prefix(4))
        if h[0] == 0x89 && h[1] == 0x50 { return "image/png" }
        if h[0] == 0xFF && h[1] == 0xD8 { return "image/jpeg" }
        if h[0] == 0x25 && h[1] == 0x50 { return "application/pdf" }
        return "image/jpeg"
    }

    // MARK: - Prompt

    private static let corPrompt = """
    Extract ALL information from this Certificate of Registry (CoR) document.

    Return ONLY a JSON object (no markdown, no explanation) with these exact fields:
    {
      "vesselName": "the vessel/ship name",
      "officialNumber": "official registration number",
      "callSign": "radio call sign",
      "imoNumber": "IMO number if present",
      "flagState": "full country name (e.g. Malta)",
      "flagStateCode": "ISO 3166-1 alpha-3 code (e.g. MLT)",
      "portOfRegistry": "home port",
      "vesselType": "e.g. Pleasure Yacht, Commercial Yacht, Oil Tanker",
      "certificateNumber": "certificate number",
      "builder": "shipyard/builder name and location",
      "yearBuilt": "year",
      "hullMaterial": "e.g. GRP, Steel",
      "vesselDescription": "vessel type description from certificate",
      "lengthOverall": "Length Overall (LOA) in metres",
      "registeredLength": "Registered Length in metres (per IMO definition, distinct from LOA — often labeled 'Length (Reg.)' or 'Registered Length')",
      "breadth": "breadth in metres",
      "depth": "depth in metres",
      "draught": "draught in metres",
      "grossTonnage": "GT figure",
      "netTonnage": "NT figure",
      "propulsionType": "e.g. Motor Ship",
      "engineDescription": "e.g. Two Internal Combustion Diesel",
      "engineMaker": "engine manufacturer",
      "propulsionPower": "power in KW",
      "estimatedSpeed": "speed in knots",
      "registeredOwner": "owner name",
      "ownerAddress": "owner address",
      "registrationDate": "registration date",
      "certificateExpiry": "expiry date"
    }

    Set any field to null if not visible or not applicable. Return ONLY the JSON object.
    """

    // MARK: - JSON Schema

    private nonisolated(unsafe) static let corSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "vesselName": ["type": ["string", "null"]],
            "officialNumber": ["type": ["string", "null"]],
            "callSign": ["type": ["string", "null"]],
            "imoNumber": ["type": ["string", "null"]],
            "flagState": ["type": ["string", "null"]],
            "flagStateCode": ["type": ["string", "null"]],
            "portOfRegistry": ["type": ["string", "null"]],
            "vesselType": ["type": ["string", "null"]],
            "certificateNumber": ["type": ["string", "null"]],
            "builder": ["type": ["string", "null"]],
            "yearBuilt": ["type": ["string", "null"]],
            "hullMaterial": ["type": ["string", "null"]],
            "vesselDescription": ["type": ["string", "null"]],
            "lengthOverall": ["type": ["string", "null"]],
            "registeredLength": ["type": ["string", "null"]],
            "breadth": ["type": ["string", "null"]],
            "depth": ["type": ["string", "null"]],
            "draught": ["type": ["string", "null"]],
            "grossTonnage": ["type": ["string", "null"]],
            "netTonnage": ["type": ["string", "null"]],
            "propulsionType": ["type": ["string", "null"]],
            "engineDescription": ["type": ["string", "null"]],
            "engineMaker": ["type": ["string", "null"]],
            "propulsionPower": ["type": ["string", "null"]],
            "estimatedSpeed": ["type": ["string", "null"]],
            "registeredOwner": ["type": ["string", "null"]],
            "ownerAddress": ["type": ["string", "null"]],
            "registrationDate": ["type": ["string", "null"]],
            "certificateExpiry": ["type": ["string", "null"]],
        ],
        "required": ["vesselName", "flagState", "flagStateCode"],
        "additionalProperties": false
    ]
}

// MARK: - Errors

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { (self ?? "").isEmpty }
}

enum ClaudeError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Claude API key not set. Add it in Settings."
        case .invalidResponse: return "Invalid response from Claude."
        case .apiError(let code, let msg): return "Claude API error (\(code)): \(msg.prefix(100))"
        }
    }
}
