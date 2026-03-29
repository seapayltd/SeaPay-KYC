//
//  DocumentPortfolioView.swift
//  OceanCheck
//
//  Full document portfolio for a crew member.
//  Required docs auto-populated from rank + vessel type + flag.
//  Quick-add: tap missing → camera → expiry → done.
//

import SwiftUI
import UniformTypeIdentifiers

struct DocumentPortfolioView: View {
    @ObservedObject var vm: KYCViewModel
    let checkId: String
    @State private var addingDocType: MaritimeDocType?
    @State private var editingDoc: CrewDocument?

    private var check: KYCCheck { vm.checks.first(where: { $0.id == checkId }) ?? KYCCheck(id: checkId, customerId: "", customerName: "Unknown", agentId: "", agentName: "", checkType: .idVerification, status: .pending, entityType: .seafarer, createdAt: Date()) }
    private var portfolio: [KYCViewModel.PortfolioItem] { vm.documentPortfolio(for: check) }

    private var validCount: Int { portfolio.filter { $0.document?.status == .valid }.count }
    private var requiredCount: Int { portfolio.filter(\.required).count }
    private var expiringCount: Int { portfolio.filter { $0.document?.status == .expiringSoon }.count }
    private var expiredCount: Int { portfolio.filter { $0.document?.status == .expired }.count }

    private var needsAttention: [KYCViewModel.PortfolioItem] {
        portfolio.filter { item in
            if let doc = item.document {
                return doc.status == .expired || doc.status == .expiringSoon
            }
            return item.required && item.document == nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Readiness dashboard
                ReadinessCard(
                    completed: validCount,
                    total: requiredCount,
                    expiringCount: expiringCount,
                    expiredCount: expiredCount
                )
                .padding(.horizontal, 16).padding(.top, 12)

                // Needs Attention section
                if !needsAttention.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEEDS ATTENTION")
                            .font(Typo.meta).foregroundStyle(Color.review).tracking(0.8)
                            .padding(.horizontal, 20)

                        ForEach(needsAttention) { item in
                            DocRow(item: item, urgent: true) {
                                if let doc = item.document, !doc.imagePaths.isEmpty {
                                    editingDoc = doc
                                } else {
                                    addingDocType = item.type
                                }
                            }
                        }
                    }
                }

                // Rank picker
                if check.entityType == .seafarer && check.crewRank == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "person.text.rectangle").font(.system(size: 28)).foregroundStyle(.quaternary)
                        Text("Set crew rank").font(Typo.context)
                        Text("Required documents are determined by rank, vessel type, and flag state").font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center)

                        Menu {
                            ForEach(CrewRank.allCases) { rank in
                                Button(rank.rawValue) {
                                    withAnimation { vm.setCrewRank(rank, for: checkId) }
                                }
                            }
                        } label: {
                            Text("Select Rank")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 48)
                    }
                    .padding(.vertical, 16).padding(.horizontal, 32)
                } else if check.entityType == .seafarer {
                    // Current rank indicator
                    HStack {
                        Text("Rank").font(Typo.meta).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(CrewRank.allCases) { rank in
                                Button(rank.rawValue) {
                                    withAnimation { vm.setCrewRank(rank, for: checkId) }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(check.crewRank?.rawValue ?? "").font(Typo.body)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Document list grouped by category
                let grouped = Dictionary(grouping: portfolio, by: { $0.type.category })
                let categories = MaritimeDocCategory.allCases.filter { grouped[$0] != nil }

                ForEach(categories) { category in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.rawValue)
                            .font(Typo.meta).foregroundStyle(.tertiary)
                            .padding(.horizontal, 20).padding(.top, 14)

                        ForEach(grouped[category]!) { item in
                            DocRow(item: item, urgent: item.required && item.document == nil) {
                                if let doc = item.document, !doc.imagePaths.isEmpty {
                                    editingDoc = doc
                                } else {
                                    addingDocType = item.type
                                }
                            }
                        }
                    }
                }

                // Add custom document
                Button {
                    addingDocType = .other
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle").font(Typo.body)
                        Text("Add Document").font(Typo.body)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 32)
            }
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $addingDocType) { docType in
            QuickAddSheet(vm: vm, checkId: checkId, docType: docType)
        }
        .sheet(item: $editingDoc) { doc in
            DocumentDetailSheet(vm: vm, checkId: checkId, document: doc)
        }
    }

    private func statCell(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Typo.stat).monospacedDigit().foregroundStyle(color)
            Text(label).font(Typo.meta).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Document Row

private struct DocRow: View {
    let item: KYCViewModel.PortfolioItem
    var urgent: Bool = false
    let onTap: () -> Void

