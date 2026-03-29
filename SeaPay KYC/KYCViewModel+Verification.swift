//
//  KYCViewModel+Verification.swift
//  OceanCheck
//
//  ID scan, AML screening, PoA, polling, invite session management.
//

import Foundation
import os.log

private let verifyLogger = Logger(subsystem: "com.seapay.kyc", category: "Verification")

extension KYCViewModel {

    // MARK: - Invite Flow

    struct InviteResult {
        let sessionId: String
        let verifyURL: String
    }

    func createInviteSession(checkId: String) async throws -> InviteResult {
        guard let i = checkIndex(checkId) else { throw AppError.verificationFailed("Check not found") }
        let wf = AppConfiguration.workflowID
        guard !wf.isEmpty else { throw AppError.missingRequiredField("Workflow ID — configure it in Settings") }

        let api = services.api
        APIUsageTracker.track(.session)
        let session = try await api.createSession(workflowID: wf, vendorData: checks[i].customerName)

        checks[i].status = .inProgress
        checks[i].sessionId = session.sessionId
        checks[i].hostedVerifyURL = session.url
        saveChecks()

        startPolling(checkId: checkId, sessionId: session.sessionId)
        return InviteResult(sessionId: session.sessionId, verifyURL: session.url ?? "")
    }

    func cancelInviteSession(checkId: String) {
        stopPolling(checkId: checkId)
        guard let i = checkIndex(checkId) else { return }
        checks[i].status = .pending; checks[i].sessionId = nil; checks[i].hostedVerifyURL = nil; saveChecks()
    }

    func refreshPendingSessions() async {
        for check in checks where check.sessionId != nil && check.status == .inProgress {
            guard let sid = check.sessionId else { continue }
            await pollOnce(checkId: check.id, sessionId: sid)
        }
    }

    // MARK: - Pipeline: ID Scan

    struct IDScanResult {
        let idResult: IDResult?
        let nameMismatch: (entered: String, extracted: String)?
        let isExpired: Bool
    }

    func runIDScan(checkId: String, frontImage: Data, backImage: Data?) async throws -> IDScanResult {
        guard let i = checkIndex(checkId) else { throw AppError.verificationFailed("Check not found") }

        checks[i].status = .inProgress; saveChecks()
        _ = saveImages(checkId: checkId, front: frontImage, back: backImage)

        let api = services.api
        APIUsageTracker.track(.idScan)
        let (idResp, idRaw) = try await api.verifyID(frontImage: frontImage, backImage: backImage, vendorData: checkId)
        let id = idResp.idVerification

        checks[i].extractedName = id?.extractedFullName
        if let fullName = id?.extractedFullName, !fullName.isEmpty { checks[i].customerName = fullName }
        checks[i].documentType = id?.documentType
        checks[i].documentNumber = id?.documentNumber
        checks[i].dateOfBirth = id?.dateOfBirth
        checks[i].expiryDate = id?.expiryDate
        checks[i].nationality = id?.nationality
        checks[i].issuingCountry = id?.issuingStateName ?? id?.issuingState
        checks[i].gender = id?.gender
        checks[i].documentIssueDate = id?.dateOfIssue
        checks[i].placeOfBirth = id?.placeOfBirth
        checks[i].personalNumber = id?.personalNumber
        checks[i].extractedAddress = id?.formattedAddress ?? id?.address
        checks[i].idWarnings = id?.warnings?.compactMap { $0.shortDescription ?? $0.risk }
        checks[i].rawIDResponse = String(data: idRaw, encoding: .utf8)
        if let dn = id?.documentNumber { checks[i].customerId = dn }

        autoCreatePassportDoc(checkIndex: i, idResult: id)
        saveChecks()

        return IDScanResult(
            idResult: id,
            nameMismatch: nameMismatch(entered: checks[i].customerName, extracted: id?.extractedFullName ?? ""),
            isExpired: isExpired(checks[i].expiryDate)
        )
    }

    // MARK: - AML Screening

