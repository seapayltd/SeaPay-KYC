//
//  DesignSystem.swift
//  SeaPay KYC
//

import SwiftUI

// MARK: - Brand Font (IvyMode)
//
// To use: drop IvyMode-Regular.otf, IvyMode-Bold.otf, IvyMode-SemiBold.otf
// into SeaPay KYC/Fonts/ and they'll be picked up automatically.
// Falls back to system font if not present.

enum BrandFont {
    private static let postScriptName = "IvyMode-Regular"
    private static var registered = false

    /// Register the font from the app bundle at launch. Call once.
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true

        // Try common filenames
        let candidates = ["ivy-mode-regular.ttf", "IvyMode-Regular.ttf", "ivy-mode-regular.otf", "IvyMode-Regular.otf"]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: nil) ??
                         Bundle.main.url(forResource: name.replacingOccurrences(of: ".ttf", with: ""), withExtension: "ttf") ??
                         Bundle.main.url(forResource: name.replacingOccurrences(of: ".otf", with: ""), withExtension: "otf") {
                var error: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    #if DEBUG
                    print("BrandFont: registered \(name) as \(postScriptName)")
                    #endif
                    return
                }
                #if DEBUG
                print("BrandFont: failed to register \(name): \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
                #endif
            }
        }
        #if DEBUG
        print("BrandFont: no font file found in bundle. Using system font.")
        #endif
    }

    private static var isAvailable: Bool {
        registerIfNeeded()
        return UIFont(name: postScriptName, size: 12) != nil
    }

    /// IvyMode Regular at the given size. Falls back to system regular if font not installed.
    static func brand(_ size: CGFloat) -> Font {
        isAvailable ? .custom(postScriptName, size: size) : .system(size: size)
    }

    /// UIFont version for PDF rendering — always regular weight.
    static func uiFont(size: CGFloat) -> UIFont {
        registerIfNeeded()
        return UIFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size)
    }
}

// MARK: - Flow Layout (wrapping tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        let maxW = proposal.width ?? .infinity
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX; var y: CGFloat = bounds.minY; var rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Colors

extension Color {
    static let brand = Color(red: 0.07, green: 0.45, blue: 0.87)
    static let brandDark = Color(red: 0.04, green: 0.32, blue: 0.70)
    static let brandLight = Color(red: 0.40, green: 0.70, blue: 1.0)
    static let surface = Color(.systemBackground)
    static let surfaceRaised = Color(.secondarySystemBackground)
    static let surfaceMuted = Color(.systemGray6)
    static let pass = Color(red: 0.20, green: 0.72, blue: 0.40)
    static let fail = Color(red: 0.90, green: 0.26, blue: 0.26)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.10)
}

extension LinearGradient {
    static let brand = LinearGradient(colors: [.brand, .brandDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let hero = LinearGradient(colors: [Color.brand.opacity(0.06), Color.brandLight.opacity(0.02), .clear], startPoint: .top, endPoint: .bottom)
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(isEnabled ? AnyShapeStyle(LinearGradient.brand) : AnyShapeStyle(Color.gray.opacity(0.35)))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: isEnabled ? Color.brand.opacity(0.3) : .clear, radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(Color.brand.opacity(0.08))
            .foregroundStyle(Color.brand)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Card

struct CardView<Content: View>: View {
    var padded = true
    let content: Content
    init(padded: Bool = true, @ViewBuilder content: () -> Content) { self.padded = padded; self.content = content() }
    var body: some View {
        content
            .padding(padded ? 16 : 0)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String?
    init(_ title: String, icon: String? = nil) { self.title = title; self.icon = icon }
    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: KYCCheck.CheckStatus
    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var color: Color {
        switch status {
        case .pending: .gray; case .inProgress: .blue; case .passed: .pass
        case .failed: .fail; case .requiresReview: .warning; case .incomplete: .purple
        }
    }
}

// MARK: - Risk Gauge

struct RiskGauge: View {
    let score: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.surfaceMuted, lineWidth: size * 0.12)
            Circle()
                .trim(from: 0, to: CGFloat(min(score, 100)) / 100)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: size * 0.32, weight: .bold, design: .rounded)).monospacedDigit()
                Text(label).font(.system(size: size * 0.12, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(gaugeColor)
    }

    private var gaugeColor: Color { score > 70 ? .fail : score > 40 ? .warning : .pass }
    private var label: String { score > 70 ? "HIGH" : score > 40 ? "MEDIUM" : "LOW" }
}

// MARK: - Verdict Banner

struct VerdictBanner: View {
    let status: KYCCheck.CheckStatus

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(color.gradient)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(color.opacity(0.15), lineWidth: 1))
    }

    private var color: Color { status == .passed ? .pass : status == .failed ? .fail : .warning }
    private var icon: String { status == .passed ? "checkmark" : status == .failed ? "xmark" : "exclamationmark" }
    private var title: String { status == .passed ? "All Checks Passed" : status == .failed ? "Verification Failed" : "Review Required" }
    private var subtitle: String { status == .passed ? "Identity confirmed, compliance clear" : status == .failed ? "One or more checks did not pass" : "Warnings detected, review details" }
}

// MARK: - Data Row

struct DataRow: View {
    let label: String
    let value: String
    var color: Color? = nil
    var bold: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(bold ? .caption.bold() : .caption.weight(.medium))
                .foregroundStyle(color ?? .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