    private var hasDoc: Bool { item.document != nil && !(item.document?.imagePaths.isEmpty ?? true) }
    private var color: Color { item.document?.statusColor ?? Color.secondary.opacity(0.2) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Urgent left border
                if urgent {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(item.document?.status == .expired ? Color.flagged : item.document?.status == .expiringSoon ? Color.review : Color.review)
                        .frame(width: 3, height: 36)
                        .padding(.trailing, 10).padding(.leading, 16)
                }

                HStack(spacing: 14) {
                    // Icon with status ring
                    ZStack {
                        Circle().fill(color.opacity(0.1)).frame(width: 36, height: 36)
                        Image(systemName: item.type.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(hasDoc ? color : .secondary.opacity(0.4))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.type.displayName).font(Typo.body).lineLimit(1).foregroundStyle(.primary)
                        if let doc = item.document, let exp = doc.expiryDate {
                            Text(exp.formatted(date: .abbreviated, time: .omitted))
                                .font(Typo.meta).foregroundStyle(doc.statusColor)
                        } else {
                            Text(hasDoc ? "Added" : item.required ? "Required" : "Optional")
                                .font(Typo.meta).foregroundStyle(hasDoc ? .secondary : .quaternary)
                        }
                        // KYB freshness warning
                        if let doc = item.document, let warning = doc.freshnessWarning {
                            Text(warning).font(.system(size: 10)).foregroundStyle(Color.review)
                        }
                    }

                    Spacer()

                    if hasDoc {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                    } else {
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, urgent ? 6 : 20).padding(.vertical, 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.document?.accessibilityDescription ?? "\(item.type.displayName), \(item.required ? "required" : "optional"), \(hasDoc ? "added" : "missing")")
        .accessibilityHint(hasDoc ? "Double tap to view" : "Double tap to add")
    }
}

// MARK: - Quick Add Sheet

struct QuickAddSheet: View {
    @ObservedObject var vm: KYCViewModel
    let checkId: String
    let docType: MaritimeDocType
    var renewingDocId: String? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var capturedImage: Data?
    @State private var docNumber = ""
    @State private var expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasExpiry = true
    @State private var issuingAuthority = ""
    @State private var issueDate = Date()
    @State private var hasIssueDate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 12)

                    // Doc type header
                    Image(systemName: docType.icon)
                        .font(.system(size: 36)).foregroundStyle(.primary.opacity(0.2))
                    Text(docType.displayName).font(Typo.context)

                    // Photo
                    if let data = capturedImage, let img = UIImage(data: data) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Button { showCamera = true } label: {
                                Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.white, .primary).padding(6)
                            }
                        }.padding(.horizontal, 32)
                    } else {
                        HStack(spacing: 10) {
                            Button { showCamera = true } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill").font(.title3)
                                    Text("Take Photo").font(Typo.meta)
                                }
                                .frame(maxWidth: .infinity).frame(height: 100)
                                .background(Color.surfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button { showFilePicker = true } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.badge.plus").font(.title3)
                                    Text("Upload File").font(Typo.meta)
                                }
                                .frame(maxWidth: .infinity).frame(height: 100)
                                .background(Color.surfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }.padding(.horizontal, 32)
                    }

                    VStack(spacing: 14) {
                        field("Document Number", text: $docNumber, prompt: "Optional")
                        field("Issuing Authority", text: $issuingAuthority, prompt: "e.g. MCA, MARINA")

                        Toggle(isOn: $hasIssueDate) {
                            Text("Record issue date").font(Typo.meta)
                        }.tint(.primary).padding(.horizontal, 4)

                        if hasIssueDate {
                            DatePicker("Issued", selection: $issueDate, in: ...Date(), displayedComponents: .date)
                                .font(Typo.meta).padding(.horizontal, 4)
                        }

                        Toggle(isOn: $hasExpiry) {
                            Text("Has expiry date").font(Typo.meta)
                        }.tint(.primary).padding(.horizontal, 4)

                        if hasExpiry {
                            DatePicker("Expiry", selection: $expiryDate, displayedComponents: .date)
                                .font(Typo.meta)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 32)

                    Button { saveDoc() } label: { Text("Save") }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 32)

                    Spacer(minLength: 32)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) { CameraCapture(result: $capturedImage).ignoresSafeArea() }
            .sheet(isPresented: $showFilePicker) {
                DocumentFilePicker { url in
                    showFilePicker = false
                    guard let url else { return }
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        capturedImage = try? Data(contentsOf: url)
                    }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.meta).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .font(Typo.body).padding(14)
                .background(Color.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func saveDoc() {
        var paths: [String] = []
        if let data = capturedImage {
            let filename = "\(checkId)_\(docType.rawValue.prefix(10).replacingOccurrences(of: " ", with: "_"))_\(UUID().uuidString.prefix(6)).jpg"
            let url = vm.imagesDir.appendingPathComponent(filename)
            try? data.write(to: url)
            paths.append(filename)
            // Auto-upload to workspace if connected
            let vesselId = vm.checks.first(where: { $0.id == checkId })?.vesselId
            vm.queueFileForSync(filename: filename, vesselId: vesselId)
        }
        let doc = CrewDocument(
            type: docType,
            imagePaths: paths,
            documentNumber: docNumber.isEmpty ? nil : docNumber,
            issueDate: hasIssueDate ? issueDate : nil,
            expiryDate: hasExpiry ? expiryDate : nil,
            issuingAuthority: issuingAuthority.isEmpty ? nil : issuingAuthority
        )
        if let oldId = renewingDocId {
            vm.renewDocument(checkId: checkId, oldDocId: oldId, newDoc: doc)
        } else {
            vm.addDocument(to: checkId, document: doc)
        }
        dismiss()
    }
}

