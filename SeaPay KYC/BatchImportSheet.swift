//
//  BatchImportSheet.swift
//  OceanCheck
//
//  Import crew and compliance data from CSV.
//  Flow: pick file → preview → assign vessel → confirm.
//

import SwiftUI
import UniformTypeIdentifiers

struct BatchImportSheet: View {
    @ObservedObject var vm: KYCViewModel
    var vesselId: String?
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .pick
    @State private var parseResult: CSVImporter.ParseResult?
    @State private var selectedVesselId: String?
    @State private var sendInvites = false
    @State private var showFilePicker = false
    @State private var showTemplateShare = false
    @State private var importedChecks: [KYCCheck] = []
    @State private var importing = false

    enum Phase { case pick, preview, vessel, importing, done }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick: pickView
                case .preview: previewView
                case .vessel: vesselView
                case .importing: importingView
                case .done: doneView
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: phase == .pick ? "xmark" : "chevron.left").foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.smooth(duration: 0.25), value: phase)
        }
    }

    // MARK: - Pick File

    private var pickView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.badge.plus").font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("Import Crew CSV").font(Typo.context)
            Text("Import crew members, owners, and compliance entities from a CSV file")
                .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)

            VStack(spacing: 10) {
                Button { showFilePicker = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder").font(.system(size: 18)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose CSV File").font(Typo.body).fontWeight(.medium)
                            Text("From Files, iCloud, or other apps").font(Typo.meta).opacity(0.7)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(Color.primary).foregroundStyle(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button { showTemplateShare = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc").font(.system(size: 18)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Download Template").font(Typo.body).fontWeight(.medium)
                            Text("Get a sample CSV with the expected format").font(Typo.meta)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(Color.surfaceMuted).foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .sheet(isPresented: $showFilePicker) {
            CSVFilePicker { url in
                showFilePicker = false
                guard let url else { return }
                withAnimation { phase = .importing } // Show spinner while parsing
                Task {
                    let result = CSVImporter.parse(url: url)
                    await MainActor.run {
                        parseResult = result
                        withAnimation { phase = .preview }
                    }
                }
            }
        }
        .sheet(isPresented: $showTemplateShare) {
            let template = CSVImporter.generateTemplate()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("OceanCheck_Import_Template.csv")
            let _ = try? template.write(to: tempURL, atomically: true, encoding: .utf8)
            ActivityView(items: [tempURL])
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: 0) {
            if let result = parseResult {
                // Summary header
                VStack(spacing: 8) {
                    Text("Preview").font(Typo.context)
                    HStack(spacing: 12) {
                        if result.crewCount > 0 { MetadataPill(icon: "person.text.rectangle", text: "\(result.crewCount) Crew") }
                        if result.complianceCount > 0 { MetadataPill(icon: "person.badge.key", text: "\(result.complianceCount) Compliance") }
                        if result.shoreBasedCount > 0 { MetadataPill(icon: "building", text: "\(result.shoreBasedCount) Shore-Based") }
                    }
                    if result.skippedCount > 0 {
                        Text("\(result.skippedCount) row\(result.skippedCount == 1 ? "" : "s") skipped").font(Typo.meta).foregroundStyle(Color.review)
                    }
                }
                .padding(.top, 16).padding(.bottom, 12)

                // Row list
                List {
                    if !result.errors.isEmpty {
                        Section("Warnings") {
                            ForEach(result.errors, id: \.self) { err in
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle").font(Typo.meta).foregroundStyle(Color.review)
                                    Text(err).font(Typo.meta).foregroundStyle(Color.review)
                                }
                            }
                        }
                    }

                    Section("People to Import (\(result.rows.count))") {
                        ForEach(result.rows) { row in
                            HStack(spacing: 12) {
                                Circle().fill(Color.surfaceMuted).frame(width: 36, height: 36)
                                    .overlay { Text(String(row.name.prefix(1)).uppercased()).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary) }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).font(Typo.body).fontWeight(.medium)
                                    HStack(spacing: 6) {
                                        if row.entityType == .seafarer {
                                            Text(row.rank?.rawValue ?? "No rank").font(Typo.meta).foregroundStyle(.secondary)
                                        } else {
                                            Text(row.entityType.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                                        }
                                        if let nat = row.nationality {
                                            Text(nat).font(Typo.meta).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                Spacer()
                                if let w = row.warning {
                                    Image(systemName: "exclamationmark.triangle").font(Typo.meta).foregroundStyle(Color.review)
                                        .help(w)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                // Actions
                VStack(spacing: 8) {
                    if AppConfiguration.hasWorkflow && vm.isOnline {
                        Toggle(isOn: $sendInvites) {
                            Text("Send invite links after import").font(Typo.meta)
                        }
                        .tint(.primary).padding(.horizontal, 20)
                    }

                    Button {
                        if vesselId != nil {
                            selectedVesselId = vesselId
                            performImport()
                        } else {
                            withAnimation { phase = .vessel }
                        }
                    } label: {
                        Text("Import \(result.rows.count) People")
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !result.rows.isEmpty))
                    .disabled(result.rows.isEmpty)
                    .padding(.horizontal, 32)
                }
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
    }

    // MARK: - Vessel Selection

    private var vesselView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Assign to Vessel").font(Typo.context)
                Text("Select which vessel to assign the imported crew to").font(Typo.meta).foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)

            List {
                Section {
                    ForEach(vm.vessels) { vessel in
                        Button {
                            selectedVesselId = vessel.id
                            performImport()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vessel.name).font(Typo.body).fontWeight(.medium)
                                    if let vt = vessel.vesselType { Text(vt.rawValue).font(Typo.meta).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        selectedVesselId = nil
                        performImport()
                    } label: {
                        HStack {
                            Text("Skip — import without vessel").font(Typo.body).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Importing

    private var importingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Importing...").font(Typo.body).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()
            Circle().fill(Color.clear_.opacity(0.08)).frame(width: 72, height: 72)
                .overlay { Image(systemName: "checkmark").font(.system(size: 24)).foregroundStyle(Color.clear_) }
            Text("Import Complete").font(Typo.context)

            let crewCount = importedChecks.filter { $0.entityType == .seafarer }.count
            let otherCount = importedChecks.count - crewCount
            VStack(spacing: 4) {
                if crewCount > 0 { Text("\(crewCount) crew imported").font(Typo.body) }
                if otherCount > 0 { Text("\(otherCount) other entities imported").font(Typo.body) }
                if let vid = selectedVesselId, let v = vm.vessels.first(where: { $0.id == vid }) {
                    Text("Assigned to \(v.name)").font(Typo.meta).foregroundStyle(.secondary)
                }
            }

            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)

            Spacer()
        }
    }

    // MARK: - Import Action

    private func performImport() {
        withAnimation { phase = .importing }
        let rows = parseResult?.rows ?? []
        let vid = selectedVesselId
        Task.detached { [vm] in
            let created = await vm.importCrewCSV(rows: rows, vesselId: vid)
            await MainActor.run {
                importedChecks = created
                Haptics.success()
                withAnimation { phase = .done }
            }
        }
    }
}

// MARK: - CSV File Picker

struct CSVFilePicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.commaSeparatedText, .plainText, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { onPick(nil) }
    }
}
