//
//  ModeSelectionView.swift
//  OceanCheck
//
//  Launch pad: choose Agent or Subject. Not a permanent choice — easily switchable.
//

import SwiftUI

struct ModeSelectionView: View {
    var appState: AppState

    var body: some View {
        ZStack {
            LinearGradient.hero.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
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

                Spacer().frame(height: 44)

                // Cards
                VStack(spacing: 14) {
                    Text("What would you like to do?")
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    modeCard(
                        icon: "shield.checkered",
                        iconBg: Color.brand,
                        title: "Verify Someone",
                        subtitle: "Scan documents, run KYC & AML checks, generate compliance reports.",
                        action: { withAnimation { appState.setMode(.agent) } }
                    )

                    modeCard(
                        icon: "person.crop.rectangle",
                        iconBg: Color.pass,
                        title: "Verify Myself",
                        subtitle: "I was invited by an agent. Scan a QR code to begin self-verification.",
                        action: { withAnimation { appState.setMode(.subject) } }
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                Text("You can switch anytime from Settings")
                    .font(.caption2).foregroundStyle(.quaternary)
                    .padding(.bottom, 8)

                Text("seapay.me  \u{2022}  v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption2).foregroundStyle(.quaternary)
                    .padding(.bottom, 24)
            }
        }
    }

    private func modeCard(icon: String, iconBg: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(iconBg.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
}
