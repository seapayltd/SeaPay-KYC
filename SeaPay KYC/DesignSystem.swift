//
//  DesignSystem.swift
//  OceanCheck
//
//  Jony Ive redesign: monochrome base, color only for status,
//  4-size typography, minimal components.
//

import SwiftUI

// MARK: - Brand Font

enum BrandFont {
    private static let postScriptName = "IvyMode-Regular"
    private static var registered = false

    static func registerIfNeeded() {
        guard !registered else { return }; registered = true
        for name in ["ivy-mode-regular.ttf", "IvyMode-Regular.ttf", "ivy-mode-regular.otf", "IvyMode-Regular.otf"] {
            if let url = Bundle.main.url(forResource: name, withExtension: nil) ?? Bundle.main.url(forResource: name.replacingOccurrences(of: ".ttf", with: ""), withExtension: "ttf") {
                var err: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err) { return }
            }
        }
    }

    private static var ok: Bool { registerIfNeeded(); return UIFont(name: postScriptName, size: 12) != nil }
    static func brand(_ size: CGFloat) -> Font { ok ? .custom(postScriptName, size: size) : .system(size: size) }
    static func uiFont(size: CGFloat) -> UIFont { registerIfNeeded(); return UIFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size) }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var x: CGFloat = 0, y: CGFloat = 0, rh: CGFloat = 0; let mw = proposal.width ?? .infinity
        for sv in subviews { let s = sv.sizeThatFits(.unspecified); if x + s.width > mw && x > 0 { x = 0; y += rh + spacing; rh = 0 }; x += s.width + spacing; rh = max(rh, s.height) }
        return CGSize(width: mw, height: y + rh)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rh: CGFloat = 0
        for sv in subviews { let s = sv.sizeThatFits(.unspecified); if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rh + spacing; rh = 0 }; sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += s.width + spacing; rh = max(rh, s.height) }
    }
}

// MARK: - Colors (monochrome base, color = status only)

extension Color {
    // Monochrome
    static let surface = Color(.systemBackground)
    static let surfaceRaised = Color(.secondarySystemBackground)
    static let surfaceMuted = Color(.systemGray6)

    // Status — the only color in the app
    static let clear_ = Color(red: 0.20, green: 0.62, blue: 0.38) // green — passed
    static let flagged = Color(red: 0.85, green: 0.22, blue: 0.22) // red — failed
    static let review = Color(red: 0.82, green: 0.58, blue: 0.10) // amber — review

    // Legacy aliases (for existing code)
    static let brand = Color.primary
    static let pass = Color.clear_
    static let fail = Color.flagged
    static let warning = Color.review
}

// MARK: - Typography System (4 sizes)
//
//  hero:    32pt — the name being verified
//  context: 16pt — section labels
//  body:    13pt — data values
//  meta:    11pt — labels, timestamps, supporting text

enum Typo {
    static let hero: Font = .system(size: 32, weight: .bold)
    static let context: Font = .system(size: 16, weight: .semibold)
    static let stat: Font = .system(size: 18, weight: .bold, design: .rounded)
    static let body: Font = .system(size: 13, weight: .medium)
    static let meta: Font = .system(size: 11)
}

// MARK: - Primary Button (monochrome)

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(isEnabled ? Color.primary : Color.gray.opacity(0.3))
            .foregroundStyle(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(Color.primary.opacity(0.06))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - iPad Content Width

struct ContentWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.frame(maxWidth: 680).frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func iPadOptimized() -> some View { modifier(ContentWidth()) }
}

// MARK: - Card (clean, no shadow noise)

struct CardView<Content: View>: View {
    var padded = true
    let content: Content
    init(padded: Bool = true, @ViewBuilder content: () -> Content) { self.padded = padded; self.content = content() }
    var body: some View {
        content
            .padding(padded ? 16 : 0)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Section Header (minimal)

struct SectionHeader: View {
    let title: String
    let icon: String?
    init(_ title: String, icon: String? = nil) { self.title = title; self.icon = icon }
    var body: some View {
        Text(title.uppercased())
            .font(Typo.meta).foregroundStyle(.secondary).tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status Badge (dot + label for scannability)

struct StatusBadge: View {
    let status: KYCCheck.CheckStatus
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(shortLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
    }
    private var color: Color {
        switch status {
        case .passed: .clear_; case .failed: .flagged; case .requiresReview: .review
        case .pending: Color.secondary.opacity(0.5); case .inProgress: Color.secondary.opacity(0.6); case .incomplete: Color.secondary.opacity(0.4)
        }
    }
    private var shortLabel: String {
        switch status {
        case .passed: "Clear"; case .failed: "Flagged"; case .requiresReview: "Review"
        case .pending: "Pending"; case .inProgress: "Active"; case .incomplete: "Draft"
        }
    }
}

// MARK: - Risk Gauge

struct RiskGauge: View {
    let score: Int; let size: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.06), lineWidth: size * 0.1)
            Circle().trim(from: 0, to: CGFloat(min(score, 100)) / 100)
                .stroke(gc, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(.system(size: size * 0.3, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(gc)
        }.frame(width: size, height: size)
    }
    private var gc: Color { score > 70 ? .flagged : score > 40 ? .review : .clear_ }
}

// MARK: - Verdict (minimal)

struct VerdictBanner: View {
    let status: KYCCheck.CheckStatus
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).font(Typo.context)
            Spacer()
        }
        .padding(16)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var color: Color { status == .passed ? .clear_ : status == .failed ? .flagged : .review }
    private var title: String { status == .passed ? "Clear" : status == .failed ? "Flagged" : "Review Required" }
}

// MARK: - Data Row

struct DataRow: View {
    let label: String; let value: String; var color: Color? = nil; var bold: Bool = false
    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(Typo.meta).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(bold ? .system(size: 13, weight: .semibold) : Typo.body).foregroundStyle(color ?? .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
