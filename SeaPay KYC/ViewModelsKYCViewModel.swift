//
//  KYCViewModel.swift
//  SeaPay KYC
//
//  Pipeline: Scan ID → AML → optional PoA → PDF
//

import Foundation
import Combine
import SwiftUI
import CoreLocation

@MainActor
class KYCViewModel: ObservableObject {
    @Published var checks: [KYCCheck] = []

    private let api = VerificationAPIService.shared

    // MARK: - Storage

    private var docsDir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first! }
    private var checksFile: URL { docsDir.appendingPathComponent("kyc_checks.json") }
    var imagesDir: URL {
        let d = docsDir.appendingPathComponent("captured_documents")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    private var reportsDir: URL {
        let d = docsDir.appendingPathComponent("reports")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: checksFile) else { return }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        checks = (try? d.decode([KYCCheck].self, from: data)) ?? []
    }

    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        try? e.encode(checks).write(to: checksFile)
        // Force SwiftUI to re-render — mutating array elements in place
        // doesn't trigger @Published because the array identity hasn't changed
        objectWillChange.send()
    }

    // MARK: - Create

    func createCheck(customerName: String, docType: KYCCheck.IDDocType? = nil) -> KYCCheck {
        // One-shot location
        let lm = CLLocationManager()
        lm.requestWhenInUseAuthorization()
        let loc = lm.location

        let check = KYCCheck(
            id: UUID().uuidString,
            customerId: "",
            customerName: customerName,
            agentId: "",
            agentName: UserDefaults.standard.string(forKey: "agentName") ?? "Agent",
            checkType: .idVerification,
            status: .pending,
            createdAt: Date(),
            latitude: loc?.coordinate.latitude,
            longitude: loc?.coordinate.longitude,
            expectedDocType: docType
        )
        checks.insert(check, at: 0); save()
        return check
    }

    // MARK: - Invite Flow (session-based)

    func createInviteSession(checkId: String) async throws -> (sessionId: String, qrURL: String, verifyURL: String) {
        guard let i = idx(checkId) else { throw AppError.verificationFailed("Check not found") }
        let wf = AppConfiguration.workflowID
        guard !wf.isEmpty else { throw AppError.missingRequiredField("Workflow ID — configure it in Settings") }

        let agent = UserDefaults.standard.string(forKey: "agentName") ?? "Agent"
        let ref = "OC-\(String(checks[i].id.prefix(8)).uppercased())"

        let session = try await api.createSession(workflowID: wf, vendorData: checks[i].customerName)
        let sessionId = session.sessionId

        checks[i].status = .inProgress
        save()

        // Build the deep link for QR
        let qrURL = "\(AppConfiguration.urlScheme)://verify?session=\(sessionId)&agent=\(agent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&ref=\(ref)"

        // The hosted verification URL (fallback for non-app users)
        let verifyURL = session.url ?? ""

        return (sessionId, qrURL, verifyURL)
    }

    func pollSessionDecision(checkId: String, sessionId: String) async throws -> SessionDecision {
        let decision = try await api.getSessionDecision(sessionId: sessionId)

        if let i = idx(checkId) {
            switch decision.status {
            case "Approved": checks[i].status = .passed
            case "Declined": checks[i].status = .failed
            default: break // still in progress
            }

            // Extract data from decision
            if let idResult = decision.idVerifications?.first {
                checks[i].extractedName = idResult.extractedFullName
                checks[i].documentType = idResult.documentType
                checks[i].documentNumber = idResult.documentNumber
                checks[i].dateOfBirth = idResult.dateOfBirth
                checks[i].nationality = idResult.nationality
            }
            if let amlResult = decision.aml?.first {
                checks[i].amlStatus = amlResult.status
                checks[i].amlScore = amlResult.score
                checks[i].amlHitCount = amlResult.totalHits
            }

            if decision.status == "Approved" || decision.status == "Declined" {
                checks[i].completedAt = Date()
            }
            save()
        }

        return decision
    }

    func configureCheck(checkId: String, docType: KYCCheck.IDDocType, depth: KYCCheck.InvestigationDepth) {
        guard let i = idx(checkId) else { return }
        checks[i].expectedDocType = docType
        checks[i].investigationDepth = depth
        save()
    }

    // MARK: - Pipeline: ID + AML

    struct IDScanResult {
        let idResult: IDResult?
        let nameMismatch: (entered: String, extracted: String)?
        let isExpired: Bool
    }

    /// Step 1: ID scan only. Sets status to inProgress, stores results, does NOT set final status.
    func runIDScan(checkId: String, frontImage: Data, backImage: Data?) async throws -> IDScanResult {
        guard let i = idx(checkId) else { throw AppError.verificationFailed("Check not found") }

        checks[i].status = .inProgress; save()
        _ = saveImages(checkId: checkId, front: frontImage, back: backImage)

        let (idResp, idRaw) = try await api.verifyID(frontImage: frontImage, backImage: backImage, vendorData: checkId)
        let id = idResp.idVerification

        checks[i].extractedName = id?.extractedFullName
        checks[i].documentType = id?.documentType
        checks[i].documentNumber = id?.documentNumber
        checks[i].dateOfBirth = id?.dateOfBirth
        checks[i].expiryDate = id?.expiryDate
        checks[i].nationality = id?.nationality
        checks[i].idWarnings = id?.warnings?.compactMap { $0.shortDescription ?? $0.risk }
        checks[i].rawIDResponse = String(data: idRaw, encoding: .utf8)
        if let dn = id?.documentNumber { checks[i].customerId = dn }
        save() // triggers list update — still inProgress

        let exp = isExp(id?.expiryDate)
        return IDScanResult(
            idResult: id,
            nameMismatch: nameMismatch(entered: checks[i].customerName, extracted: id?.extractedFullName ?? ""),
            isExpired: exp
        )
    }

    /// Step 2: AML screening. Updates status to final based on combined ID+AML results.
    func runAMLScreening(checkId: String, monitoring: Bool = false) async throws -> AMLResult? {
        guard let i = idx(checkId) else { throw AppError.verificationFailed("Check not found") }

        let name = checks[i].extractedName ?? ""
        guard !name.isEmpty else { return nil }

        // Mark AML as in-progress (check stays inProgress)
        checks[i].amlStatus = "Screening..."; save()

        let iso2 = toISO2(checks[i].nationality) ?? toISO2(checks[i].documentType)
        let opts = VerificationAPIService.AMLOptions(includeAdverseMedia: true, includeMonitoring: monitoring)
        let (amlResp, amlRaw) = try await api.screenAML(
            fullName: name, dateOfBirth: checks[i].dateOfBirth,
            nationality: iso2, documentNumber: checks[i].documentNumber, vendorData: checkId,
            options: opts
        )
        let aml = amlResp.aml

        checks[i].amlStatus = aml?.status
        checks[i].amlScore = aml?.score
        checks[i].amlHitCount = aml?.totalHits
        checks[i].amlMonitoring = monitoring
        checks[i].rawAMLResponse = String(data: amlRaw, encoding: .utf8)

        // Now compute final status
        let exp = isExp(checks[i].expiryDate)
        let idWarn = checks[i].idWarnings?.isEmpty == false
        let amlFail = aml?.status == "Declined"
        let amlReview = aml?.status == "In Review"

        if amlFail || exp { checks[i].status = .failed }
        else if idWarn || amlReview { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        checks[i].completedAt = Date()
        save() // triggers list update — now shows final status

        return aml
    }

    /// For ID-only depth (no AML). Finalizes status based on ID results alone.
    func finalizeIDOnly(checkId: String) {
        guard let i = idx(checkId) else { return }
        let exp = isExp(checks[i].expiryDate)
        let warn = checks[i].idWarnings?.isEmpty == false
        if exp { checks[i].status = .failed }
        else if warn { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        checks[i].completedAt = Date(); save()
    }

    // MARK: - PoA

    struct PoAResult_ { let poaResult: PoAResult?; let rawJSON: String }

    func runPoA(checkId: String, documentImage: Data, expectedName: String?, expectedAddress: String?, onProgress: @escaping (String) -> Void) async throws -> PoAResult_ {
        guard let i = idx(checkId) else { throw AppError.verificationFailed("Check not found") }

        let fp = imagesDir.appendingPathComponent("\(checkId)_poa.jpg")
        try? documentImage.write(to: fp)
        checks[i].documentImagePaths = (checks[i].documentImagePaths ?? []) + [fp.lastPathComponent]

        onProgress("Verifying address...")
        let (resp, raw) = try await api.verifyAddress(document: documentImage, expectedName: expectedName, expectedAddress: expectedAddress, vendorData: checkId)
        let json = String(data: raw, encoding: .utf8) ?? ""
        let poa = resp.poa

        checks[i].poaStatus = poa?.status
        checks[i].poaAddress = poa?.poaFormattedAddress ?? poa?.poaAddress
        checks[i].poaIssuer = poa?.issuer
        checks[i].poaWarnings = poa?.warnings?.compactMap { $0.shortDescription ?? $0.risk }
        checks[i].rawPoAResponse = json
        checks[i].checkType = .idWithPoA
        if poa?.status == "Declined" { checks[i].status = .failed }
        else if poa?.warnings?.isEmpty == false && checks[i].status == .passed { checks[i].status = .requiresReview }
        checks[i].completedAt = Date(); save()

        return PoAResult_(poaResult: poa, rawJSON: json)
    }

    // MARK: - AML Re-run

    func updateAML(checkId: String, result: AMLResult?, rawJSON: String) {
        guard let i = idx(checkId) else { return }
        checks[i].amlStatus = result?.status
        checks[i].amlScore = result?.score
        checks[i].amlHitCount = result?.totalHits
        checks[i].rawAMLResponse = rawJSON

        // Re-evaluate
        let amlFail = result?.status == "Declined"
        let amlReview = result?.status == "In Review"
        let exp = isExp(checks[i].expiryDate)
        let warn = checks[i].idWarnings?.isEmpty == false

        if amlFail || exp { checks[i].status = .failed }
        else if warn || amlReview { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        save()
    }

    // MARK: - Notes

    // MARK: - Agent Review

    func submitReview(checkId: String, decision: KYCCheck.ReviewDecision, reason: String) {
        guard let i = idx(checkId) else { return }
        checks[i].reviewDecision = decision
        checks[i].reviewReason = reason
        checks[i].reviewedAt = Date()
        checks[i].reviewedBy = UserDefaults.standard.string(forKey: "agentName") ?? "Agent"

        // Override status based on review
        switch decision {
        case .approved: checks[i].status = .passed
        case .flagged: checks[i].status = .requiresReview
        case .declined: checks[i].status = .failed
        }
        save()
    }

    func updateAgentNotes(checkId: String, notes: String) {
        guard let i = idx(checkId) else { return }
        checks[i].agentNotes = notes; save()
    }

    // MARK: - Images

    func saveImages(checkId: String, front: Data, back: Data?) -> [String] {
        var paths: [String] = []
        let fp = imagesDir.appendingPathComponent("\(checkId)_front.jpg"); try? front.write(to: fp); paths.append(fp.lastPathComponent)
        if let b = back { let bp = imagesDir.appendingPathComponent("\(checkId)_back.jpg"); try? b.write(to: bp); paths.append(bp.lastPathComponent) }
        if let i = idx(checkId) { checks[i].documentImagePaths = paths; save() }
        return paths
    }

    func loadDocumentImage(filename: String) -> Data? {
        try? Data(contentsOf: imagesDir.appendingPathComponent(filename))
    }

    // MARK: - Delete

    func deleteCheck(at offsets: IndexSet) {
        for i in offsets {
            if let paths = checks[i].documentImagePaths {
                for p in paths { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(p)) }
            }
        }
        checks.remove(atOffsets: offsets); save()
    }

    // MARK: - Reset

    func resetAll() {
        KeychainService.deleteAll()
        UserDefaults.standard.removeObject(forKey: "agentName")
        try? FileManager.default.removeItem(at: checksFile)
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.removeItem(at: reportsDir)
        checks = []
    }

    // MARK: - PDF

    func generateReport(checkId: String) -> URL? {
        guard let check = checks.first(where: { $0.id == checkId }) else { return nil }
        // Load captured images for embedding
        var docImages: [UIImage] = []
        if let paths = check.documentImagePaths {
            for p in paths {
                if let d = loadDocumentImage(filename: p), let img = UIImage(data: d) { docImages.append(img) }
            }
        }
        let data = ReportGenerator.generatePDF(for: check, documentImages: docImages)
        let name = "OceanCheck_Report_\(check.customerName.replacingOccurrences(of: " ", with: "_"))_\(check.id.prefix(8)).pdf"
        let url = reportsDir.appendingPathComponent(name)
        try? data.write(to: url); return url
    }

    // MARK: - Helpers

    private func idx(_ id: String) -> Int? { checks.firstIndex(where: { $0.id == id }) }

    private func isExp(_ s: String?) -> Bool {
        guard let s else { return false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s).map { $0 < Date() } ?? false
    }

    /// Converts any country representation to ISO 3166-1 alpha-2.
    func toISO2(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Already alpha-2
        if trimmed.count == 2, Locale.Region.isoRegions.contains(where: { $0.identifier == trimmed }) {
            return trimmed
        }

        // Try alpha-3 → alpha-2 via Locale
        if trimmed.count == 3 {
            // Look up using Foundation
            for region in Locale.Region.isoRegions {
                let locale = Locale(identifier: "en_\(region.identifier)")
                if let code3 = locale.region?.identifier, code3.count == 2 {
                    // Check via Locale's identifier mapping
                }
            }
            // Manual common alpha-3 lookup
            if let found = alpha3Map[trimmed] { return found }
        }

        // Try matching by country name
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for region in Locale.Region.isoRegions {
            let name = Locale(identifier: "en").localizedString(forRegionCode: region.identifier)?.lowercased() ?? ""
            if name == lower || lower.contains(name) || name.contains(lower) {
                return region.identifier
            }
        }

        // If it's already 2 chars, try it anyway
        if trimmed.count == 2 { return trimmed }

        return nil
    }

    private let alpha3Map: [String: String] = [
        "AFG": "AF", "ALB": "AL", "DZA": "DZ", "AND": "AD", "AGO": "AO",
        "ARG": "AR", "ARM": "AM", "AUS": "AU", "AUT": "AT", "AZE": "AZ",
        "BHS": "BS", "BHR": "BH", "BGD": "BD", "BRB": "BB", "BLR": "BY",
        "BEL": "BE", "BLZ": "BZ", "BEN": "BJ", "BTN": "BT", "BOL": "BO",
        "BIH": "BA", "BWA": "BW", "BRA": "BR", "BRN": "BN", "BGR": "BG",
        "BFA": "BF", "BDI": "BI", "KHM": "KH", "CMR": "CM", "CAN": "CA",
        "CPV": "CV", "CAF": "CF", "TCD": "TD", "CHL": "CL", "CHN": "CN",
        "COL": "CO", "COM": "KM", "COG": "CG", "COD": "CD", "CRI": "CR",
        "CIV": "CI", "HRV": "HR", "CUB": "CU", "CYP": "CY", "CZE": "CZ",
        "DNK": "DK", "DJI": "DJ", "DMA": "DM", "DOM": "DO", "ECU": "EC",
        "EGY": "EG", "SLV": "SV", "GNQ": "GQ", "ERI": "ER", "EST": "EE",
        "ETH": "ET", "FJI": "FJ", "FIN": "FI", "FRA": "FR", "GAB": "GA",
        "GMB": "GM", "GEO": "GE", "DEU": "DE", "GHA": "GH", "GRC": "GR",
        "GTM": "GT", "GIN": "GN", "GNB": "GW", "GUY": "GY", "HTI": "HT",
        "HND": "HN", "HUN": "HU", "ISL": "IS", "IND": "IN", "IDN": "ID",
        "IRN": "IR", "IRQ": "IQ", "IRL": "IE", "ISR": "IL", "ITA": "IT",
        "JAM": "JM", "JPN": "JP", "JOR": "JO", "KAZ": "KZ", "KEN": "KE",
        "KWT": "KW", "KGZ": "KG", "LAO": "LA", "LVA": "LV", "LBN": "LB",
        "LSO": "LS", "LBR": "LR", "LBY": "LY", "LIE": "LI", "LTU": "LT",
        "LUX": "LU", "MKD": "MK", "MDG": "MG", "MWI": "MW", "MYS": "MY",
        "MDV": "MV", "MLI": "ML", "MLT": "MT", "MRT": "MR", "MUS": "MU",
        "MEX": "MX", "MDA": "MD", "MCO": "MC", "MNG": "MN", "MNE": "ME",
        "MAR": "MA", "MOZ": "MZ", "MMR": "MM", "NAM": "NA", "NPL": "NP",
        "NLD": "NL", "NZL": "NZ", "NIC": "NI", "NER": "NE", "NGA": "NG",
        "NOR": "NO", "OMN": "OM", "PAK": "PK", "PAN": "PA", "PNG": "PG",
        "PRY": "PY", "PER": "PE", "PHL": "PH", "POL": "PL", "PRT": "PT",
        "QAT": "QA", "ROU": "RO", "RUS": "RU", "RWA": "RW", "SAU": "SA",
        "SEN": "SN", "SRB": "RS", "SGP": "SG", "SVK": "SK", "SVN": "SI",
        "SOM": "SO", "ZAF": "ZA", "KOR": "KR", "ESP": "ES", "LKA": "LK",
        "SDN": "SD", "SUR": "SR", "SWZ": "SZ", "SWE": "SE", "CHE": "CH",
        "SYR": "SY", "TWN": "TW", "TJK": "TJ", "TZA": "TZ", "THA": "TH",
        "TLS": "TL", "TGO": "TG", "TTO": "TT", "TUN": "TN", "TUR": "TR",
        "TKM": "TM", "UGA": "UG", "UKR": "UA", "ARE": "AE", "GBR": "GB",
        "USA": "US", "URY": "UY", "UZB": "UZ", "VEN": "VE", "VNM": "VN",
        "YEM": "YE", "ZMB": "ZM", "ZWE": "ZW", "PSE": "PS", "XKX": "XK",
        "SSD": "SS", "D": "DE", "F": "FR", "GB": "GB"
    ]

    private func nameMismatch(entered: String, extracted: String) -> (String, String)? {
        guard !extracted.isEmpty else { return nil }
        let e = Set(entered.lowercased().split(separator: " ").map(String.init))
        let x = Set(extracted.lowercased().split(separator: " ").map(String.init))
        return Double(e.intersection(x).count) / Double(max(e.count, x.count, 1)) < 0.5 ? (entered, extracted) : nil
    }
}
