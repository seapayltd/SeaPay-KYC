//
//  PersonDetailView.swift
//  SeaPay KYC
//
//  Push-destination for crew / person records.
//  Card-based layout, role-scoped (agents vs collaborators).
//

import SwiftUI

struct PersonDetailView: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck

    @State private var reviewReason = ""
    @State private var activeReviewType: ReviewCeremonyView.ReviewDecisionType?
    @State private var reportURL: URL?
    @State private var showShareSheet = false

    private var isCollaborator: Bool {
        UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty
    }

    /// Live check from the VM (picks up review changes, etc.)
    private var liveCheck: KYCCheck {
        vm.checks.first(where: { $0.id == check.id }) ?? check
    }

    private var documents: [CrewDocument] {
        liveCheck.documents ?? []
    }

    private var validDocCount: Int {
        documents.filter { $0.status == .valid }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                headerSection
                identityCard
                documentsSection

                if !isCollaborator {
                    reviewSection
                }

                generateReportButton

                Spacer(minLength: Space.xxl)
            }
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.md)
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationTitle("Person")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeReviewType) { type in
            ReviewCeremonyView(
                personName: liveCheck.displayName,
                documentType: liveCheck.documentType,
                amlStatus: liveCheck.amlStatus,
                decision: type,
                reason: $reviewReason,
                onConfirm: {
                    let decision: KYCCheck.ReviewDecision = {
                        switch type {
                        case .approve: return .approved
                        case .flag: return .flagged
                        case .decline: return .declined
                        }
                    }()
                    vm.submitReview(checkId: liveCheck.id, decision: decision, reason: reviewReason)
                    reviewReason = ""
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = reportURL {
                ActivityView(items: [url])
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Space.sm) {
            // Avatar
            if let photoFilename = liveCheck.profilePhoto,
               let data = vm.loadDocumentImage(filename: photoFilename),
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.surfaceMuted)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Text(initialLetter)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }

            // Name
            Text(liveCheck.displayName)
                .font(Typo.title)
                .multilineTextAlignment(.center)

            // Rank + nationality
            HStack(spacing: Space.xs) {
                if let rank = liveCheck.crewRank {
                    Text(rank.rawValue)
                }
                if liveCheck.crewRank != nil && liveCheck.nationality != nil {
                    Text("\u{2022}")
                }
                if let nationality = liveCheck.nationality {
                    Text(nationality)
                }
            }
            .font(Typo.caption)
            .foregroundStyle(.secondary)

            StatusBadge(status: liveCheck.status)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.sm)
    }

    // MARK: - Identity Card

    private var identityCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("IDENTITY")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                if let docType = liveCheck.documentType {
                    DataRow(label: "Document", value: docType)
                }

                if let docNumber = liveCheck.documentNumber {
                    DataRow(label: "Number", value: docNumber)
                }

                if let expiry = liveCheck.expiryDate {
                    DataRow(label: "Expiry", value: expiry)
                }

                if let aml = liveCheck.amlStatus {
                    DataRow(
                        label: "AML",
                        value: aml,
                        color: amlColor(for: aml),
                        bold: true
                    )
                }

                // Document images — agents only (PII protection for collaborators)
                if !isCollaborator, let paths = liveCheck.documentImagePaths, !paths.isEmpty {
                    Divider()
                    ForEach(paths, id: \.self) { path in
                        if let data = vm.loadDocumentImage(filename: path),
                           let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Documents Section

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("DOCUMENTS")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                Text("\(validDocCount)/\(documents.count)")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
            }

            if documents.isEmpty {
                Text("No documents")
                    .font(Typo.body)
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Space.lg)
            } else {
                ForEach(documents.filter { !$0.isArchived }) { doc in
                    NavigationLink {
                        DocumentDetailSheet(vm: vm, checkId: liveCheck.id, document: doc)
                    } label: {
                        documentRow(doc)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func documentRow(_ doc: CrewDocument) -> some View {
        CardView {
            HStack(spacing: Space.md) {
                // Icon circle with status color
                ZStack {
                    Circle()
                        .fill(doc.statusColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: doc.docIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(doc.statusColor)
                }

                // Doc name + status
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.displayName)
                        .font(Typo.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(doc.statusLabel)
                        .font(Typo.micro)
                        .foregroundStyle(doc.statusColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    // MARK: - Review Section (agents only)

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("REVIEW")
                .font(Typo.caption)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            if let decision = liveCheck.reviewDecision {
                // Existing review
                CardView {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(spacing: Space.sm) {
                            StatusBadge(status: reviewDecisionToStatus(decision))
                            Spacer()
                        }
                        if let reviewer = liveCheck.reviewedBy, !reviewer.isEmpty {
                            Text("by \(reviewer)")
                                .font(Typo.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let reason = liveCheck.reviewReason, !reason.isEmpty {
                            Text("\"\(reason)\"")
                                .font(Typo.body)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                }
            } else {
                // No review yet — action buttons
                HStack(spacing: Space.sm) {
                    reviewButton("Approve", color: .clear_, type: .approve)
                    reviewButton("Flag", color: .review, type: .flag)
                    reviewButton("Decline", color: .flagged, type: .decline)
                }
            }
        }
    }

    private func reviewButton(_ label: String, color: Color, type: ReviewCeremonyView.ReviewDecisionType) -> some View {
        Button {
            reviewReason = ""
            activeReviewType = type
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(color.opacity(0.1))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Generate Report

    private var generateReportButton: some View {
        Button {
            if let url = vm.generateReport(checkId: liveCheck.id) {
                reportURL = url
                showShareSheet = true
            }
        } label: {
            Text("Generate PDF Report")
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    // MARK: - Helpers

    private var initialLetter: String {
        let name = liveCheck.displayName
        return name.first.map(String.init) ?? "?"
    }

    private func amlColor(for status: String) -> Color {
        let lower = status.lowercased()
        if lower.contains("clear") || lower.contains("pass") { return .clear_ }
        if lower.contains("hit") || lower.contains("fail") || lower.contains("match") { return .flagged }
        return .review
    }

    private func reviewDecisionToStatus(_ decision: KYCCheck.ReviewDecision) -> KYCCheck.CheckStatus {
        switch decision {
        case .approved: return .passed
        case .flagged: return .requiresReview
        case .declined: return .failed
        }
    }
}

// MARK: - Make ReviewDecisionType Identifiable for sheet binding

extension ReviewCeremonyView.ReviewDecisionType: @retroactive Identifiable {
    public var id: String {
        switch self {
        case .approve: return "approve"
        case .flag: return "flag"
        case .decline: return "decline"
        }
    }
}
