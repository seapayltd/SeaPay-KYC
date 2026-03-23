//
//  ExportPreviewView.swift
//  OceanCheck
//
//  Preview generated PDFs and CSVs before sharing.
//  See it first, then decide to share. The Ive way.
//

import SwiftUI
import PDFKit

struct ExportPreviewView: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String?
    let type: ExportType

    enum ExportType { case pdf, csv }

    @State private var fileURL: URL?
    @State private var csvContent: String?
    @State private var showShare = false
    @State private var generating = true

    var body: some View {
        Group {
            if generating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(type == .pdf ? "Generating report..." : "Preparing data...")
                        .font(Typo.body).foregroundStyle(.secondary)
                }
            } else if type == .pdf, let url = fileURL {
                PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
            } else if type == .csv, let content = csvContent {
                csvPreview(content)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(.quaternary)
                    Text("Could not generate file").font(Typo.body).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(type == .pdf ? "Compliance Report" : "Crew Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if fileURL != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = fileURL { ActivityView(items: [url]) }
        }
        .task { await generate() }
    }

    // MARK: - CSV Preview

    private func csvPreview(_ content: String) -> some View {
        let lines = content.components(separatedBy: "\n").prefix(50)
        let header = lines.first?.components(separatedBy: ",") ?? []

        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(header.indices, id: \.self) { i in
                        Text(header[i].replacingOccurrences(of: "\"", with: ""))
                            .font(Typo.meta).fontWeight(.bold)
                            .frame(minWidth: 90, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Color.surfaceMuted)
                    }
                }

                // Data rows
                ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { idx, line in
                    let cols = line.components(separatedBy: ",")
                    HStack(spacing: 0) {
                        ForEach(cols.indices, id: \.self) { i in
                            Text(cols[i].replacingOccurrences(of: "\"", with: ""))
                                .font(Typo.meta)
                                .foregroundStyle(statusColor(cols[i]))
                                .frame(minWidth: 100, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                        }
                    }
                    .background(idx % 2 == 0 ? Color.surfaceMuted.opacity(0.3) : Color.clear)
                }
            }
            .padding(12)
        }
    }

    private func statusColor(_ value: String) -> Color {
        let v = value.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
        switch v {
        case "Valid", "Passed", "Clear": return .clear_
        case "Expired", "Failed", "Flagged": return .flagged
        case "Expiring", "Review": return .review
        case "Missing": return .secondary
        default: return .primary
        }
    }

    // MARK: - Generate

    private func generate() async {
        // Small delay for push animation to complete
        try? await Task.sleep(nanoseconds: 150_000_000)

        await MainActor.run {
            switch type {
            case .pdf:
                fileURL = vm.generateCompliancePacket(vesselId: vesselId)
            case .csv:
                fileURL = vm.generateCSV(vesselId: vesselId)
                if let url = fileURL { csvContent = try? String(contentsOf: url, encoding: .utf8) }
            }
            withAnimation { generating = false }
        }
    }
}
