//
//  ReportGenerator.swift
//  OceanCheck
//
//  Compliance-grade PDF with: cover page, two-column layout, summary table,
//  risk bar, QR code, document images, regulatory refs, chain of custody,
//  verification timeline, signatory, watermark, integrity hash, PDF metadata,
//  color-coded page edges, clickable hyperlinks.
//

import UIKit
import CoreImage
import CryptoKit

enum ReportGenerator {

    // Palette
    private static let black = UIColor.black
    private static let dark = UIColor(white: 0.15, alpha: 1)
    private static let mid = UIColor(white: 0.45, alpha: 1)
    private static let light = UIColor(white: 0.70, alpha: 1)
    private static let ruleC = UIColor(white: 0.82, alpha: 1)
    private static let bgAlt = UIColor(white: 0.96, alpha: 1)
    private static let white = UIColor.white
    private static let sG = UIColor(red: 0.15, green: 0.55, blue: 0.25, alpha: 1)
    private static let sR = UIColor(red: 0.70, green: 0.12, blue: 0.12, alpha: 1)
    private static let sA = UIColor(red: 0.65, green: 0.50, blue: 0.08, alpha: 1)

    private static let L: CGFloat = 48, W: CGFloat = 499, FZ: CGFloat = 60
    private static let pg = CGRect(x: 0, y: 0, width: 595, height: 842)

    private static func sc(_ s: KYCCheck.CheckStatus) -> UIColor { s == .passed ? sG : s == .failed ? sR : sA }
    private static func sn(_ full: String) -> String { let p = full.trimmingCharacters(in: .whitespaces).split(separator: " "); guard let f = p.first else { return full }; if let last = p.last, let initial = last.first { return "\(f) \(initial.uppercased())." }; return String(f) }

    // ═══════════════════════════════════════════
    // MARK: - Public
    // ═══════════════════════════════════════════

    static func generatePDF(for check: KYCCheck, documentImages: [UIImage] = []) -> Data {
        let ref = "OC-\(String(check.id.prefix(8)).uppercased())"
        let profile = AgentProfile.current
        let agent = profile?.profileLine ?? sn(check.agentName)
        let hash = computeHash(check)
        var pn = 0
        let edgeColor = sc(check.status)

        let pdfInfo: [String: Any] = [
            kCGPDFContextTitle as String: "OceanCheck KYC Report — \(check.customerName)",
            kCGPDFContextAuthor as String: "OceanCheck / SeaPay",
            kCGPDFContextSubject as String: "Know Your Customer Compliance Report \(ref)",
            kCGPDFContextCreator as String: "OceanCheck v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"
        ]
        let fmt = UIGraphicsPDFRendererFormat()
        fmt.documentInfo = pdfInfo
        let renderer = UIGraphicsPDFRenderer(bounds: pg, format: fmt)
        return renderer.pdfData { ctx in

            // ╔══════════════════════════════════════╗
            // ║           PAGE 1 — COVER             ║
            // ╚══════════════════════════════════════╝
            ctx.beginPage(); pn += 1; watermark(); edge(edgeColor)

            // Header
            black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: pg.width, height: 90))
            txt("OceanCheck", pt(L, 22), BrandFont.uiFont(size: 24), white)
            txt("KNOW YOUR CUSTOMER COMPLIANCE REPORT", pt(L, 54), .systemFont(ofSize: 8.5, weight: .bold), UIColor(white: 0.5, alpha: 1))
            txtR("CONFIDENTIAL", 30, .systemFont(ofSize: 7, weight: .bold), UIColor(white: 0.4, alpha: 1))
            txtR(ref, 44, .monospacedSystemFont(ofSize: 7, weight: .regular), UIColor(white: 0.4, alpha: 1))
            txtR(Date().formatted(date: .long, time: .omitted), 58, .systemFont(ofSize: 7), UIColor(white: 0.4, alpha: 1))

            var y: CGFloat = 104

