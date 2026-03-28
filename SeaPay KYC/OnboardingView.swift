//
//  OnboardingView.swift
//  OceanCheck
//
//  First-launch tutorial — explains what the app does and what you need.
//  3 pages + a Get Started button that transitions to the WelcomeView.
//

import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0

    private let pages: [(icon: String, title: String, subtitle: String, details: [String])] = [
        (
            "checkmark.shield",
            "Maritime Compliance\nin Your Pocket",
            "OceanCheck helps you verify crew, track documents, and manage vessel compliance — all from your iPhone.",
            ["Identity verification across 4000+ document types", "AML/sanctions screening against 1300+ watchlists", "Maritime document portfolio with expiry tracking"]
        ),
        (
            "person.badge.shield.checkmark",
            "Verify Anyone\nin the Chain",
            "From seafarers to beneficial owners, OceanCheck covers every entity in the maritime compliance chain.",
            ["Crew: passport scan + STCW certificates", "Ownership: UBO declaration + KYB verification", "Remote: send a link, they verify themselves"]
        ),
        (
            "key",
            "What You'll Need",
            "OceanCheck connects to verification services that require API credentials.",
            ["Didit API key — for identity & AML verification", "Workflow ID — for remote crew invitations", "Claude API key (optional) — for certificate OCR"]
        )
    ]

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Content
                TabView(selection: $page) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        onboardingPage(pages[i])
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.smooth(duration: 0.3), value: page)

                Spacer()

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Color.primary : Color.primary.opacity(0.15))
                            .frame(width: i == page ? 20 : 6, height: 6)
                            .animation(.smooth(duration: 0.2), value: page)
                    }
                }
                .padding(.bottom, 32)

                // Action
                if page < pages.count - 1 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("Next")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 48)
                } else {
                    Button {
                        Haptics.success()
                        onComplete()
                    } label: {
                        Text("Get Started")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 48)
                }

                Button {
                    Haptics.light()
                    onComplete()
                } label: {
                    Text(page < pages.count - 1 ? "Skip" : "")
                        .font(Typo.meta).foregroundStyle(.secondary)
                }
                .opacity(page < pages.count - 1 ? 1 : 0)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private func onboardingPage(_ content: (icon: String, title: String, subtitle: String, details: [String])) -> some View {
        VStack(spacing: 24) {
            Image(systemName: content.icon)
                .font(.system(size: 56))
                .foregroundStyle(.primary.opacity(0.12))

            Text(content.title)
                .font(BrandFont.brand(26))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Text(content.subtitle)
                .font(Typo.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(content.details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                        Text(detail)
                            .font(Typo.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
    }
}
