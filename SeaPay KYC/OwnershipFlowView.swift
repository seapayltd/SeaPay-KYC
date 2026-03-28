//
//  OwnershipFlowView.swift
//  OceanCheck
//
//  UBO verification via document chain discovery.
//  Upload documents → AI identifies & extracts → ownership tree builds itself.
//

import SwiftUI
import PDFKit

struct OwnershipFlowView: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String
    @Environment(\.dismiss) private var dismiss

    // Ownership type
    @State private var ownershipType: OwnershipEntityType = .company

    // Ownership tree (builds as documents are uploaded)
    @State private var entities: [OwnershipEntity] = []
    @State private var persons: [OwnershipPerson] = []

    // Document capture
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var capturedData: Data?
    @State private var analyzing = false
    @State private var analysisResult = ""

    // Verification
    @State private var activeCheck: KYCCheck?
    @State private var inviteCheck: KYCCheck?
    @State private var showReport = false
    @State private var reportData: Data?

    private var vessel: Vessel? { vm.vessels.first { $0.id == vesselId } }
    private var ubos: [OwnershipPerson] { persons.filter { $0.ownershipPercent >= 25 } }
    private var allUBOsVerified: Bool { ubos.allSatisfy { p in p.checkId != nil && vm.checks.first(where: { $0.id == p.checkId })?.status == .passed } }
    private var canGenerateReport: Bool { !persons.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Entity type selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OWNERSHIP TYPE").font(Typo.meta).foregroundStyle(.secondary).tracking(0.6)
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(OwnershipEntityType.allCases) { type in
                                    Button {
                                        withAnimation(.smooth(duration: 0.2)) { ownershipType = type }
                                    } label: {
                                        Text(type.rawValue)
                                            .font(Typo.meta).fontWeight(.medium)
                                            .foregroundStyle(ownershipType == type ? Color.surface : .secondary)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(ownershipType == type ? Color.primary : Color.surfaceMuted)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 12)

                    // Upload button — always at top
                    uploadSection

                    // Analysis progress
                    if analyzing { analysisSection }

                    // Ownership tree
                    if !entities.isEmpty || !persons.isEmpty {
                        ownershipTree
                    } else if !analyzing {
                        emptyState
                    }

                    // Generate report
                    if canGenerateReport {
                        reportSection
                    }
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("UBO Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { saveAndDismiss() } }
            }
            .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
            .sheet(item: $inviteCheck) { InviteSheet(vm: vm, check: $0) }
            .fullScreenCover(isPresented: $showCamera) { CameraCapture(result: $capturedData).ignoresSafeArea() }
            .sheet(isPresented: $showFilePicker) {
                DocumentFilePicker { url in
                    showFilePicker = false
                    guard let url else { return }
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        capturedData = try? Data(contentsOf: url)
                    }
                }
            }
            .onChange(of: capturedData) { _, val in
                if let data = val { Task { await analyzeDocument(data) }; capturedData = nil }
            }
            .sheet(isPresented: $showReport) {
                if let data = reportData {
                    NavigationStack {
                        let url = writeTempPDF(data)
                        PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
                            .navigationTitle("UBO Report").navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) { Button("Done") { showReport = false } }
                                ToolbarItem(placement: .primaryAction) {
                                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                }
                            }
                    }
                }
            }
            .onAppear { loadExisting() }
        }
    }

    // ═══════════ UPLOAD SECTION ═══════════

    private var uploadSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { showCamera = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera").font(Typo.body)
                        Text("Photo").font(Typo.body)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.primary).foregroundStyle(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button { showFilePicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus").font(Typo.body)
                        Text("File").font(Typo.body)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.surfaceMuted).foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("Upload corporate documents, passports, or shareholder registers").font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    // ═══════════ ANALYSIS ═══════════

    private var analysisSection: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Analyzing document...").font(Typo.meta).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    // ═══════════ EMPTY STATE ═══════════

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            Image(systemName: "doc.viewfinder").font(.system(size: 44)).foregroundStyle(.quaternary)
            Text("Upload your first document").font(Typo.context)
            VStack(spacing: 6) {
                Text("Start with any of these:").font(Typo.meta).foregroundStyle(.secondary)
                if ownershipType == .trust {
                    docHint("Trust Deed / Agreement")
                    docHint("Beneficiary List")
                    docHint("Trustee Passport")
                    docHint("Settlor Identification")
                } else if ownershipType == .partnership {
                    docHint("Partnership Agreement")
                    docHint("Partner Passport")
                } else {
                    docHint("Certificate of Incorporation")
                    docHint("Shareholder Register")
                    docHint("Articles of Association")
                    docHint("Passport of a known owner")
                }
            }
            Spacer(minLength: 40)
        }
    }

    private func docHint(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc").font(Typo.meta).foregroundStyle(.tertiary)
            Text(text).font(Typo.meta).foregroundStyle(.secondary)
        }
    }

    // ═══════════ OWNERSHIP TREE ═══════════

    private var ownershipTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary card
            let totalUBOs = ubos.count
            let unverifiedUBOs = ubos.filter { $0.checkId == nil }
            let totalPersons = persons.count
            let verifiedPersons = persons.filter { $0.checkId != nil }.count

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: unverifiedUBOs.isEmpty && totalUBOs > 0 ? "checkmark.shield" : "exclamationmark.triangle")
                        .font(.system(size: 14))
                        .foregroundStyle(unverifiedUBOs.isEmpty && totalUBOs > 0 ? Color.clear_ : Color.review)
                    Text(unverifiedUBOs.isEmpty && totalUBOs > 0
                         ? "All UBOs verified"
                         : totalUBOs == 0
                         ? "\(totalPersons) person\(totalPersons == 1 ? "" : "s") identified"
                         : "\(totalUBOs) UBO\(totalUBOs == 1 ? "" : "s") identified, \(unverifiedUBOs.count) passport\(unverifiedUBOs.count == 1 ? "" : "s") needed"
                    )
                    .font(Typo.body).fontWeight(.medium)
                }
                if totalPersons > 0 {
                    ProgressBar(value: verifiedPersons, total: totalPersons)
                    Text("\(verifiedPersons)/\(totalPersons) persons verified").font(Typo.meta).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background((unverifiedUBOs.isEmpty && totalUBOs > 0 ? Color.clear_ : Color.review).opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16).padding(.bottom, 12)

            // Analysis result banner
            if !analysisResult.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "brain").font(Typo.meta).foregroundStyle(Color.clear_)
                    Text(analysisResult).font(Typo.meta).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
                .padding(10)
                .background(Color.clear_.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }

            // Entities (companies/trusts)
            if !entities.isEmpty {
                sectionHeader(ownershipType == .trust ? "TRUST ENTITY" : "CORPORATE ENTITIES")
                ForEach($entities) { $entity in
                    entityRow(entity)
                }
            }

            // Persons — grouped by role for trusts, flat for companies
            if !persons.isEmpty {
                if ownershipType == .trust {
                    let trustees = persons.filter { $0.role == .trustee }
                    let settlors = persons.filter { $0.role == .settlor }
                    let protectors = persons.filter { $0.role == .protector }
                    let beneficiaries = persons.filter { $0.role == .beneficiary }
                    let others = persons.filter { [.shareholder, .director, .corporateShareholder].contains($0.role) }

                    if !settlors.isEmpty { trustRoleSection("SETTLORS", persons: settlors) }
                    if !trustees.isEmpty { trustRoleSection("TRUSTEES", persons: trustees) }
                    if !protectors.isEmpty { trustRoleSection("PROTECTORS", persons: protectors) }
                    if !beneficiaries.isEmpty { trustRoleSection("BENEFICIARIES", persons: beneficiaries) }
                    if !others.isEmpty { trustRoleSection("OTHER PERSONS", persons: others) }
                } else {
                    sectionHeader("PERSONS IDENTIFIED")
                    ForEach($persons) { $person in
                        personRow($person)
                    }
                }
            }

            // Action required — unverified UBOs
            if !unverifiedUBOs.isEmpty {
                sectionHeader("ACTION REQUIRED")
                ForEach(unverifiedUBOs) { person in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.review)
                            .frame(width: 3, height: 32)
                            .padding(.trailing, 10).padding(.leading, 16)
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").font(Typo.meta).foregroundStyle(Color.review)
                            Text("\(person.name) — \(String(format: "%.0f", person.ownershipPercent))% owner, passport needed")
                                .font(Typo.meta).foregroundStyle(Color.review)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder
    private func trustRoleSection(_ title: String, persons: [OwnershipPerson]) -> some View {
        sectionHeader(title)
        ForEach(persons) { person in
            // Can't use $person with local array — use by-id lookup
            if let idx = self.persons.firstIndex(where: { $0.id == person.id }) {
                personRow($persons[idx])
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(Typo.meta).foregroundStyle(.tertiary)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 6)
    }

    private func entityRow(_ entity: OwnershipEntity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2").font(Typo.body).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name).font(Typo.body)
                HStack(spacing: 6) {
                    if !entity.jurisdiction.isEmpty { Text(entity.jurisdiction).font(Typo.meta).foregroundStyle(.secondary) }
                    if !entity.registrationNumber.isEmpty { Text(entity.registrationNumber).font(Typo.meta).foregroundStyle(.tertiary) }
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(Typo.body).foregroundStyle(Color.clear_)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private func personRow(_ person: Binding<OwnershipPerson>) -> some View {
        let p = person.wrappedValue
        let isUBO = p.ownershipPercent >= 25
        return HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle().fill(isUBO ? Color.review.opacity(0.1) : Color.surfaceMuted).frame(width: 36, height: 36)
                Image(systemName: p.role == .director ? "person.badge.shield.checkmark" : "person").font(Typo.body)
                    .foregroundStyle(isUBO ? Color.review : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(Typo.body)
                HStack(spacing: 6) {
                    Text(p.role.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                    if p.ownershipPercent > 0 {
                        Text("\(String(format: "%.0f", p.ownershipPercent))%").font(Typo.meta).fontWeight(.medium)
                            .foregroundStyle(isUBO ? Color.review : .secondary)
                    }
                    if isUBO { Text("UBO").font(Typo.meta).fontWeight(.bold).foregroundStyle(Color.review) }
                }
            }

            Spacer()

            // Verify / Invite / Status
            if let cid = p.checkId, let check = vm.checks.first(where: { $0.id == cid }) {
                StatusBadge(status: check.status)
            } else if p.role != .corporateShareholder {
                // Verify or invite — for any natural person
                Menu {
                    Button {
                        let et: KYCCheck.EntityType = isUBO ? .ubo : p.role == .director ? .directorOfficer : p.role == .trustee ? .trustee : p.role == .settlor ? .settlor : p.role == .protector ? .protector : p.role == .beneficiary ? .beneficiary : .owner
                        let check = vm.createCheck(customerName: p.name, entityType: et, vesselId: vesselId, ownershipPercent: p.ownershipPercent > 0 ? p.ownershipPercent : nil)
                        person.wrappedValue.checkId = check.id
                        activeCheck = check
                    } label: { Label("Scan Passport", systemImage: "camera.viewfinder") }

                    if AppConfiguration.hasWorkflow && vm.isOnline {
                        Button {
                            let et: KYCCheck.EntityType = isUBO ? .ubo : p.role == .director ? .directorOfficer : p.role == .trustee ? .trustee : p.role == .settlor ? .settlor : p.role == .protector ? .protector : p.role == .beneficiary ? .beneficiary : .owner
                            let check = vm.createCheck(customerName: p.name, entityType: et, vesselId: vesselId, ownershipPercent: p.ownershipPercent > 0 ? p.ownershipPercent : nil)
                            person.wrappedValue.checkId = check.id
                            inviteCheck = check
                        } label: { Label("Send Invite", systemImage: "paperplane") }
                    }
                } label: {
                    Text("Verify").font(Typo.meta).fontWeight(.medium)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(isUBO ? Color.primary : Color.surfaceMuted)
                        .foregroundStyle(isUBO ? Color.surface : .primary)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(isUBO ? Color.review.opacity(0.03) : Color.clear)
    }

    // ═══════════ REPORT SECTION ═══════════

    private var reportSection: some View {
        VStack(spacing: 10) {
            Divider().padding(.horizontal, 20).padding(.top, 16)

            Button {
                saveStructure()
                if let data = vm.generateUBOReport(vesselId: vesselId) {
                    reportData = data; showReport = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                    Text("Generate UBO Report")
                }
                .font(Typo.body)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(canGenerateReport ? Color.primary : Color.surfaceMuted)
                .foregroundStyle(canGenerateReport ? Color.surface : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canGenerateReport)
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    // ═══════════ AI ANALYSIS ═══════════

    private func analyzeDocument(_ data: Data) async {
        await MainActor.run { analyzing = true; analysisResult = "" }

        guard !KeychainService.get(.claudeAPIKey).isNilOrEmpty else {
            await MainActor.run { analyzing = false; analysisResult = "No Claude API key — add documents manually" }
            return
        }

        let trustContext = ownershipType == .trust ? """
        This is a TRUST structure. Also extract trust-specific roles:
          "trustees": [{"name": "...", "is_company": false}],
          "settlors": [{"name": "..."}],
          "protectors": [{"name": "..."}],
          "beneficiaries": [{"name": "...", "percent": 0.0, "is_determinable": true}],
          "beneficiary_class": "Description of class beneficiaries if not individually named (e.g., 'Issue of the Settlor')"
        """ : ""

        let prompt = """
        Analyze this document for corporate ownership / KYC purposes. Determine what type of document it is and extract ALL relevant information.
        \(trustContext)
        Return ONLY JSON:
        {
          "document_type": "certificate_of_incorporation | shareholder_register | articles_of_association | passport | trust_deed | board_resolution | certificate_of_good_standing | certificate_of_incumbency | partnership_agreement | nominee_declaration | ubo_registry | other | not_a_document",
          "company": {"name": "...", "jurisdiction": "...", "registration_number": "...", "incorporation_date": "..."},
          "shareholders": [{"name": "...", "percent": 0.0, "is_company": false}],
          "directors": [{"name": "..."}],
          "trustees": [{"name": "...", "is_company": false}],
          "settlors": [{"name": "..."}],
          "protectors": [{"name": "..."}],
          "beneficiaries": [{"name": "...", "percent": 0.0}],
          "beneficiary_class": "...",
          "person": {"name": "...", "nationality": "...", "date_of_birth": "...", "document_number": "..."},
          "summary": "One-line description of what was found"
        }

        Set any section to null if not applicable. For passports, fill the person field. For corporate docs, fill company/shareholders/directors. For trust deeds, fill trustees/settlors/protectors/beneficiaries.
        """

        do {
            let text = try await ClaudeService.shared.extractDocument(imageData: data, prompt: prompt)
            var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
            if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
            if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }

            guard let jsonData = cleaned.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                await MainActor.run { analyzing = false; analysisResult = "Could not parse AI response" }
                return
            }

            let docType = json["document_type"] as? String ?? "other"
            let summary = json["summary"] as? String ?? "Document analyzed"

            if docType == "not_a_document" {
                await MainActor.run { analyzing = false; analysisResult = "Not a recognized document" }
                return
            }

            await MainActor.run {
                // Extract company info
                if let co = json["company"] as? [String: Any], let name = co["name"] as? String, !name.isEmpty {
                    if !entities.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                        entities.append(OwnershipEntity(
                            name: name,
                            jurisdiction: co["jurisdiction"] as? String ?? "",
                            registrationNumber: co["registration_number"] as? String ?? "",
                            incorporationDate: co["incorporation_date"] as? String ?? "",
                            documentType: docType
                        ))
                    }
                }

                // Extract shareholders
                if let shs = json["shareholders"] as? [[String: Any]] {
                    for sh in shs {
                        let name = sh["name"] as? String ?? ""
                        let pct = sh["percent"] as? Double ?? 0
                        let isCo = sh["is_company"] as? Bool ?? false
                        guard !name.isEmpty else { continue }
                        if !persons.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                            persons.append(OwnershipPerson(name: name, ownershipPercent: pct, role: isCo ? .corporateShareholder : .shareholder))
                        }
                    }
                }

                // Extract directors
                if let dirs = json["directors"] as? [[String: Any]] {
                    for d in dirs {
                        let name = d["name"] as? String ?? ""
                        guard !name.isEmpty else { continue }
                        if !persons.contains(where: { $0.name.lowercased() == name.lowercased() && $0.role == .director }) {
                            persons.append(OwnershipPerson(name: name, ownershipPercent: 0, role: .director))
                        }
                    }
                }

                // Extract trust roles
                for (key, role) in [("trustees", OwnershipPerson.Role.trustee), ("settlors", .settlor), ("protectors", .protector), ("beneficiaries", .beneficiary)] {
                    if let arr = json[key] as? [[String: Any]] {
                        for item in arr {
                            guard let name = item["name"] as? String, !name.isEmpty else { continue }
                            if !persons.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                                let pct = item["percent"] as? Double ?? 0
                                persons.append(OwnershipPerson(name: name, ownershipPercent: pct, role: role))
                            }
                        }
                    }
                }

                // Extract passport person
                if let person = json["person"] as? [String: Any], let name = person["name"] as? String, !name.isEmpty {
                    if persons.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                        analysisResult = "Passport identified: \(name)"
                    } else {
                        persons.append(OwnershipPerson(name: name, ownershipPercent: 0, role: .shareholder))
                        analysisResult = "New person identified: \(name)"
                    }
                } else {
                    analysisResult = summary
                }

                analyzing = false
            }
        } catch {
            await MainActor.run { analyzing = false; analysisResult = "Analysis failed: \(error.localizedDescription.prefix(40))" }
        }
    }

    // ═══════════ PERSISTENCE ═══════════

    private func loadExisting() {
        // Restore from saved structure if exists
        if let os = vessel?.ownershipStructure {
            // Restore entity type
            ownershipType = os.resolvedEntityType

            if let spv = os.spv {
                entities = [OwnershipEntity(name: spv.name, jurisdiction: spv.jurisdiction, registrationNumber: spv.registrationNumber, incorporationDate: spv.incorporationDate, documentType: "")]
            }
            persons = os.shareholders.map { sh in
                OwnershipPerson(id: sh.id, name: sh.name, ownershipPercent: sh.ownershipPercent, role: sh.isCompany ? .corporateShareholder : .shareholder, checkId: sh.checkId)
            } + os.directors.map { dir in
                OwnershipPerson(id: dir.id, name: dir.name, ownershipPercent: 0, role: .director, checkId: dir.checkId)
            }
            // Restore trust persons
            persons += (os.trustees ?? []).map { sh in
                OwnershipPerson(id: sh.id, name: sh.name, ownershipPercent: sh.ownershipPercent, role: .trustee, checkId: sh.checkId)
            }
            persons += (os.settlors ?? []).map { sh in
                OwnershipPerson(id: sh.id, name: sh.name, ownershipPercent: sh.ownershipPercent, role: .settlor, checkId: sh.checkId)
            }
            persons += (os.protectors ?? []).map { sh in
                OwnershipPerson(id: sh.id, name: sh.name, ownershipPercent: sh.ownershipPercent, role: .protector, checkId: sh.checkId)
            }
            persons += (os.beneficiaries ?? []).map { sh in
                OwnershipPerson(id: sh.id, name: sh.name, ownershipPercent: sh.ownershipPercent, role: .beneficiary, checkId: sh.checkId)
            }
            return
        }

        // First time — pre-populate from CoR registered owner if available
        guard let v = vessel else { return }
        if !v.registeredOwner.isEmpty {
            // Check if it looks like a company (contains Ltd, Limited, Inc, Corp, etc.)
            let upper = v.registeredOwner.uppercased()
            let corporateIndicators = ["LTD", "LIMITED", "INC", "CORP", "LLC", "GMBH", "S.A.", "SA ", "BV ", "NV "]
            let isCompany = corporateIndicators.contains(where: { upper.contains($0) })

            if isCompany {
                entities.append(OwnershipEntity(name: v.registeredOwner, jurisdiction: v.flagState, registrationNumber: "", incorporationDate: "", documentType: "CoR"))
                analysisResult = "Registered owner from CoR: \(v.registeredOwner) (corporate)"
            } else {
                persons.append(OwnershipPerson(name: v.registeredOwner, ownershipPercent: 100, role: .shareholder))
                analysisResult = "Registered owner from CoR: \(v.registeredOwner)"
            }
        }
    }

    private func saveStructure() {
        let spv = entities.first.map { SPVEntity(name: $0.name, jurisdiction: $0.jurisdiction, registrationNumber: $0.registrationNumber, incorporationDate: $0.incorporationDate, documentPaths: []) }

        func toShareholder(_ p: OwnershipPerson) -> Shareholder {
            var sh = Shareholder(id: p.id, name: p.name, ownershipPercent: p.ownershipPercent, isCompany: p.role == .corporateShareholder)
            sh.checkId = p.checkId; return sh
        }

        let shareholders = persons.filter { [.shareholder, .corporateShareholder].contains($0.role) }.map(toShareholder)
        let directors = persons.filter { $0.role == .director }.map { p in
            var dir = Director(id: p.id, name: p.name); dir.checkId = p.checkId; return dir
        }

        var structure = OwnershipStructure(isDirectOwnership: entities.isEmpty && persons.count <= 1, spv: spv, shareholders: shareholders, directors: directors)
        structure.entityType = ownershipType

        // Trust-specific arrays
        if ownershipType == .trust {
            structure.trustees = persons.filter { $0.role == .trustee }.map(toShareholder)
            structure.settlors = persons.filter { $0.role == .settlor }.map(toShareholder)
            structure.protectors = persons.filter { $0.role == .protector }.map(toShareholder)
            structure.beneficiaries = persons.filter { $0.role == .beneficiary }.map(toShareholder)
        }

        guard var v = vessel else { return }
        v.ownershipStructure = structure
        vm.updateVessel(v)
    }

    private func saveAndDismiss() { saveStructure(); dismiss() }

    private func writeTempPDF(_ data: Data) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UBO_Report_\(UUID().uuidString.prefix(6)).pdf")
        try? data.write(to: url); return url
    }
}

// MARK: - Local Models (view state only, not persisted directly)

struct OwnershipEntity: Identifiable, Hashable {
    let id = UUID().uuidString
    var name: String
    var jurisdiction: String
    var registrationNumber: String
    var incorporationDate: String
    var documentType: String
}

struct OwnershipPerson: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var ownershipPercent: Double
    var role: Role
    var checkId: String?

    enum Role: String, Hashable { case shareholder = "Shareholder", corporateShareholder = "Corporate", director = "Director", trustee = "Trustee", settlor = "Settlor", protector = "Protector", beneficiary = "Beneficiary" }
}
