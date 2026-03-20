//
//  HomeView.swift
//  OceanCheck
//
//  Minimal tool: search field, name list, one-word status.
//  No dashboard, no stats. Focused on doing work.
//

import SwiftUI
import Network

struct HomeView: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState

    @State private var name = ""
    @State private var activeCheck: KYCCheck?
    @State private var inviteCheck: KYCCheck?
    @State private var showSettings = false
    @State private var showMethodPicker = false
    @State private var searchText = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── NAME FIELD ──
                HStack(spacing: 12) {
                    TextField("Name", text: $name)
                        .font(Typo.body).focused($nameFocused)
                        .submitLabel(.go)
                        .onSubmit { if canStart { showMethodPicker = true } }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button { showMethodPicker = true } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.surface)
                            .frame(width: 44, height: 44)
                            .background(canStart ? Color.primary : Color.secondary.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .disabled(!canStart)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)

                // ── LIST ──
                if filtered.isEmpty {
                    Spacer()
                    Text(vm.checks.isEmpty ? "Type a name to begin" : "No results")
                        .font(Typo.meta).foregroundStyle(.quaternary)
                    Spacer()
                } else {
                    List {
                        ForEach(filtered) { check in
                            Button { activeCheck = check } label: {
                                HStack {
                                    Text(check.customerName).font(Typo.body).lineLimit(1)
                                    Spacer()
                                    StatusBadge(status: check.status)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { filtered[$0].id }
                            let real = IndexSet(ids.compactMap { id in vm.checks.firstIndex(where: { $0.id == id }) })
                            vm.deleteCheck(at: real)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("OceanCheck").font(BrandFont.brand(17)) }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape").foregroundStyle(.primary) }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
            .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
            .sheet(item: $inviteCheck) { InviteSheet(vm: vm, check: $0) }
            .sheet(isPresented: $showSettings) { SettingsSheet(vm: vm, appState: appState) }
            .confirmationDialog("Verify \(name)", isPresented: $showMethodPicker, titleVisibility: .visible) {
                Button("I have their documents") { startDirect() }
                Button("Send them an invite") { startInvite() }.disabled(!AppConfiguration.hasWorkflow)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var canStart: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func startDirect() {
        let check = vm.createCheck(customerName: name.trimmingCharacters(in: .whitespaces))
        name = ""; nameFocused = false; activeCheck = check
    }

    private func startInvite() {
        let check = vm.createCheck(customerName: name.trimmingCharacters(in: .whitespaces))
        name = ""; nameFocused = false; inviteCheck = check
    }

    private var filtered: [KYCCheck] {
        searchText.isEmpty ? vm.checks : vm.checks.filter {
            $0.customerName.localizedCaseInsensitiveContains(searchText) ||
            ($0.documentNumber ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
}