// MARK: - Document Detail Sheet

struct DocumentDetailSheet: View {
    @ObservedObject var vm: KYCViewModel
    let checkId: String
    @State var document: CrewDocument
    @Environment(\.dismiss) private var dismiss
    @State private var showRenew = false
    @State private var previewImage: UIImage?
    @State private var previewFilename: String?
    @State private var shareData: Data?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 12)

                    Image(systemName: document.type.icon)
                        .font(.system(size: 36)).foregroundStyle(document.statusColor)
                    Text(document.type.displayName).font(Typo.context)
                    Text(document.statusLabel)
                        .font(Typo.meta).fontWeight(.semibold).foregroundStyle(document.statusColor)

                    // Documents (images + PDFs, tappable for preview + share)
                    ForEach(document.imagePaths, id: \.self) { path in
                        if let data = vm.loadDocumentImage(filename: path) {
                            let isPDF = path.lowercased().hasSuffix(".pdf") || data.prefix(5) == Data([0x25, 0x50, 0x44, 0x46, 0x2D])
                            Button {
                                previewFilename = path
                                if isPDF {
                                    shareData = data
                                } else if let img = UIImage(data: data) {
                                    previewImage = img
                                }
                            } label: {
                                if isPDF {
                                    // PDF thumbnail
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.richtext").font(.system(size: 24)).foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(path).font(Typo.body).lineLimit(1)
                                            Text("PDF \u{2022} \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                                                .font(Typo.meta).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "eye").font(.system(size: 14)).foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color.surfaceMuted.opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else if let img = UIImage(data: data) {
                                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10))
                                                .padding(6).background(.ultraThinMaterial).clipShape(Circle())
                                                .padding(8)
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 32)
                        } else {
                            // File not downloaded yet
                            HStack(spacing: 8) {
                                Image(systemName: "icloud.and.arrow.down").font(.system(size: 16)).foregroundStyle(.secondary)
                                Text(path).font(Typo.meta).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 32)
                        }
                    }

                    // No images uploaded
                    if document.imagePaths.isEmpty {
                        Text("No images uploaded for this document").font(Typo.meta).foregroundStyle(.quaternary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if let n = document.documentNumber, !n.isEmpty { DataRow(label: "Number", value: n) }
                        if let d = document.expiryDate { DataRow(label: "Expires", value: d.formatted(date: .long, time: .omitted), color: document.status == .expired ? .flagged : nil) }
                        if let a = document.issuingAuthority, !a.isEmpty { DataRow(label: "Issued by", value: a) }
                    }
                    .padding(.horizontal, 32)

                    Spacer(minLength: 16)

                    // Renewal guidance + renew button
                    if document.expiryDate != nil {
                        // Guidance card (shown when expiring or expired)
                        if let guidance = document.type.renewalInfo,
                           document.status == .expiringSoon || document.status == .expired {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Renewal Steps", systemImage: "arrow.clockwise")
                                    .font(Typo.body).fontWeight(.medium)
                                Text(guidance.activity).font(Typo.body)
                                HStack(spacing: 16) {
                                    Label(guidance.leadTime, systemImage: "clock").font(Typo.meta)
                                    Label(guidance.contactType, systemImage: "person").font(Typo.meta)
                                }.foregroundStyle(.secondary)
                                if let notes = guidance.notes {
                                    Text(notes).font(Typo.meta).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(14)
                            .background(Color.review.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 32)
                        }

                        Button {
                            showRenew = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Renew Document")
                            }
                            .font(Typo.body).fontWeight(.medium)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal, 32)
                    }

                    Button(role: .destructive) {
                        vm.removeDocument(checkId: checkId, documentId: document.id)
                        dismiss()
                    } label: {
                        Text("Remove Document").font(Typo.meta)
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showRenew) {
                QuickAddSheet(vm: vm, checkId: checkId, docType: document.type, renewingDocId: document.id)
            }
            .fullScreenCover(item: Binding(
                get: { previewImage.map { ImagePreviewItem(image: $0, filename: previewFilename ?? "") } },
                set: { if $0 == nil { previewImage = nil } }
            )) { item in
                ImagePreviewView(image: item.image, filename: item.filename, imagesDir: vm.imagesDir)
            }
            .sheet(isPresented: Binding(get: { shareData != nil }, set: { if !$0 { shareData = nil } })) {
                if let data = shareData { ActivityView(items: [data]) }
            }
        }
    }
}

// MARK: - Image Preview

struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let filename: String
}

struct ImagePreviewView: View {
    let image: UIImage
    let filename: String
    let imagesDir: URL
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Centered image
            VStack {
                Spacer()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 2)
                Spacer()
            }

            // Floating controls
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16).padding(.top, 54)
                Spacer()
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .sheet(isPresented: $showShare) {
            // Share image data directly — avoids all sandbox/URL issues
            if let data = image.jpegData(compressionQuality: 0.95) {
                ActivityView(items: [data])
            }
        }
    }
}
