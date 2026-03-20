//
//  HomeView.swift
//  SeaPay KYC
//

import SwiftUI
import Network

struct HomeView: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState

    @State private var customerName = ""
    @State private var activeCheck: KYCCheck?
    @State private var inviteCheck: KYCCheck?
    @State private var showSettings = false
    @State private var showMethodPicker = false
    @State private var searchText = ""
    @State private var isOnline = true
    @State private var netMonitor: NWPathMonitor?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── NAME ENTRY ──
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill").foregroundStyle(Color.brand.opacity(0.5))
                        TextField("Enter customer name", text: $customerName)
                            .textContentType(.name).focused($nameFocused)
                            .submitLabel(.go)
                            .onSubmit { if canStart { startNew() } }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)

                    Button { showMethodPicker = true } label: {
                        Image(systemName: "arrow.right").font(.body.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(canStart ? Color.brand : Color.gray.opacity(0.3))
                            .clipShape(Circle())
                            .shadow(color: canStart ? Color.brand.opacity(0.4) : .clear, radius: 8, y: 4)
                    }
                    .disabled(!canStart)
                    .accessibilityLabel("Start verification")
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(LinearGradient(colors: [Color.brand.opacity(0.04), .clear], startPoint: .top, endPoint: .bottom))

                // ── LIST ──
                if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "person.text.rectangle").font(.system(size: 48, weight: .thin)).foregroundStyle(Color.brand.opacity(0.2))
                        Text(vm.checks.isEmpty ? "Start your first verification" : "No results").font(.subheadline).foregroundStyle(.tertiary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filtered) { check in
                            Button { activeCheck = check } label: { CheckRow(check: check, loadImage: vm.loadDocumentImage) }
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { filtered[$0].id }
                            let real = IndexSet(ids.compactMap { id in vm.checks.firstIndex(where: { $0.id == id }) })
                            vm.deleteCheck(at: real)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }

                // ── STATUS ──
                HStack(spacing: 14) {
                    HStack(spacing: 5) { Circle().fill(isOnline ? Color.pass : Color.fail).frame(width: 6, height: 6); Text(isOnline ? "Online" : "Offline") }
                    Spacer()
                    stat(vm.checks.count, "total", .secondary)
                    stat(vm.checks.filter { $0.status == .passed }.count, "passed", .pass)
                    stat(vm.checks.filter { $0.status == .failed }.count, "failed", .fail)
                }
                .font(.system(size: 10, weight: .medium)).padding(.horizontal, 20).padding(.vertical, 7).background(.bar)
            }
            .background(Color.surfaceRaised.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("OceanCheck").font(BrandFont.brand(18))
                        Text("Maritime Identity Verification").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .primaryAction) { Button { showSettings = true } label: { Image(systemName: "gearshape.fill").foregroundStyle(Color.brand) } }
            }
            .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
            .sheet(item: $inviteCheck) { InviteSheet(vm: vm, check: $0) }
            .confirmationDialog("How would you like to verify \(customerName)?", isPresented: $showMethodPicker, titleVisibility: .visible) {
                Button("Verify Here — I have their documents") { startNew() }
                Button("Send Invite — they verify themselves") { startInvite() }
                    .disabled(!AppConfiguration.hasWorkflow)
                Button("Cancel", role: .cancel) {}
            } message: {
                if !AppConfiguration.hasWorkflow {
                    Text("Remote invitations require a Workflow ID. Add it in Settings.")
                }
            }
            .sheet(isPresented: $showSettings) { SetupView(vm: vm, isSheet: true, onReset: { appState.didReset() }, onSwitchMode: { appState.setMode(.none) }) }
            .onAppear {
                if netMonitor == nil {
                    let m = NWPathMonitor()
                    m.pathUpdateHandler = { p in Task { @MainActor in isOnline = p.status == .satisfied } }
                    m.start(queue: DispatchQueue(label: "net"))
                    netMonitor = m
                }
            }
        }
    }

    private var canStart: Bool { !customerName.trimmingCharacters(in: .whitespaces).isEmpty }

    private func startNew() {
        let check = vm.createCheck(customerName: customerName.trimmingCharacters(in: .whitespaces)); customerName = ""; nameFocused = false; activeCheck = check
    }

    private func startInvite() {
        let check = vm.createCheck(customerName: customerName.trimmingCharacters(in: .whitespaces)); customerName = ""; nameFocused = false; inviteCheck = check
    }
    private var filtered: [KYCCheck] {
        searchText.isEmpty ? vm.checks : vm.checks.filter { $0.customerName.localizedCaseInsensitiveContains(searchText) || ($0.documentNumber ?? "").localizedCaseInsensitiveContains(searchText) || ($0.extractedName ?? "").localizedCaseInsensitiveContains(searchText) }
    }
    private func stat(_ n: Int, _ l: String, _ c: Color) -> some View { HStack(spacing: 3) { Text("\(n)").foregroundStyle(c); Text(l).foregroundStyle(.secondary) } }
}

// MARK: - Check Row

struct CheckRow: View {
    let check: KYCCheck
    let loadImage: (String) -> Data?
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let p = check.documentImagePaths?.first, let d = loadImage(p), let i = UIImage(data: d) { Image(uiImage: i).resizable().scaledToFill() }
                else { Image(systemName: check.expectedDocType?.icon ?? "doc").font(.title3).foregroundStyle(Color.brand.opacity(0.5)).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.brand.opacity(0.06)) }
            }.frame(width: 52, height: 36).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(check.customerName).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    if let dt = check.documentType ?? check.expectedDocType?.rawValue { Text(dt.replacingOccurrences(of: "_", with: " ").capitalized).lineLimit(1) }
                    if let n = check.documentNumber { Text(n).fontDesign(.monospaced).lineLimit(1) }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: check.status)
                if let s = check.amlScore {
                    HStack(spacing: 3) { Circle().fill(s > 70 ? Color.fail : s > 40 ? Color.warning : Color.pass).frame(width: 5, height: 5); Text("AML \(s)").font(.system(size: 9, weight: .bold)).foregroundStyle(s > 70 ? Color.fail : s > 40 ? Color.warning : Color.pass) }
                } else { Text(check.createdAt, style: .relative).font(.caption2).foregroundStyle(.quaternary) }
            }
        }.padding(.vertical, 8).padding(.horizontal, 14).background(Color.surface).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).shadow(color: .black.opacity(0.04), radius: 6, y: 2).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(check.customerName), \(check.status.rawValue)")
            .accessibilityHint(check.status == .pending ? "Tap to start verification" : "Tap to view results")
    }
}

struct DocChip: View {
    let type: KYCCheck.IDDocType; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) { Image(systemName: type.icon).font(.system(size: 16, weight: .medium)); Text(type.rawValue).font(.system(size: 9, weight: selected ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.7) }
                .frame(maxWidth: .infinity).padding(.vertical, 10).background(selected ? Color.brand : Color.surface).foregroundStyle(selected ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).shadow(color: selected ? Color.brand.opacity(0.3) : .black.opacity(0.04), radius: selected ? 8 : 4, y: selected ? 3 : 2)
        }.buttonStyle(.plain)
    }
}
