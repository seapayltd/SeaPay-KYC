//
//  ModeSelectionView.swift
//  OceanCheck
//
//  First launch: choose Agent or Subject mode.
//

import SwiftUI

struct ModeSelectionView: View {
    var appState: AppState

    var body: some View {
        ZStack {
            LinearGradient.hero.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo + brand
                VStack(spacing: 16) {
                    Image("AppIcon")
                        .resizable().scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)

                    Text("OceanCheck").font(BrandFont.brand(30))

                    Text("Maritime Identity Verification")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                Spacer().frame(height: 48)

                // Mode cards
                VStack(spacing: 14) {
                    Text("How will you use this app?")
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    // Agent card
                    Button {
                        withAnimation { appState.setMode(.agent) }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "shield.checkered")
                                .font(.title2).foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Color.brand.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("I'm an Agent").font(.subheadline.weight(.semibold))
                                Text("Verify crew members, scan documents, run compliance checks, generate reports.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)

                    // Subject card
                    Button {
                        withAnimation { appState.setMode(.subject) }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.rectangle")
                                .font(.title2).foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(Color.pass.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("I was invited").font(.subheadline.weight(.semibold))
                                Text("Scan a QR code from an agent to verify your identity securely.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Footer
                Text("seapay.me  \u{2022}  v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption2).foregroundStyle(.quaternary)
                    .padding(.bottom, 24)
            }
        }
    }
}