            // QR code (top right, below header) — encodes signed verification URL
            let verifyURL = buildVerificationURL(check: check, ref: ref, hash: hash)
            if let qr = generateQR(verifyURL) {
                let qrSize: CGFloat = 60
                let qrX = pg.width - L - qrSize
                // White background behind QR
                white.setFill()
                UIBezierPath(roundedRect: CGRect(x: qrX - 4, y: y - 4, width: qrSize + 8, height: qrSize + 20), cornerRadius: 4).fill()
                ruleC.setStroke()
                UIBezierPath(roundedRect: CGRect(x: qrX - 4, y: y - 4, width: qrSize + 8, height: qrSize + 20), cornerRadius: 4).stroke()
                qr.draw(in: CGRect(x: qrX, y: y, width: qrSize, height: qrSize))
                // Label
                let lbl = "Scan to verify"
                let lblA: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 5.5, weight: .medium), .foregroundColor: mid]
                let lblSz = (lbl as NSString).size(withAttributes: lblA)
                (lbl as NSString).draw(at: CGPoint(x: qrX + (qrSize - lblSz.width) / 2, y: y + qrSize + 2), withAttributes: lblA)
                // Make QR area a clickable link in the PDF
                if let url = URL(string: verifyURL) {
                    UIGraphicsGetCurrentContext()?.setURL(url as CFURL, for: CGRect(x: qrX, y: pg.height - y - qrSize, width: qrSize, height: qrSize))
                }
            }

            // Subject + verdict (left column, next to QR)
            txt(check.customerName.uppercased(), pt(L, y + 4), .systemFont(ofSize: 20, weight: .bold), black)
            y += 30

            let oc = sc(check.status)
            let vR = CGRect(x: L, y: y, width: W - 72, height: 46)
            oc.withAlphaComponent(0.05).setFill(); UIBezierPath(roundedRect: vR, cornerRadius: 4).fill()
            black.setFill(); UIRectFill(CGRect(x: L, y: y, width: 4, height: 46))
            oc.setFill(); UIRectFill(CGRect(x: L + 4, y: y, width: 2, height: 46))
            txt(outTitle(check.status), pt(L + 16, y + 6), .systemFont(ofSize: 16, weight: .bold), black)
            txt(outSub(check.status), pt(L + 16, y + 28), .systemFont(ofSize: 8), mid)
            y += 60

            // Expired document warning
            if let exp = check.expiryDate, isExp(exp) {
                let wR = CGRect(x: L, y: y, width: W, height: 18)
                sR.withAlphaComponent(0.08).setFill(); UIRectFill(wR)
                txt("\u{26A0} DOCUMENT EXPIRED — Presented document has passed its expiry date", pt(L + 6, y + 3), .systemFont(ofSize: 7.5, weight: .bold), sR)
                y += 24
            }

            // ── Two-column metadata ──
            let colW: CGFloat = (W - 20) / 2
            let leftX = L, rightX = L + colW + 20
            var ly = y, ry = y

            // Left column: subject
            txt("SUBJECT", pt(leftX, ly), .systemFont(ofSize: 7, weight: .bold), mid); ly += 12
            ly = metaRow("Full Name", check.customerName, at: ly, x: leftX, w: colW)
            if !check.customerId.isEmpty { ly = metaRow("Reference", check.customerId, at: ly, x: leftX, w: colW) }
            if let v = check.documentType { ly = metaRow("Document", v.replacingOccurrences(of: "_", with: " ").capitalized, at: ly, x: leftX, w: colW) }
            if let v = check.documentNumber { ly = metaRow("Doc Number", v, at: ly, x: leftX, w: colW) }
            if let v = check.nationality { ly = metaRow("Nationality", v.uppercased(), at: ly, x: leftX, w: colW) }

            // Right column: verification
            txt("VERIFICATION", pt(rightX, ry), .systemFont(ofSize: 7, weight: .bold), mid); ry += 12
            ry = metaRow("Date", (check.completedAt ?? check.createdAt).formatted(date: .long, time: .shortened), at: ry, x: rightX, w: colW)
            ry = metaRow("Officer", agent, at: ry, x: rightX, w: colW)
            if let aid = profile?.agentId, !aid.isEmpty { ry = metaRow("Agent ID", aid, at: ry, x: rightX, w: colW) }
            ry = metaRow("Classification", "Confidential", at: ry, x: rightX, w: colW)
            if let lat = check.latitude, let lon = check.longitude { ry = metaRow("Location", String(format: "%.4f, %.4f", lat, lon), at: ry, x: rightX, w: colW) }
            ry = metaRow("Report Ref", ref, at: ry, x: rightX, w: colW)

            y = max(ly, ry) + 14

            // ── Summary Table ──
            y = secT("Verification Summary", at: y, ctx: ctx, pn: &pn, ref: ref)
            y = sumRow("Identity Document", check.documentType != nil ? "VERIFIED" : "PENDING", check.idWarnings?.isEmpty ?? true ? sG : sA, at: y, alt: true)
            y = sumRow("AML / Sanctions", check.amlStatus ?? "PENDING", check.amlStatus == "Approved" ? sG : check.amlStatus == "Declined" ? sR : sA, at: y, alt: false)
            if check.poaStatus != nil { y = sumRow("Proof of Address", check.poaStatus!, check.poaStatus == "Approved" ? sG : sR, at: y, alt: true) }
            if let d = check.reviewDecision { y = sumRow("Agent Review", d.rawValue, d == .approved ? sG : d == .declined ? sR : sA, at: y, alt: check.poaStatus != nil ? false : true) }
            y += 10

            // ── Risk Bar ──
            if let score = check.amlScore {
                y = fitC(y, 42, ctx, &pn, ref, edgeColor)
                txt("RISK ASSESSMENT", pt(L, y), .systemFont(ofSize: 7, weight: .bold), mid); y += 12
                riskBar(score, y); y += 28
            }

            // ── Verification Timeline ──
            y = fitC(y, 36, ctx, &pn, ref, edgeColor)
            txt("VERIFICATION TIMELINE", pt(L, y), .systemFont(ofSize: 7, weight: .bold), mid); y += 12
            y = drawTimeline(check, at: y)
            y += 12

            // ── Regulatory Framework ──
            y = fitC(y, 56, ctx, &pn, ref, edgeColor)
            txt("REGULATORY FRAMEWORK", pt(L, y), .systemFont(ofSize: 7, weight: .bold), mid); y += 12
            y = bul("Maritime Labour Convention (MLC) 2006", y)
            y = bul("ISM Code, Section 6 — Resources and Personnel", y)
            y = bul("STCW Convention — Standards of Training, Certification and Watchkeeping", y)
            y = bul("EU Anti-Money Laundering Directive 2015/849", y)

            footer(ref, pn, pn + 2, edgeColor)

            // ╔══════════════════════════════════════╗
            // ║         PAGE 2+ — DETAILS            ║
            // ╚══════════════════════════════════════╝
            ctx.beginPage(); pn += 1; watermark(); edge(edgeColor)
            y = hdr(ref)

            // Executive Summary
            y = secT("Executive Summary", at: y, ctx: ctx, pn: &pn, ref: ref)
            y = para(buildSum(check), y); y += 12

            // Identity
            if check.documentType != nil || check.extractedName != nil {
                y = fitC(y, 120, ctx, &pn, ref, edgeColor)
                y = secT("Identity Document Verification", at: y, ctx: ctx, pn: &pn, ref: ref)
                var a = true
                func r(_ l: String, _ v: String, c: UIColor? = nil) { y = fitC(y, 18, ctx, &pn, ref, edgeColor); y = tR(l, v, y, a, c); a.toggle() }
                if let v = check.documentType { r("Document Type", v.replacingOccurrences(of: "_", with: " ").capitalized) }
                if let v = check.extractedName { r("Name on Document", v) }
                if let v = check.documentNumber { r("Document Number", v) }
                if let v = check.dateOfBirth { r("Date of Birth", fD(v)) }
                if let v = check.nationality { r("Nationality", v.uppercased()) }
                if let v = check.expiryDate { r("Document Expiry", fD(v) + (isExp(v) ? "  (EXPIRED)" : ""), c: isExp(v) ? sR : nil) }
                if let ex = check.extractedName, !ex.isEmpty { let ok = nameSim(check.customerName, ex); r("Name Consistency", ok ? "Consistent with stated identity" : "Discrepancy noted", c: ok ? nil : sA) }
                if let w = check.idWarnings, !w.isEmpty { y += 3; for s in w { y = bul(s, y, sA) } }

                // Document images
                if !documentImages.isEmpty {
                    y += 8; y = fitC(y, 80, ctx, &pn, ref, edgeColor)
                    txt("Captured Documents", pt(L, y), .systemFont(ofSize: 7.5, weight: .bold), mid); y += 12
                    var imgX = L
                    for img in documentImages.prefix(3) {
                        let h: CGFloat = 60; let w = h * img.size.width / max(img.size.height, 1)
                        let bounded = min(w, 140)
                        if imgX + bounded > L + W { break }
                        img.draw(in: CGRect(x: imgX, y: y, width: bounded, height: h))
                        ruleC.setStroke(); UIBezierPath(rect: CGRect(x: imgX, y: y, width: bounded, height: h)).stroke()
                        imgX += bounded + 8
                    }
                    y += 68
                }
                y += 12
            }

            // AML
            if check.amlStatus != nil {
                y = fitC(y, 70, ctx, &pn, ref, edgeColor)
                y = secT("Anti-Money Laundering Screening", at: y, ctx: ctx, pn: &pn, ref: ref)
                var a = true
                func r(_ l: String, _ v: String, c: UIColor? = nil) { y = fitC(y, 18, ctx, &pn, ref, edgeColor); y = tR(l, v, y, a, c); a.toggle() }
                func lk(_ l: String, _ u: String) { y = fitC(y, 18, ctx, &pn, ref, edgeColor); y = lnkR(l, u, y, a); a.toggle() }
                if let v = check.amlStatus { r("Result", v == "Approved" ? "Clear — No adverse findings" : v == "Declined" ? "Adverse findings identified" : "Requires manual review", c: v == "Approved" ? sG : v == "Declined" ? sR : sA) }
                if let v = check.amlScore { r("Risk Score", "\(v > 70 ? "High" : v > 40 ? "Elevated" : "Low") (\(v)/100)", c: v > 70 ? sR : v > 40 ? sA : sG) }
                if let v = check.amlHitCount, v > 0 { r("Watchlist Matches", "\(v)") }
                if check.amlMonitoring == true { r("Monitoring", "Active — continuous rescreening") }
                y += 3; y = bul("UN, EU, OFAC, HMT sanctions", y); y = bul("PEP databases", y); y = bul("Adverse media", y)

                // Hits
                if let raw = check.rawAMLResponse, let data = raw.data(using: .utf8),
                   let resp = try? JSONDecoder().decode(AMLScreeningResponse.self, from: data),
                   let hits = resp.aml?.hits, !hits.isEmpty {
                    y += 6
                    for (i, hit) in hits.prefix(10).enumerated() {
                        y = fitC(y, 50, ctx, &pn, ref, edgeColor)
                        ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 0.5)); y += 5
                        txt("\(i+1). \(hit.caption ?? "Unknown")", pt(L + 4, y), .systemFont(ofSize: 8.5, weight: .bold), dark)
                        var bd: [String] = []; if let ms = hit.matchScore { bd.append("Match \(ms)%") }; if let rs = hit.riskScore { bd.append("Risk \(Int(rs))") }
                        if !bd.isEmpty { txtR(bd.joined(separator: " \u{2022} "), y, .systemFont(ofSize: 8, weight: .bold), (hit.riskScore ?? 0) > 70 ? sR : sA) }
                        y += 13; a = true
                        if let ds = hit.datasets, !ds.isEmpty { r("Categories", ds.joined(separator: ", ")) }
                        if let sb = hit.scoreBreakdown { var p: [String] = []; if let n = sb.nameScore { p.append("Name \(n)") }; if let d = sb.dobScore { p.append("DOB \(d)") }; if let c = sb.countryScore { p.append("Country \(c)") }; if !p.isEmpty { r("Scoring", p.joined(separator: " \u{2022} ")) } }
                        if let rv = hit.reviewStatus { r("Review", rv) }
                        if let peps = hit.pepMatches, !peps.isEmpty { for pep in peps.prefix(3) { if let pos = pep.pepPosition { r("  PEP", pos) }; if let list = pep.listName { r("  List", list) } } }
                        if let sxns = hit.sanctionMatches, !sxns.isEmpty { for sxn in sxns.prefix(3) { if let desc = sxn.description { r("  Sanction", String(desc.prefix(180))) }; if let reason = sxn.reason { r("  Basis", reason) }; if let url = sxn.sourceUrl { lk("  Source", url) } } }
                        if let media = hit.adverseMediaMatches, !media.isEmpty { for m in media.prefix(3) { if let h = m.headline { r("  Media", String(h.prefix(140))) }; if let s = m.sentiment { r("  Sentiment", s.capitalized, c: s.lowercased() == "negative" ? sR : nil) }; if let url = m.sourceUrl { lk("  Source", url) } } }
                        y += 4
                    }
                }
                y += 10
            }

            // PoA
            if check.poaStatus != nil {
                y = fitC(y, 50, ctx, &pn, ref, edgeColor); y = secT("Address Verification", at: y, ctx: ctx, pn: &pn, ref: ref); var a = true
                func r(_ l: String, _ v: String, c: UIColor? = nil) { y = fitC(y, 18, ctx, &pn, ref, edgeColor); y = tR(l, v, y, a, c); a.toggle() }
                if let v = check.poaStatus { r("Result", v == "Approved" ? "Address confirmed" : "Review required", c: v == "Approved" ? sG : sR) }
                if let v = check.poaAddress { r("Address", v) }; if let v = check.poaIssuer { r("Issuer", v) }; y += 12
            }

            // Review
            if let dec = check.reviewDecision {
                y = fitC(y, 50, ctx, &pn, ref, edgeColor); y = secT("Compliance Review Decision", at: y, ctx: ctx, pn: &pn, ref: ref)
                y = tR("Decision", dec.rawValue.uppercased(), y, true, dec == .approved ? sG : dec == .declined ? sR : sA)
                if let by = check.reviewedBy { y = tR("Reviewed By", sn(by), y, false) }
                if let at = check.reviewedAt { y = tR("Date", at.formatted(date: .long, time: .shortened), y, true) }
                if let r = check.reviewReason, !r.isEmpty { y += 3; y = para(r, y) }; y += 12
            }

            // Notes
            if let n = check.agentNotes, !n.isEmpty { y = fitC(y, 40, ctx, &pn, ref, edgeColor); y = secT("Officer Observations", at: y, ctx: ctx, pn: &pn, ref: ref); y = para(n, y); y += 12 }

            // Document Portfolio
            if let docs = check.documents, !docs.isEmpty {
                y = fitC(y, 60, ctx, &pn, ref, edgeColor)
                y = secT("Document Portfolio", at: y, ctx: ctx, pn: &pn, ref: ref)
                let dfmt = DateFormatter(); dfmt.dateFormat = "dd MMM yyyy"
                var da = true
                for doc in docs.sorted(by: { $0.type.displayName < $1.type.displayName }) {
                    y = fitC(y, 16, ctx, &pn, ref, edgeColor)
                    let expStr: String
                    if let exp = doc.expiryDate {
                        expStr = dfmt.string(from: exp) + (exp < Date() ? " (EXPIRED)" : "")
                    } else { expStr = "No expiry" }
                    let sc: UIColor = doc.status == .valid ? sG : doc.status == .expired ? sR : doc.status == .expiringSoon ? sA : mid
                    sc.setFill(); UIRectFill(CGRect(x: L, y: y + 2, width: 3, height: 10))
                    txt(doc.type.displayName, pt(L + 8, y), .systemFont(ofSize: 8, weight: .medium), dark)
                    txtR(expStr, y, .systemFont(ofSize: 7), sc)
                    y += 14; da.toggle()
                }
                y += 12
            }

            // Chain of Custody
            y = fitC(y, 80, ctx, &pn, ref, edgeColor); y = secT("Chain of Custody", at: y, ctx: ctx, pn: &pn, ref: ref)
            var ca = true
            func cr(_ l: String, _ v: String) { y = tR(l, v, y, ca); ca.toggle() }
            cr("Captured By", agent); cr("Capture Date", check.createdAt.formatted(date: .long, time: .shortened))
            if let lat = check.latitude, let lon = check.longitude { cr("GPS", String(format: "%.5f, %.5f", lat, lon)) }
            cr("Application", "OceanCheck v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
            cr("Report Generated", Date().formatted(date: .long, time: .shortened))
            y += 12

            // Signatory
            y = fitC(y, 100, ctx, &pn, ref, edgeColor)
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 0.5)); y += 14
            txt("DIGITAL ATTESTATION", pt(L, y), .systemFont(ofSize: 8, weight: .bold), dark); y += 14
            txt("This report has been reviewed and is issued under the authority of:", pt(L, y), .systemFont(ofSize: 8), mid); y += 16
            txt("Alexander D.", pt(L, y), .systemFont(ofSize: 11, weight: .bold), black); y += 14
            txt("Money Laundering Reporting Officer (MLRO) & Chief Executive Officer", pt(L, y), .systemFont(ofSize: 8), mid); y += 12
            txt("SeaPay\u{00AE}", pt(L, y), BrandFont.uiFont(size: 10), black); y += 16
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: 180, height: 0.5)); y += 4
            txt("Authorised Signatory", pt(L, y), .systemFont(ofSize: 7), light); y += 18

            // Integrity Hash
            y = fitC(y, 30, ctx, &pn, ref, edgeColor)
            txt("DOCUMENT INTEGRITY", pt(L, y), .systemFont(ofSize: 6.5, weight: .bold), light); y += 10
            txt("SHA-256: \(hash)", pt(L, y), .monospacedSystemFont(ofSize: 5.5, weight: .regular), UIColor(white: 0.75, alpha: 1)); y += 12

            // Disclaimer
            y = fitC(y, 50, ctx, &pn, ref, edgeColor)
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 0.5)); y += 6
            y = para("This report is generated by OceanCheck on behalf of SeaPay\u{00AE} for compliance and regulatory purposes. The information is based on automated identity verification and screening processes conducted in accordance with applicable anti-money laundering regulations. Results should be considered in conjunction with institutional risk policies. This document is confidential and intended solely for authorised recipients. Unauthorised reproduction or distribution is prohibited.", y, .systemFont(ofSize: 6), light)

            footer(ref, pn, pn, edgeColor)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - QR Code
    // ═══════════════════════════════════════════

    /// Builds a verification URL with signed payload.
    /// When scanned, takes the viewer to a page confirming the report's authenticity.
    /// The hash parameter allows independent verification — if any field is altered, the hash won't match.
    private static func buildVerificationURL(check: KYCCheck, ref: String, hash: String) -> String {
        let base = "https://seapay.me/verify"
        var params: [String] = []
        params.append("ref=\(ref)")
        params.append("name=\(check.customerName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        params.append("status=\(check.status.rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        if let aml = check.amlStatus { params.append("aml=\(aml)") }
        if let score = check.amlScore { params.append("score=\(score)") }
        if let doc = check.documentType { params.append("doc=\(doc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") }
        if let docNum = check.documentNumber { params.append("docnum=\(docNum.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") }
        let dateStr = check.createdAt.formatted(date: .numeric, time: .omitted)
        params.append("date=\(dateStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        // The hash is the integrity seal — SHA-256 of all check data
        params.append("hash=\(hash)")
        return "\(base)?\(params.joined(separator: "&"))"
    }

    private static func generateQR(_ string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        // Use UTF-8 encoding (not ASCII) to support special characters in URLs
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        // Render to a crisp CGImage — no interpolation, pixel-perfect
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        // Scale up to a high-res bitmap with nearest-neighbor (no blur)
        let targetSize: CGFloat = 512
        let size = CGSize(width: targetSize, height: targetSize)

        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.interpolationQuality = .none // nearest-neighbor — crisp pixels
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -targetSize)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }

    // ═══════════════════════════════════════════
    // MARK: - Integrity Hash
    // ═══════════════════════════════════════════

    private static func computeHash(_ c: KYCCheck) -> String {
        let payload = "\(c.id)|\(c.customerName)|\(c.customerId)|\(c.status.rawValue)|\(c.amlStatus ?? "")|\(c.amlScore ?? 0)|\(c.createdAt.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // ═══════════════════════════════════════════
    // MARK: - Timeline
    // ═══════════════════════════════════════════

    private static func drawTimeline(_ c: KYCCheck, at y: CGFloat) -> CGFloat {
        var steps: [(String, String)] = [("Created", c.createdAt.formatted(date: .abbreviated, time: .shortened))]
        if c.documentType != nil { steps.append(("ID Scanned", "")) }
        if c.amlStatus != nil { steps.append(("AML \(c.amlStatus ?? "")", "")) }
        if c.poaStatus != nil { steps.append(("PoA \(c.poaStatus ?? "")", "")) }
        if c.reviewDecision != nil { steps.append(("Reviewed", "")) }
        if let d = c.completedAt { steps.append(("Completed", d.formatted(date: .abbreviated, time: .shortened))) }

        let stepW = W / CGFloat(max(steps.count, 1))
        for (i, step) in steps.enumerated() {
            let x = L + stepW * CGFloat(i) + stepW / 2
            // Dot
            let dotR: CGFloat = 4
            (i < steps.count - 1 || c.completedAt != nil ? sG : sA).setFill()
            UIBezierPath(ovalIn: CGRect(x: x - dotR, y: y, width: dotR * 2, height: dotR * 2)).fill()
            // Line to next
            if i < steps.count - 1 {
                let nx = L + stepW * CGFloat(i + 1) + stepW / 2
                ruleC.setStroke()
                let path = UIBezierPath(); path.move(to: CGPoint(x: x + dotR + 2, y: y + dotR)); path.addLine(to: CGPoint(x: nx - dotR - 2, y: y + dotR)); path.lineWidth = 1; path.stroke()
            }
            // Label
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 6, weight: .medium), .foregroundColor: dark]
            let lbl = step.0 as NSString
            let sz = lbl.size(withAttributes: attrs)
            lbl.draw(at: CGPoint(x: x - sz.width / 2, y: y + 10), withAttributes: attrs)
        }
        return y + 24
    }

    // ═══════════════════════════════════════════
    // MARK: - Watermark + Edge
    // ═══════════════════════════════════════════

    private static func watermark() {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); ctx.translateBy(x: pg.width / 2, y: pg.height / 2); ctx.rotate(by: -.pi / 4)
        let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 68, weight: .bold), .foregroundColor: UIColor(white: 0.93, alpha: 1)]
        let s = ("OceanCheck" as NSString).size(withAttributes: a)
        ("OceanCheck" as NSString).draw(at: CGPoint(x: -s.width / 2, y: -s.height / 2), withAttributes: a)
        ctx.restoreGState()
    }

    private static func edge(_ color: UIColor) {
        color.withAlphaComponent(0.25).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 4, height: pg.height))
    }

    // ═══════════════════════════════════════════
    // MARK: - Risk Bar
    // ═══════════════════════════════════════════

    private static func riskBar(_ score: Int, _ y: CGFloat) {
        let zones: [(ClosedRange<CGFloat>, UIColor, String)] = [(0...0.4, sG, "LOW"), (0.4...0.7, sA, "MEDIUM"), (0.7...1.0, sR, "HIGH")]
        for (range, color, label) in zones {
            let x = L + W * range.lowerBound; let w = W * (range.upperBound - range.lowerBound)
            color.withAlphaComponent(0.12).setFill(); UIRectFill(CGRect(x: x, y: y, width: w, height: 12))
            (label as NSString).draw(at: CGPoint(x: x + 3, y: y + 1), withAttributes: [.font: UIFont.systemFont(ofSize: 5.5, weight: .medium), .foregroundColor: UIColor(white: 0.5, alpha: 1)])
        }
        let mx = L + W * CGFloat(min(score, 100)) / 100
        black.setFill(); let tri = UIBezierPath(); tri.move(to: CGPoint(x: mx, y: y + 12)); tri.addLine(to: CGPoint(x: mx - 3, y: y + 17)); tri.addLine(to: CGPoint(x: mx + 3, y: y + 17)); tri.close(); tri.fill()
        txt("\(score)", pt(mx - 4, y + 17), .systemFont(ofSize: 6.5, weight: .bold), black)
    }

    // ═══════════════════════════════════════════
    // MARK: - Drawing Primitives
    // ═══════════════════════════════════════════

    @discardableResult private static func txt(_ s: String, _ p: CGPoint, _ f: UIFont, _ c: UIColor) -> CGFloat { (s as NSString).draw(at: p, withAttributes: [.font: f, .foregroundColor: c]); return p.y + f.lineHeight + 2 }
    private static func txtR(_ s: String, _ y: CGFloat, _ f: UIFont, _ c: UIColor) { let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c]; let sz = (s as NSString).size(withAttributes: a); (s as NSString).draw(at: CGPoint(x: pg.width - L - sz.width, y: y), withAttributes: a) }
    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func hdr(_ ref: String) -> CGFloat { black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: pg.width, height: 44)); txt("OceanCheck", pt(L, 12), BrandFont.uiFont(size: 15), white); txtR(ref, 16, .monospacedSystemFont(ofSize: 7, weight: .regular), UIColor(white: 0.4, alpha: 1)); return 56 }

    private static func footer(_ ref: String, _ page: Int, _ total: Int, _ ec: UIColor) {
        let fy = pg.height - 28; ruleC.setFill(); UIRectFill(CGRect(x: L, y: fy - 4, width: W, height: 0.5))
        let f = UIFont.systemFont(ofSize: 6, weight: .medium); let c = light
        txt("OceanCheck  \u{2022}  Confidential  \u{2022}  \(Date().formatted(date: .abbreviated, time: .omitted))", pt(L, fy), f, c)
        txtR("\(ref)  \u{2022}  Page \(page) of \(total)", fy, f, c)
    }

    private static func secT(_ title: String, at y: CGFloat, ctx: UIGraphicsPDFRendererContext, pn: inout Int, ref: String) -> CGFloat {
        black.setFill(); UIRectFill(CGRect(x: L, y: y + 1, width: 3, height: 11))
        let ny = txt(title.uppercased(), pt(L + 10, y), .systemFont(ofSize: 8.5, weight: .bold), black)
        ruleC.setFill(); UIRectFill(CGRect(x: L, y: ny, width: W, height: 0.5)); return ny + 5
    }

    private static func tR(_ l: String, _ v: String, _ y: CGFloat, _ alt: Bool, _ vc: UIColor? = nil) -> CGFloat {
        let vF = UIFont.systemFont(ofSize: 8.5, weight: .medium); let vX: CGFloat = L + 155; let vW: CGFloat = W - 161
        let s = NSMutableParagraphStyle(); s.lineBreakMode = .byWordWrapping
        let a: [NSAttributedString.Key: Any] = [.font: vF, .foregroundColor: vc ?? dark, .paragraphStyle: s]
        let sz = (v as NSString).boundingRect(with: CGSize(width: vW, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: a, context: nil)
        let h = max(15, min(sz.height + 3, 48))
        if alt { bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y - 1, width: W, height: h)) }
        txt(l, pt(L + 5, y), .systemFont(ofSize: 8.5), mid)
        (v as NSString).draw(with: CGRect(x: vX, y: y, width: vW, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: a, context: nil)
        return y + h
    }

    private static func lnkR(_ l: String, _ u: String, _ y: CGFloat, _ alt: Bool) -> CGFloat {
        let vX: CGFloat = L + 155; let h: CGFloat = 15
        if alt { bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y - 1, width: W, height: h)) }
        txt(l, pt(L + 5, y), .systemFont(ofSize: 8.5), mid)
        let d = u.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        let t = d.count > 48 ? String(d.prefix(45)) + "..." : d
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7.5, weight: .medium), .foregroundColor: UIColor(red: 0.07, green: 0.45, blue: 0.87, alpha: 1), .underlineStyle: NSUnderlineStyle.single.rawValue]
        (t as NSString).draw(at: CGPoint(x: vX, y: y), withAttributes: attrs)
        if let url = URL(string: u) { let sz = (t as NSString).size(withAttributes: attrs); UIGraphicsGetCurrentContext()?.setURL(url as CFURL, for: CGRect(x: vX, y: pg.height - y - sz.height, width: sz.width, height: sz.height)) }
        return y + h
    }

    private static func para(_ text: String, _ y: CGFloat, _ font: UIFont? = nil, _ color: UIColor? = nil) -> CGFloat {
        let f = font ?? .systemFont(ofSize: 8.5); let c = color ?? dark; let s = NSMutableParagraphStyle(); s.lineSpacing = 2
        let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c, .paragraphStyle: s]
        (text as NSString).draw(with: CGRect(x: L, y: y, width: W, height: 400), options: .usesLineFragmentOrigin, attributes: a, context: nil)
        return y + (text as NSString).boundingRect(with: CGSize(width: W, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: a, context: nil).height + 3
    }

    private static func bul(_ text: String, _ y: CGFloat, _ color: UIColor? = nil) -> CGFloat { let c = color ?? dark; txt("\u{2022}", pt(L + 6, y), .systemFont(ofSize: 8), c); return txt(text, pt(L + 16, y), .systemFont(ofSize: 7.5), c) }

    private static func sumRow(_ label: String, _ result: String, _ color: UIColor, at y: CGFloat, alt: Bool) -> CGFloat {
        let h: CGFloat = 18; if alt { bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: h)) }
        color.setFill(); UIRectFill(CGRect(x: L, y: y, width: 3, height: h))
        txt(label, pt(L + 10, y + 2), .systemFont(ofSize: 8, weight: .medium), dark)
        txt(result.uppercased(), pt(L + 250, y + 2), .systemFont(ofSize: 8, weight: .bold), color)
        return y + h
    }

    private static func metaRow(_ l: String, _ v: String, at y: CGFloat, x: CGFloat, w: CGFloat) -> CGFloat {
        txt(l, pt(x, y), .systemFont(ofSize: 7.5), mid); txt(v, pt(x + 75, y), .systemFont(ofSize: 7.5, weight: .medium), dark); return y + 13
    }

    private static func fitC(_ y: CGFloat, _ need: CGFloat, _ ctx: UIGraphicsPDFRendererContext, _ pn: inout Int, _ ref: String, _ ec: UIColor) -> CGFloat {
        if y + need > pg.height - FZ { footer(ref, pn, pn + 1, ec); ctx.beginPage(); pn += 1; watermark(); edge(ec); _ = hdr(ref); return 56 }; return y
    }

    // Helpers
    private static func outTitle(_ s: KYCCheck.CheckStatus) -> String { s == .passed ? "APPROVED" : s == .failed ? "DECLINED" : s == .requiresReview ? "PENDING REVIEW" : "INCOMPLETE" }
    private static func outSub(_ s: KYCCheck.CheckStatus) -> String { s == .passed ? "Customer due diligence requirements satisfied" : s == .failed ? "Verification requirements not met" : "Manual assessment required" }
    private static func buildSum(_ c: KYCCheck) -> String {
        let n = c.extractedName ?? c.customerName; let dt = (c.documentType ?? "identity document").replacingOccurrences(of: "_", with: " ").lowercased()
        var p = ["An identity verification was conducted for \(n) on \(c.createdAt.formatted(date: .long, time: .omitted))."]
        if c.documentType != nil { p.append("The subject presented a \(dt) which \(c.idWarnings?.isEmpty ?? true ? "was successfully verified" : "was verified with observations").") }
        if let s = c.amlStatus { p.append(s == "Approved" ? "AML screening returned no adverse findings." : s == "Declined" ? "AML screening identified adverse findings." : "AML screening requires manual review.") }
        if let s = c.poaStatus { p.append(s == "Approved" ? "Address confirmed." : "Address requires review.") }
        p.append(c.status == .passed ? "The subject has satisfied due diligence requirements." : c.status == .failed ? "Verification did not meet required standards." : "Further review required.")
        return p.joined(separator: " ")
    }
    private static func nameSim(_ a: String, _ b: String) -> Bool { let wa = Set(a.lowercased().split(separator: " ").map(String.init)); let wb = Set(b.lowercased().split(separator: " ").map(String.init)); return Double(wa.intersection(wb).count) / Double(max(wa.count, wb.count, 1)) >= 0.5 }
    private static func fD(_ s: String) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; guard let d = f.date(from: s) else { return s }; return d.formatted(date: .long, time: .omitted) }
    private static func isExp(_ s: String) -> Bool { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: s).map { $0 < Date() } ?? false }

    // ═══════════════════════════════════════════
    // MARK: - Compliance Packet Cover Sheet
    // ═══════════════════════════════════════════

    static func generateCoverSheet(vesselName: String, imoNumber: String, flagState: String, checks: [KYCCheck]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pg)
        return renderer.pdfData { ctx in
            ctx.beginPage()

            // Header bar
            black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: pg.width, height: 90))
            txt("OceanCheck", pt(L, 22), BrandFont.uiFont(size: 24), white)
            txt("COMPLIANCE PACKET", pt(L, 54), .systemFont(ofSize: 8.5, weight: .bold), UIColor(white: 0.5, alpha: 1))
            txtR("CONFIDENTIAL", 30, .systemFont(ofSize: 7, weight: .bold), UIColor(white: 0.4, alpha: 1))
            txtR(Date().formatted(date: .long, time: .omitted), 50, .systemFont(ofSize: 7), UIColor(white: 0.4, alpha: 1))

            var y: CGFloat = 110

            // Vessel name
            txt(vesselName.uppercased(), pt(L, y), .systemFont(ofSize: 24, weight: .bold), black)
            y += 34
            if !imoNumber.isEmpty { txt("IMO \(imoNumber)", pt(L, y), .systemFont(ofSize: 11), mid); y += 16 }
            if !flagState.isEmpty { txt("Flag State: \(flagState)", pt(L, y), .systemFont(ofSize: 11), mid); y += 16 }
            y += 16

            // Split checks into crew vs compliance
            let crew = checks.filter { $0.entityType.category == .crew }
            let compliance = checks.filter { $0.entityType.category != .crew }

            // Summary stats
            let crewPassed = crew.filter { $0.status == .passed }.count
            let compPassed = compliance.filter { $0.status == .passed }.count

            txt("VERIFICATION SUMMARY", pt(L, y), .systemFont(ofSize: 9, weight: .bold), dark); y += 20

            let cols: [(String, String, UIColor)] = [
                ("\(crew.count)", "Crew", black),
                ("\(crewPassed)", "Cleared", sG),
                ("\(compliance.count)", "Compliance", black),
                ("\(compPassed)", "Verified", sG)
            ]
            let colW: CGFloat = W / CGFloat(cols.count)
            for (i, col) in cols.enumerated() {
                let x = L + CGFloat(i) * colW
                txt(col.0, pt(x, y), .systemFont(ofSize: 28, weight: .bold), col.2)
                txt(col.1, pt(x, y + 32), .systemFont(ofSize: 9), mid)
            }
            y += 60

            // Divider
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 0.5)); y += 16

            // Crew roster
            txt("CREW ROSTER", pt(L, y), .systemFont(ofSize: 9, weight: .bold), dark); y += 18

            for check in crew {
                if y > pg.height - 60 { ctx.beginPage(); y = 48 }
                let statusColor = sc(check.status)
                statusColor.setFill(); UIRectFill(CGRect(x: L, y: y + 2, width: 4, height: 12))
                txt(check.displayName, pt(L + 12, y), .systemFont(ofSize: 10, weight: .medium), dark)
                let statusText = check.status == .passed ? "Clear" : check.status == .failed ? "Flagged" : "Pending"
                txtR(statusText, y, .systemFont(ofSize: 9, weight: .semibold), statusColor)
                let subtitle = [check.crewRank?.rawValue, check.documentType?.replacingOccurrences(of: "_", with: " ").capitalized].compactMap { $0 }.joined(separator: " \u{2022} ")
                if !subtitle.isEmpty { txt(subtitle, pt(L + 12, y + 13), .systemFont(ofSize: 8), mid) }
                y += 28
            }

            // UBO & Compliance section
            if !compliance.isEmpty {
                y += 8
                if y > pg.height - 60 { ctx.beginPage(); y = 48 }
                ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 0.5)); y += 16
                txt("BENEFICIAL OWNERS & COMPLIANCE", pt(L, y), .systemFont(ofSize: 9, weight: .bold), dark); y += 18

                for check in compliance {
                    if y > pg.height - 60 { ctx.beginPage(); y = 48 }
                    let statusColor = sc(check.status)
                    statusColor.setFill(); UIRectFill(CGRect(x: L, y: y + 2, width: 4, height: 12))
                    txt(check.displayName, pt(L + 12, y), .systemFont(ofSize: 10, weight: .medium), dark)
                    let statusText = check.status == .passed ? "Verified" : check.status == .failed ? "Failed" : "Pending"
                    txtR(statusText, y, .systemFont(ofSize: 9, weight: .semibold), statusColor)
                    let role = check.entityType.rawValue
                    let pct = check.ownershipPercent.map { " \u{2022} \(String(format: "%.0f", $0))%" } ?? ""
                    txt("\(role)\(pct)", pt(L + 12, y + 13), .systemFont(ofSize: 8), mid)
                    y += 28
                }
            }

            // Footer
            y = pg.height - 50
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 0.5))
            txt("Generated by OceanCheck on \(Date().formatted(date: .long, time: .shortened))", pt(L, y + 8), .systemFont(ofSize: 7), light)
            txt("This document is confidential and intended for compliance purposes only.", pt(L, y + 18), .systemFont(ofSize: 6.5), light)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - IMO Crew List PDF (FAL Form 5)
    // ═══════════════════════════════════════════

    static func generateCrewListPDF(vessel: Vessel, checks: [KYCCheck]) -> Data {
        let seafarers = checks.filter { $0.entityType.category == .crew }
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "dd MMM yyyy"

        let pdfInfo: [String: Any] = [
            kCGPDFContextTitle as String: "Crew List — \(vessel.name)",
            kCGPDFContextAuthor as String: "OceanCheck / SeaPay",
            kCGPDFContextCreator as String: "OceanCheck v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"
        ]
        let fmt = UIGraphicsPDFRendererFormat(); fmt.documentInfo = pdfInfo
        let renderer = UIGraphicsPDFRenderer(bounds: pg, format: fmt)

        return renderer.pdfData { ctx in
            var pn = 0

            ctx.beginPage(); pn += 1; watermark()

            // ── Header bar ──
            black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: pg.width, height: 90))
            txt("OceanCheck", pt(L, 22), BrandFont.uiFont(size: 24), white)
            txt("IMO CREW LIST — FAL FORM 5", pt(L, 54), .systemFont(ofSize: 8.5, weight: .bold), UIColor(white: 0.5, alpha: 1))
            txtR(Date().formatted(date: .long, time: .omitted), 30, .systemFont(ofSize: 7), UIColor(white: 0.4, alpha: 1))

            var y: CGFloat = 108

            // ── Vessel details ──
            txt(vessel.name.uppercased(), pt(L, y), .systemFont(ofSize: 20, weight: .bold), black); y += 28

            let colW: CGFloat = (W - 20) / 2
            var ly = y, ry = y
            func lRow(_ label: String, _ val: String) { txt(label, pt(L, ly), .systemFont(ofSize: 7, weight: .bold), mid); txt(val, pt(L + 70, ly), .systemFont(ofSize: 8), dark); ly += 14 }
            func rRow(_ label: String, _ val: String) { let rx = L + colW + 20; txt(label, pt(rx, ry), .systemFont(ofSize: 7, weight: .bold), mid); txt(val, pt(rx + 70, ry), .systemFont(ofSize: 8), dark); ry += 14 }

            lRow("IMO Number", vessel.imoNumber.isEmpty ? "—" : vessel.imoNumber)
            rRow("Call Sign", vessel.callSign.isEmpty ? "—" : vessel.callSign)
            lRow("Flag State", vessel.flagState.isEmpty ? "—" : vessel.flagState)
            rRow("Port of Registry", vessel.portOfRegistry.isEmpty ? "—" : vessel.portOfRegistry)
            lRow("Vessel Type", vessel.vesselType?.rawValue ?? "—")
            rRow("Gross Tonnage", vessel.grossTonnage.isEmpty ? "—" : vessel.grossTonnage)

            y = max(ly, ry) + 12
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 0.5)); y += 12

            // ── Table header ──
            let cols: [(String, CGFloat)] = [
                ("No.", 24), ("Family Name", 80), ("Given Names", 72), ("Rank", 60),
                ("Nationality", 48), ("DOB", 56), ("Document No.", 64), ("Expiry", 56)
            ]
            var hx = L
            bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y - 2, width: W, height: 16))
            for (label, width) in cols {
                txt(label, pt(hx, y), .systemFont(ofSize: 6.5, weight: .bold), mid)
                hx += width
            }
            y += 16

            // ── Crew rows ──
            for (i, check) in seafarers.enumerated() {
                y = fitC(y, 16, ctx, &pn, "", black)
                if pn > 1 && y < 60 { // re-draw header on new page
                    var nhx = L
                    bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y - 2, width: W, height: 16))
                    for (label, width) in cols { txt(label, pt(nhx, y), .systemFont(ofSize: 6.5, weight: .bold), mid); nhx += width }
                    y += 16
                }

                let nameParts = (check.extractedName ?? check.customerName).split(separator: " ", maxSplits: 1)
                let family = nameParts.count > 1 ? String(nameParts.last ?? "") : String(nameParts.first ?? "")
                let given = nameParts.count > 1 ? String(nameParts.first ?? "") : ""
                let passport = (check.documents ?? []).first(where: { $0.type == .passport && !$0.isArchived })

                // Alternating row background
                if i % 2 == 0 { bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y - 2, width: W, height: 14)) }

                var cx = L
                let font = UIFont.systemFont(ofSize: 7.5)
                let vals: [String] = [
                    "\(i + 1)",
                    family,
                    given,
                    check.crewRank?.rawValue ?? "—",
                    check.nationality ?? "—",
                    check.dateOfBirth ?? "—",
                    check.documentNumber ?? passport?.documentNumber ?? "—",
                    check.expiryDate ?? (passport?.expiryDate.map { dateFmt.string(from: $0) } ?? "—")
                ]
                for (vi, (_, width)) in cols.enumerated() {
                    let val = vi < vals.count ? vals[vi] : ""
                    txt(val, pt(cx, y), font, dark)
                    cx += width
                }
                y += 14
            }

            // ── Summary ──
            y += 10
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 0.5)); y += 12
            txt("Total crew on board: \(seafarers.count)", pt(L, y), .systemFont(ofSize: 9, weight: .bold), dark); y += 20
            txt("Master's signature: ____________________________", pt(L, y), .systemFont(ofSize: 8), mid); y += 14
            txt("Date: \(Date().formatted(date: .long, time: .omitted))", pt(L, y), .systemFont(ofSize: 8), mid)

            // ── Footer ──
            let fy = pg.height - 50
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: fy, width: W, height: 0.5))
            txt("Generated by OceanCheck on \(Date().formatted(date: .long, time: .shortened))", pt(L, fy + 8), .systemFont(ofSize: 7), light)
            txt("IMO FAL Form 5 — Crew List. This document is generated for operational use.", pt(L, fy + 18), .systemFont(ofSize: 6.5), light)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - UBO Compliance Report
    // ═══════════════════════════════════════════

    static func generateUBOReport(vessel: Vessel, structure: OwnershipStructure, checks: [KYCCheck]) -> Data {
        let ref = "UBO-\(String(vessel.id.prefix(8)).uppercased())"
        var pn = 0
        let allVerified = structure.shareholders.filter(\.isUBO).allSatisfy { sh in
            guard let cid = sh.checkId, let c = checks.first(where: { $0.id == cid }) else { return false }
            return c.status == .passed
        }
        let edgeColor = allVerified ? sG : sA

        let renderer = UIGraphicsPDFRenderer(bounds: pg)
        return renderer.pdfData { ctx in
            ctx.beginPage(); pn += 1; watermark(); edge(edgeColor)

            // Header
            black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: pg.width, height: 90))
            txt("OceanCheck", pt(L, 22), BrandFont.uiFont(size: 24), white)
            txt("UBO COMPLIANCE REPORT", pt(L, 54), .systemFont(ofSize: 8.5, weight: .bold), UIColor(white: 0.5, alpha: 1))
            txtR("CONFIDENTIAL", 30, .systemFont(ofSize: 7, weight: .bold), UIColor(white: 0.4, alpha: 1))
            txtR(ref, 44, .monospacedSystemFont(ofSize: 7, weight: .regular), UIColor(white: 0.4, alpha: 1))
            txtR(Date().formatted(date: .long, time: .omitted), 58, .systemFont(ofSize: 7), UIColor(white: 0.4, alpha: 1))

            var y: CGFloat = 108

            // Vessel
            txt(vessel.name.uppercased(), pt(L, y), .systemFont(ofSize: 20, weight: .bold), black); y += 28
            var la = true
            func row(_ l: String, _ v: String) { y = tR(l, v, y, la); la.toggle() }
            if !vessel.imoNumber.isEmpty { row("IMO Number", vessel.imoNumber) }
            if !vessel.flagState.isEmpty { row("Flag State", vessel.flagState) }
            if let vt = vessel.vesselType { row("Vessel Type", vt.rawValue) }
            y += 12

            // Ownership type
            y = secT("Ownership Structure", at: y, ctx: ctx, pn: &pn, ref: ref)
            la = true
            row("Type", structure.isDirectOwnership ? "Direct Individual Ownership" : "Corporate / SPV")
            if let spv = structure.spv {
                row("SPV Name", spv.name)
                row("Jurisdiction", spv.jurisdiction)
                row("Registration", spv.registrationNumber)
                if !spv.incorporationDate.isEmpty { row("Incorporated", spv.incorporationDate) }
            }
            y += 12

            // UBOs
            y = fitC(y, 30, ctx, &pn, ref, edgeColor)
            y = secT("Ultimate Beneficial Owners (>25%)", at: y, ctx: ctx, pn: &pn, ref: ref)
            for sh in structure.shareholders where sh.isUBO {
                y = fitC(y, 20, ctx, &pn, ref, edgeColor)
                let check = sh.checkId.flatMap { cid in checks.first { $0.id == cid } }
                let status = check?.status ?? .pending
                let sColor = sc(status)
                sColor.setFill(); UIRectFill(CGRect(x: L, y: y + 2, width: 4, height: 12))
                txt(sh.name, pt(L + 10, y), .systemFont(ofSize: 9, weight: .medium), dark)
                txt("\(String(format: "%.0f", sh.ownershipPercent))%", pt(L + 200, y), .systemFont(ofSize: 9), mid)
                let statusText = status == .passed ? "VERIFIED" : status == .failed ? "FAILED" : "PENDING"
                txtR(statusText, y, .systemFont(ofSize: 8, weight: .bold), sColor)
                y += 16

                // AML status if verified
                if let check, check.amlStatus != nil {
                    txt("  AML: \(check.amlStatus ?? "—")", pt(L + 10, y), .systemFont(ofSize: 7.5), mid)
                    if let score = check.amlScore { txt("Score: \(score)", pt(L + 120, y), .systemFont(ofSize: 7.5), mid) }
                    y += 12
                }
            }
            y += 8

            // Other shareholders
            let others = structure.shareholders.filter { !$0.isUBO }
            if !others.isEmpty {
                y = fitC(y, 20, ctx, &pn, ref, edgeColor)
                txt("Other shareholders (below 25%)", pt(L, y), .systemFont(ofSize: 7.5, weight: .bold), mid); y += 14
                for sh in others {
                    y = fitC(y, 14, ctx, &pn, ref, edgeColor)
                    txt("\(sh.name) — \(String(format: "%.0f", sh.ownershipPercent))%\(sh.isCompany ? " (corporate)" : "")", pt(L + 10, y), .systemFont(ofSize: 7.5), mid)
                    y += 12
                }
            }
            y += 12

            // Directors
            y = fitC(y, 30, ctx, &pn, ref, edgeColor)
            y = secT("Directors / Officers", at: y, ctx: ctx, pn: &pn, ref: ref)
            for dir in structure.directors {
                y = fitC(y, 16, ctx, &pn, ref, edgeColor)
                let check = dir.checkId.flatMap { cid in checks.first { $0.id == cid } }
                let status = check?.status ?? .pending
                let sColor = sc(status)
                sColor.setFill(); UIRectFill(CGRect(x: L, y: y + 2, width: 4, height: 12))
                txt(dir.name, pt(L + 10, y), .systemFont(ofSize: 9, weight: .medium), dark)
                let statusText = status == .passed ? "VERIFIED" : "PENDING"
                txtR(statusText, y, .systemFont(ofSize: 8, weight: .bold), sColor)
                y += 16
            }
            y += 16

            // Verdict
            y = fitC(y, 50, ctx, &pn, ref, edgeColor)
            let verdict = allVerified ? "COMPLIANT" : "INCOMPLETE"
            let vc = allVerified ? sG : sA
            let vR = CGRect(x: L, y: y, width: W, height: 40)
            vc.withAlphaComponent(0.06).setFill(); UIBezierPath(roundedRect: vR, cornerRadius: 4).fill()
            black.setFill(); UIRectFill(CGRect(x: L, y: y, width: 4, height: 40))
            vc.setFill(); UIRectFill(CGRect(x: L + 4, y: y, width: 2, height: 40))
            txt(verdict, pt(L + 16, y + 6), .systemFont(ofSize: 16, weight: .bold), vc)
            let verdictSub = allVerified ? "All beneficial owners verified and screened" : "Verification incomplete — action required"
            txt(verdictSub, pt(L + 16, y + 24), .systemFont(ofSize: 8), mid)
            y += 54

            // Footer
            let fy = pg.height - 50
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: fy, width: W, height: 0.5))
            txt("Generated by OceanCheck on \(Date().formatted(date: .long, time: .shortened))", pt(L, fy + 8), .systemFont(ofSize: 7), light)
            txt("UBO Compliance Report \(ref). This document is confidential.", pt(L, fy + 18), .systemFont(ofSize: 6.5), light)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Certificate Summary (for class/port/insurance)
    // ═══════════════════════════════════════════

    static func generateCertificateSummary(vessel: Vessel) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pg)
        return renderer.pdfData { ctx in
            ctx.beginPage(); watermark()

            black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: pg.width, height: 90))
            txt("OceanCheck", pt(L, 22), BrandFont.uiFont(size: 24), white)
            txt("VESSEL CERTIFICATE SUMMARY", pt(L, 54), .systemFont(ofSize: 8.5, weight: .bold), UIColor(white: 0.5, alpha: 1))
            txtR(Date().formatted(date: .long, time: .omitted), 30, .systemFont(ofSize: 7), UIColor(white: 0.4, alpha: 1))

            var y: CGFloat = 108
            txt(vessel.name.uppercased(), pt(L, y), .systemFont(ofSize: 20, weight: .bold), black); y += 26
            if !vessel.imoNumber.isEmpty { txt("IMO \(vessel.imoNumber) \u{2022} \(vessel.flagState) \u{2022} \(vessel.portOfRegistry)", pt(L, y), .systemFont(ofSize: 9), mid); y += 20 }

            y += 4
            // Table header
            bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 16))
            txt("Certificate", pt(L + 4, y + 2), .systemFont(ofSize: 7, weight: .bold), mid)
            txt("Number", pt(L + 200, y + 2), .systemFont(ofSize: 7, weight: .bold), mid)
            txt("Expiry", pt(L + 340, y + 2), .systemFont(ofSize: 7, weight: .bold), mid)
            txt("Status", pt(L + 430, y + 2), .systemFont(ofSize: 7, weight: .bold), mid)
            y += 18

            let dfmt = DateFormatter(); dfmt.dateFormat = "dd MMM yyyy"
            for (i, doc) in (vessel.documents ?? []).enumerated() {
                if y > pg.height - 60 { ctx.beginPage(); y = 48; watermark() }
                if i % 2 == 0 { bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 14)) }
                let sc = doc.status == .valid ? sG : doc.status == .expired ? sR : sA
                sc.setFill(); UIRectFill(CGRect(x: L, y: y + 2, width: 3, height: 10))
                txt(doc.displayName, pt(L + 8, y + 1), .systemFont(ofSize: 8), dark)
                txt(doc.documentNumber ?? "—", pt(L + 200, y + 1), .systemFont(ofSize: 8), mid)
                txt(doc.expiryDate.map { dfmt.string(from: $0) } ?? "—", pt(L + 340, y + 1), .systemFont(ofSize: 8), sc)
                txt(doc.statusLabel, pt(L + 430, y + 1), .systemFont(ofSize: 7, weight: .semibold), sc)
                y += 14
            }

            let fy = pg.height - 40
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: fy, width: W, height: 0.5))
            txt("Generated by OceanCheck \u{2022} \(Date().formatted(date: .long, time: .shortened))", pt(L, fy + 8), .systemFont(ofSize: 7), light)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Authority Packet (flag state, insurance)
    // ═══════════════════════════════════════════

    static func generateAuthorityPacket(vessel: Vessel, checks: [KYCCheck], title: String, includeAML: Bool = false, includeUBO: Bool = false) -> Data {
        let crew = checks.filter { $0.entityType.category == .crew }
        let compliance = checks.filter { $0.entityType.category == .ownership }

        var pages: [Data] = []

        // Cover + cert summary
        pages.append(generateCertificateSummary(vessel: vessel))

        // Crew list
        if !crew.isEmpty { pages.append(generateCrewListPDF(vessel: vessel, checks: checks)) }

        // Compliance packet cover (has crew + UBO sections)
        if includeAML || includeUBO {
            pages.append(generateCoverSheet(vesselName: vessel.name, imoNumber: vessel.imoNumber, flagState: vessel.flagState, checks: checks))
        }

        // UBO report if applicable
        if includeUBO, let os = vessel.ownershipStructure {
            pages.append(generateUBOReport(vessel: vessel, structure: os, checks: compliance))
        }

        // Merge all pages
        let merged = NSMutableData()
        UIGraphicsBeginPDFContextToData(merged, .zero, nil)
        for pdf in pages {
            guard let provider = CGDataProvider(data: pdf as CFData), let doc = CGPDFDocument(provider) else { continue }
            for i in 1...doc.numberOfPages {
                guard let page = doc.page(at: i) else { continue }
                let box = page.getBoxRect(.mediaBox)
                UIGraphicsBeginPDFPageWithInfo(box, nil)
                guard let ctx = UIGraphicsGetCurrentContext() else { continue }
                ctx.translateBy(x: 0, y: box.height); ctx.scaleBy(x: 1, y: -1); ctx.drawPDFPage(page)
            }
        }
        UIGraphicsEndPDFContext()
        return merged as Data
    }

    // ═══════════════════════════════════════════
    // MARK: - Sanitized Crew Summary (charter DD)
    // ═══════════════════════════════════════════

    static func generateSanitizedCrewSummary(vessel: Vessel, checks: [KYCCheck]) -> Data {
        let crew = checks.filter { $0.entityType.category == .crew }
        let renderer = UIGraphicsPDFRenderer(bounds: pg)
        return renderer.pdfData { ctx in
            ctx.beginPage(); watermark()

            black.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: pg.width, height: 90))
            txt("OceanCheck", pt(L, 22), BrandFont.uiFont(size: 24), white)
            txt("CREW QUALIFICATION SUMMARY", pt(L, 54), .systemFont(ofSize: 8.5, weight: .bold), UIColor(white: 0.5, alpha: 1))
            txtR("COMMERCIAL IN CONFIDENCE", 30, .systemFont(ofSize: 7, weight: .bold), UIColor(white: 0.4, alpha: 1))

            var y: CGFloat = 108
            txt(vessel.name.uppercased(), pt(L, y), .systemFont(ofSize: 20, weight: .bold), black); y += 26
            txt("This summary does not contain personal identification data.", pt(L, y), .systemFont(ofSize: 8), mid); y += 20

            // Table
            bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 16))
            txt("Rank", pt(L + 4, y + 2), .systemFont(ofSize: 7, weight: .bold), mid)
            txt("Nationality", pt(L + 100, y + 2), .systemFont(ofSize: 7, weight: .bold), mid)
            txt("KYC Status", pt(L + 200, y + 2), .systemFont(ofSize: 7, weight: .bold), mid)
            txt("Key Certs", pt(L + 300, y + 2), .systemFont(ofSize: 7, weight: .bold), mid)
            y += 18

            for (i, check) in crew.enumerated() {
                if y > pg.height - 60 { ctx.beginPage(); y = 48; watermark() }
                if i % 2 == 0 { bgAlt.setFill(); UIRectFill(CGRect(x: L, y: y, width: W, height: 14)) }

                let statusC = sc(check.status)
                txt(check.crewRank?.rawValue ?? "—", pt(L + 4, y + 1), .systemFont(ofSize: 8), dark)
                txt(check.nationality ?? "—", pt(L + 100, y + 1), .systemFont(ofSize: 8), mid)
                statusC.setFill(); UIRectFill(CGRect(x: L + 200, y: y + 4, width: 4, height: 6))
                let statusText = check.status == .passed ? "Verified" : check.status == .failed ? "Failed" : "Pending"
                txt(statusText, pt(L + 208, y + 1), .systemFont(ofSize: 7, weight: .semibold), statusC)

                // Key certs summary
                let docs = (check.documents ?? []).filter { !$0.isArchived }
                let valid = docs.filter { $0.status == .valid }.count
                txt("\(valid)/\(docs.count) valid", pt(L + 300, y + 1), .systemFont(ofSize: 8), valid == docs.count ? sG : sA)
                y += 14
            }

            let fy = pg.height - 40
            ruleC.setFill(); UIRectFill(CGRect(x: L, y: fy, width: W, height: 0.5))
            txt("Sanitized summary — personal identification data omitted \u{2022} \(Date().formatted(date: .long, time: .shortened))", pt(L, fy + 8), .systemFont(ofSize: 7), light)
        }
    }
}
