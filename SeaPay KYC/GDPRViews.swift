//
//  GDPRViews.swift
//  OceanCheck
//
//  Settings views for GDPR compliance: retention policy, DSAR, audit log.
//

import SwiftUI

// MARK: - Data Retention Settings

struct RetentionSettingsView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var years: Int
    @State private var autoFlag: Bool
    @Environment(\.dismiss) private var dismiss

    init(vm: KYCViewModel) {
        self.vm = vm
        let p = vm.retentionPolicy
        _years = State(initialValue: p.retentionYears)
        _autoFlag = State(initialValue: p.autoFlagExpired)
    }

    var body: some View {
        List {
            Section {
                Stepper("Retention period: \(years) year\(years == 1 ? "" : "s")", value: $years, in: 1...10)
                    .font(Typo.body)
                Toggle("Flag records past retention", isOn: $autoFlag)
                    .font(Typo.body).tint(.primary)
            } header: {
                Text("Data Retention Policy")
            } footer: {
                Text("MLC 2006 requires maritime employment records to be retained for a minimum of 5 years. Records past the retention period will be flagged for review.")
                    .font(Typo.meta)
            }

            if !vm.retentionFlaggedChecks.isEmpty {
                Section("Flagged Records") {
                    ForEach(vm.retentionFlaggedChecks, id: \.id) { check in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.customerName).font(Typo.body)
                                Text(check.createdAt.formatted(date: .abbreviated, time: .omitted)).font(Typo.meta).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let retDate = GDPRService.retentionDate(for: check, policy: vm.retentionPolicy) {
                                Text("Due \(retDate.formatted(date: .abbreviated, time: .omitted))").font(Typo.meta).foregroundStyle(Color.review)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Data Retention")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: years) { _, _ in savePolicy() }
        .onChange(of: autoFlag) { _, _ in savePolicy() }
    }

    private func savePolicy() {
        vm.retentionPolicy = RetentionPolicy(retentionYears: years, autoFlagExpired: autoFlag, autoDeleteExpired: false)
    }
}

// MARK: - DSAR Export View

struct DSARView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var searchName = ""
    @State private var exportURL: IdentifiableURL?

    var body: some View {
        VStack(spacing: 0) {
            // Search
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter the name of the data subject to export all personal data held by OceanCheck.")
                    .font(Typo.meta).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.top, 16)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Subject name", text: $searchName)
                        .font(Typo.body)
                        .textInputAutocapitalization(.words)
                }
                .padding(12)
                .background(Color.surfaceMuted.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)
            }

            // Matching records preview
            let matches = vm.checks.filter {
                !searchName.isEmpty && (
                    $0.customerName.localizedCaseInsensitiveContains(searchName) ||
                    ($0.extractedName?.localizedCaseInsensitiveContains(searchName) ?? false)
                )
            }

            if !searchName.isEmpty {
                List {
                    Section("\(matches.count) matching record\(matches.count == 1 ? "" : "s")") {
                        ForEach(matches, id: \.id) { check in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.customerName).font(Typo.body)
                                    Text(check.entityType.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(check.status.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Spacer()
            }

            // Export button
            if !matches.isEmpty {
                Button {
                    if let url = vm.exportDSAR(name: searchName) {
                        vm.logAudit(.dsarExported, entityId: "dsar", entityName: searchName, detail: "\(matches.count) records")
                        exportURL = IdentifiableURL(url: url)
                        Haptics.success()
                    }
                } label: {
                    Text("Export Subject Data")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32).padding(.bottom, 20)
            }
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationTitle("Subject Data Request")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportURL) { url in
            ActivityView(items: [url.url])
        }
    }
}

// MARK: - Audit Log View

struct AuditLogView: View {
    @ObservedObject var vm: KYCViewModel

    private var sortedLog: [AuditEvent] {
        vm.auditLog.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        Group {
            if vm.auditLog.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.clipboard").font(.system(size: 40)).foregroundStyle(.quaternary)
                    Text("No audit events yet").font(Typo.body).foregroundStyle(.secondary)
                    Text("Actions like exports, reviews, and transfers will appear here.").font(Typo.meta).foregroundStyle(.quaternary).multilineTextAlignment(.center).padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                List {
                    ForEach(sortedLog) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: iconForAction(event.action))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(event.action.rawValue).font(Typo.body).fontWeight(.medium)
                                    Spacer()
                                    Text(event.timestamp.formatted(.relative(presentation: .named))).font(Typo.meta).foregroundStyle(.quaternary)
                                }
                                Text(event.entityName).font(Typo.meta).foregroundStyle(.secondary)
                                if let detail = event.detail {
                                    Text(detail).font(Typo.meta).foregroundStyle(.quaternary)
                                }
                                Text("by \(event.performedBy)").font(.system(size: 10)).foregroundStyle(.quaternary)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iconForAction(_ action: AuditEvent.AuditAction) -> String {
        switch action {
        case .created: return "plus.circle"
        case .viewed: return "eye"
        case .exported: return "square.and.arrow.up"
        case .shared: return "paperplane"
        case .reviewed: return "checkmark.circle"
        case .deleted: return "trash"
        case .transferred: return "arrow.right.arrow.left"
        case .dsarExported: return "person.text.rectangle"
        case .consentGranted: return "hand.thumbsup"
        case .consentWithdrawn: return "hand.thumbsdown"
        case .retentionFlagged: return "clock.badge.exclamationmark"
        case .gdprErasure: return "trash.circle"
        }
    }
}

// MARK: - GDPR Art. 17 Erasure View

struct GDPRErasureView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var searchName = ""
    @State private var showConfirm = false
    @State private var erasedCount = 0

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Right to Erasure").font(Typo.context)
                Text("GDPR Article 17 — Enter the data subject's name to permanently erase all their personal data from this device and the workspace server.")
                    .font(Typo.meta).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text("Subject Name").font(Typo.meta).foregroundStyle(.tertiary)
                TextField("Full name", text: $searchName)
                    .font(Typo.body).padding(11)
                    .background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 20)

            let matches = vm.checks.filter {
                !searchName.isEmpty && (
                    $0.customerName.localizedCaseInsensitiveContains(searchName) ||
                    ($0.extractedName ?? "").localizedCaseInsensitiveContains(searchName)
                )
            }

            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(matches.count) matching record\(matches.count == 1 ? "" : "s")").font(Typo.meta).foregroundStyle(.secondary)
                    ForEach(matches) { check in
                        HStack {
                            Text(check.displayName).font(Typo.body)
                            Spacer()
                            Text(check.status.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            if erasedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.clear_)
                    Text("\(erasedCount) record\(erasedCount == 1 ? "" : "s") permanently erased").font(Typo.body)
                }
                .padding(.horizontal, 20)
            }

            Button {
                showConfirm = true
            } label: {
                Text("Erase All Data")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !matches.isEmpty))
            .disabled(matches.isEmpty)
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationTitle("Data Erasure")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Confirm Permanent Erasure", isPresented: $showConfirm) {
            Button("Erase", role: .destructive) {
                erasedCount = GDPRService.eraseSubjectData(name: searchName, vm: vm).count
                searchName = ""
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all personal data, documents, images, and consent records for this person. This action cannot be undone. Server data will also be erased.")
        }
    }
}

// ActivityView is defined in VerificationSheet.swift
