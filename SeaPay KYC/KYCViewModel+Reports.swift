//
//  KYCViewModel+Reports.swift
//  OceanCheck
//
//  PDF generation, CSV export, compliance packets, scenario-based sharing.
//

import Foundation
import UIKit
import os.log

private let reportLogger = Logger(subsystem: "com.seapay.kyc", category: "Reports")

extension KYCViewModel {

    // MARK: - Individual PDF Report

    func generateReport(checkId: String) -> URL? {
        guard let check = checks.first(where: { $0.id == checkId }) else { return nil }
        var docImages: [UIImage] = []
        if let paths = check.documentImagePaths {
            for p in paths {
                if let d = loadDocumentImage(filename: p), let img = UIImage(data: d) { docImages.append(img) }
            }
        }
        let data = ReportGenerator.generatePDF(for: check, documentImages: docImages)
        let name = "OceanCheck_Report_\(check.customerName.replacingOccurrences(of: " ", with: "_"))_\(check.id.prefix(8)).pdf"
        let url = reportsDir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            reportLogger.error("generateReport write failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - CSV Export

    func generateCSV(vesselId: String?) -> URL? {
        let target = vesselId.map { checksForVessel($0) } ?? checks
        let csv = CSVExporter.generateCrewCSV(checks: target, vessels: vessels)
        let name = "OceanCheck_CrewData_\(Date().formatted(.iso8601.year().month().day())).csv"
        let url = reportsDir.appendingPathComponent(name)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func generateCrewList(vesselId: String) -> URL? {
        guard let vessel = vessels.first(where: { $0.id == vesselId }) else { return nil }
        let crew = checksForVessel(vesselId)
        let data = ReportGenerator.generateCrewListPDF(vessel: vessel, checks: crew)
        let safeName = vessel.name.replacingOccurrences(of: " ", with: "_")
        let name = "CrewList_FAL5_\(safeName)_\(Date().formatted(.iso8601.year().month().day())).pdf"
        let url = reportsDir.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    // MARK: - UBO Report

    func generateUBOReport(vesselId: String) -> Data? {
        guard let i = vessels.firstIndex(where: { $0.id == vesselId }),
              let structure = vessels[i].ownershipStructure else { return nil }
        let checkIds = structure.shareholders.compactMap(\.checkId) + structure.directors.compactMap(\.checkId)
            + structure.shareholders.flatMap { $0.subShareholders?.compactMap(\.checkId) ?? [] }
            + (structure.trustees ?? []).compactMap(\.checkId)
            + (structure.settlors ?? []).compactMap(\.checkId)
            + (structure.protectors ?? []).compactMap(\.checkId)
            + (structure.beneficiaries ?? []).compactMap(\.checkId)
        let linkedChecks = checks.filter { checkIds.contains($0.id) }
        let data = ReportGenerator.generateUBOReport(vessel: vessels[i], structure: structure, checks: linkedChecks)
        vessels[i].ownershipStructure?.uboReportGenerated = true
        saveVessels()
        return data
    }

    // MARK: - Scenario-Based Sharing

    func generateShareExport(vesselId: String, scenario: VesselShareScenario) -> URL? {
        guard let vessel = vessels.first(where: { $0.id == vesselId }) else { return nil }
        let allChecks = checksForVessel(vesselId)
        let scope = scenario.scope

        let data: Data
        switch scenario {
        case .portRequest:
            data = ReportGenerator.generateAuthorityPacket(vessel: vessel, checks: allChecks, title: "PORT AUTHORITY DOCUMENTATION")
        case .classSociety:
            data = ReportGenerator.generateCertificateSummary(vessel: vessel)
        case .flagStateRequest:
            data = ReportGenerator.generateAuthorityPacket(vessel: vessel, checks: allChecks, title: "FLAG STATE COMPLIANCE REPORT", includeAML: scope.aml)
        case .insuranceRequest:
            data = ReportGenerator.generateAuthorityPacket(vessel: vessel, checks: allChecks, title: "P&I COMPLIANCE EVIDENCE", includeAML: true, includeUBO: true)
        case .charterDueDiligence:
            data = ReportGenerator.generateSanitizedCrewSummary(vessel: vessel, checks: allChecks)
        default:
            return nil
        }

        let safeName = vessel.name.replacingOccurrences(of: " ", with: "_")
        let scenarioTag = scenario.rawValue.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "")
        let name = "\(safeName)_\(scenarioTag)_\(Date().formatted(.iso8601.year().month().day())).pdf"
        let url = reportsDir.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    // MARK: - Compliance Packet

    func generateCompliancePacket(vesselId: String?) -> URL? {
        let target = vesselId.map { checksForVessel($0) } ?? checks
        let vessel = vesselId.flatMap { vid in vessels.first { $0.id == vid } }
        guard !target.isEmpty else { return nil }

        var allData: [Data] = []
        allData.append(ReportGenerator.generateCoverSheet(
            vesselName: vessel?.name ?? "All Crew", imoNumber: vessel?.imoNumber ?? "",
            flagState: vessel?.flagState ?? "", checks: target
        ))
        let sorted = target.sorted { ($0.entityType == .seafarer ? 0 : 1) < ($1.entityType == .seafarer ? 0 : 1) }
        for check in sorted {
            var docImages: [UIImage] = []
            if let paths = check.documentImagePaths {
                for p in paths { if let d = loadDocumentImage(filename: p), let img = UIImage(data: d) { docImages.append(img) } }
            }
            allData.append(ReportGenerator.generatePDF(for: check, documentImages: docImages))
        }

        let merged = mergePDFs(allData)
        let name = "OceanCheck_Compliance_\(vessel?.name.replacingOccurrences(of: " ", with: "_") ?? "All")_\(Date().formatted(.iso8601.year().month().day())).pdf"
        let url = reportsDir.appendingPathComponent(name)
        try? merged.write(to: url)
        return url
    }

    func mergePDFs(_ pdfs: [Data]) -> Data {
        let merged = NSMutableData()
        UIGraphicsBeginPDFContextToData(merged, .zero, nil)
        for pdf in pdfs {
            guard let provider = CGDataProvider(data: pdf as CFData),
                  let doc = CGPDFDocument(provider) else { continue }
            for i in 1...doc.numberOfPages {
                guard let page = doc.page(at: i) else { continue }
                let box = page.getBoxRect(.mediaBox)
                UIGraphicsBeginPDFPageWithInfo(box, nil)
                guard let ctx = UIGraphicsGetCurrentContext() else { continue }
                ctx.translateBy(x: 0, y: box.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.drawPDFPage(page)
            }
        }
        UIGraphicsEndPDFContext()
        return merged as Data
    }

    // MARK: - Owner Dashboard

    func generateOwnerDashboard(vesselId: String) -> URL? {
        guard let vessel = vessels.first(where: { $0.id == vesselId }) else { return nil }
        let allChecks = checksForVessel(vesselId)
        let readiness = vesselDocReadiness(for: vessel)
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let crewEntries = allChecks.map { check in
            let docs = check.documents?.filter { !$0.isArchived } ?? []
            let valid = docs.filter { $0.status == .valid }.count
            return OwnerCrewEntry(id: check.id, name: check.displayName, rank: check.crewRank?.rawValue, entityType: check.entityType.rawValue,
                status: check.status == .passed ? "Clear" : check.status == .failed ? "Flagged" : check.status == .requiresReview ? "Review" : "Pending",
                docRatio: docs.isEmpty ? nil : "\(valid)/\(docs.count)")
        }
        let certEntries = (vessel.documents ?? []).filter { !$0.isArchived }.map { doc in
            OwnerCertEntry(id: doc.id, name: doc.displayName, category: doc.vesselDocType?.category.rawValue ?? "Other",
                status: doc.status == .valid ? "Valid" : doc.status == .expiringSoon ? "Expiring" : doc.status == .expired ? "Expired" : "Missing",
                expiryDate: doc.expiryDate.map { dateFmt.string(from: $0) })
        }
        let snapshot = OwnerVesselSnapshot(vesselName: vessel.name, vesselType: vessel.vesselType?.rawValue, flagState: vessel.flagState, imoNumber: vessel.imoNumber, grossTonnage: vessel.grossTonnage,
            certTotal: readiness.total, certComplete: readiness.completed, certExpiring: readiness.expiring, certExpired: readiness.expired,
            crew: crewEntries, certificates: certEntries, agentName: AgentProfile.current?.fullName ?? "Agent", agentOrganization: AgentProfile.current?.companyName,
            lastUpdated: Date(), accessCode: vessel.id)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(snapshot) else { return nil }
        let safeName = vessel.name.replacingOccurrences(of: " ", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)_Dashboard.oceandash")
        try? FileManager.default.removeItem(at: url)
        try? data.write(to: url)
        return url
    }

    static func importOwnerDashboard(from url: URL) -> OwnerVesselSnapshot? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OwnerVesselSnapshot.self, from: data)
    }
}