    func runAMLScreening(checkId: String, monitoring: Bool = false) async throws -> AMLResult? {
        guard let i = checkIndex(checkId) else { throw AppError.verificationFailed("Check not found") }

        let name = checks[i].extractedName ?? ""
        guard !name.isEmpty else { return nil }

        checks[i].amlStatus = "Screening..."; saveChecks()

        let iso2 = toISO2(checks[i].nationality) ?? toISO2(checks[i].documentType)
        let opts = VerificationAPIService.AMLOptions(includeAdverseMedia: true, includeMonitoring: monitoring)
        let api = services.api
        APIUsageTracker.track(.amlScreening)
        let (amlResp, amlRaw) = try await api.screenAML(
            fullName: name, dateOfBirth: checks[i].dateOfBirth,
            nationality: iso2, documentNumber: checks[i].documentNumber, vendorData: checkId, options: opts
        )
        let aml = amlResp.aml

        checks[i].amlStatus = aml?.status
        checks[i].amlScore = aml?.score
        checks[i].amlHitCount = aml?.totalHits
        checks[i].amlMonitoring = monitoring
        checks[i].rawAMLResponse = String(data: amlRaw, encoding: .utf8)

        let exp = isExpired(checks[i].expiryDate)
        let idWarn = checks[i].idWarnings?.isEmpty == false
        let amlFail = aml?.status == "Declined"
        let amlReview = aml?.status == "In Review"

        if amlFail || exp { checks[i].status = .failed }
        else if idWarn || amlReview { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        checks[i].completedAt = Date()
        saveChecks()

        return aml
    }

    func finalizeIDOnly(checkId: String) {
        guard let i = checkIndex(checkId) else { return }
        let exp = isExpired(checks[i].expiryDate)
        let warn = checks[i].idWarnings?.isEmpty == false
        if exp { checks[i].status = .failed }
        else if warn { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        checks[i].completedAt = Date(); saveChecks()
    }

    // MARK: - PoA

    struct PoAResult_ { let poaResult: PoAResult?; let rawJSON: String }

    func runPoA(checkId: String, documentImage: Data, expectedName: String?, expectedAddress: String?, onProgress: @escaping (String) -> Void) async throws -> PoAResult_ {
        guard let i = checkIndex(checkId) else { throw AppError.verificationFailed("Check not found") }

        let fp = imagesDir.appendingPathComponent("\(checkId)_poa.jpg")
        try? documentImage.write(to: fp)
        checks[i].documentImagePaths = (checks[i].documentImagePaths ?? []) + [fp.lastPathComponent]

        onProgress("Verifying address...")
        let api = services.api
        APIUsageTracker.track(.poaCheck)
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
        checks[i].completedAt = Date(); saveChecks()

        return PoAResult_(poaResult: poa, rawJSON: json)
    }

    // MARK: - AML Re-run

    func updateAML(checkId: String, result: AMLResult?, rawJSON: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].amlStatus = result?.status
        checks[i].amlScore = result?.score
        checks[i].amlHitCount = result?.totalHits
        checks[i].rawAMLResponse = rawJSON

        let amlFail = result?.status == "Declined"
        let amlReview = result?.status == "In Review"
        let exp = isExpired(checks[i].expiryDate)
        let warn = checks[i].idWarnings?.isEmpty == false

        if amlFail || exp { checks[i].status = .failed }
        else if warn || amlReview { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        saveChecks()
    }

    // MARK: - Session Polling

    func pollSessionDecision(checkId: String, sessionId: String) async throws -> SessionDecision {
        let api = services.api
        let (decision, rawData) = try await api.getSessionDecision(sessionId: sessionId)
        let rawString = String(data: rawData, encoding: .utf8)

        #if DEBUG
        verifyLogger.debug("Poll \(checkId.prefix(8)): status=\(decision.status)")
        #endif

        if let i = checkIndex(checkId) {
            let s = decision.status.lowercased()
            if s == "approved" || s == "completed" { checks[i].status = .passed }
            else if s == "declined" || s == "rejected" || s == "failed" { checks[i].status = .failed }
            else if s == "expired" { checks[i].status = .incomplete }

            if let idResult = decision.idVerifications?.first {
                checks[i].extractedName = idResult.extractedFullName
                if !idResult.extractedFullName.isEmpty { checks[i].customerName = idResult.extractedFullName }
                checks[i].documentType = idResult.documentType
                checks[i].documentNumber = idResult.documentNumber
                checks[i].dateOfBirth = idResult.dateOfBirth
                checks[i].expiryDate = idResult.expirationDate
                checks[i].nationality = idResult.nationality
                checks[i].issuingCountry = idResult.issuingStateName ?? idResult.issuingState
                checks[i].gender = idResult.gender
                checks[i].documentIssueDate = idResult.dateOfIssue
                checks[i].placeOfBirth = idResult.placeOfBirth
                checks[i].personalNumber = idResult.personalNumber
                checks[i].extractedAddress = idResult.formattedAddress ?? idResult.address
                checks[i].idWarnings = idResult.warnings?.compactMap { $0.shortDescription ?? $0.risk }
                if let dn = idResult.documentNumber { checks[i].customerId = dn }
            }
            if let amlResult = decision.aml?.first {
                checks[i].amlStatus = amlResult.status
                checks[i].amlScore = amlResult.score
                checks[i].amlHitCount = amlResult.totalHits
            }

            if isTerminalStatus(decision.status) {
                checks[i].completedAt = Date()
                if checks[i].rawIDResponse == nil {
                    checks[i].rawIDResponse = rawString
                    #if DEBUG
                    verifyLogger.debug("Stored rawIDResponse for \(checkId.prefix(8))")
                    #endif
                }
            }
            saveChecks()
        }

        return decision
    }

    // MARK: - Agent Review

    func submitReview(checkId: String, decision: KYCCheck.ReviewDecision, reason: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].reviewDecision = decision
        checks[i].reviewReason = reason
        checks[i].reviewedAt = Date()
        checks[i].reviewedBy = AgentProfile.current?.fullName ?? "Agent"
        switch decision {
        case .approved: checks[i].status = .passed
        case .flagged: checks[i].status = .requiresReview
        case .declined: checks[i].status = .failed
        }
        saveChecks()
    }

    func updateAgentNotes(checkId: String, notes: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].agentNotes = notes; saveChecks()
    }

    func configureCheck(checkId: String, docType: KYCCheck.IDDocType, depth: KYCCheck.InvestigationDepth) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].expectedDocType = docType
        checks[i].investigationDepth = depth
        saveChecks()
    }

    // MARK: - Batch Invite

    struct BatchProgress {
        var total: Int; var completed: Int
        var results: [(name: String, url: String?, error: String?)]
    }

    func createBatchInvites(names: [String], vesselId: String?) -> AsyncStream<BatchProgress> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                var progress = BatchProgress(total: names.count, completed: 0, results: [])
                for name in names {
                    let check = self.createCheck(customerName: name)
                    if let vid = vesselId { self.assignCheckToVessel(checkId: check.id, vesselId: vid) }
                    do {
                        let r = try await self.createInviteSession(checkId: check.id)
                        progress.results.append((name, r.verifyURL, nil))
                    } catch {
                        progress.results.append((name, nil, error.localizedDescription))
                    }
                    progress.completed += 1
                    continuation.yield(progress)
                }
                continuation.finish()
            }
        }
    }
}
