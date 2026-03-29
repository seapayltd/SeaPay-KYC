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

    // Font is registered automatically via UIAppFonts in Info.plist — no manual CTFontManager needed
    static func registerIfNeeded() { /* no-op — UIAppFonts handles registration */ }

    private static var ok: Bool { UIFont(name: postScriptName, size: 12) != nil }
    static func brand(_ size: CGFloat) -> Font { ok ? .custom(postScriptName, size: size) : .system(size: size) }
    static func uiFont(size: CGFloat) -> UIFont { UIFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size) }
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

// MARK: - Haptics

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

// MARK: - Status Badge (dot + label, pulse animation for flagged)

struct StatusBadge: View {
    let status: KYCCheck.CheckStatus
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
                .opacity(shouldPulse ? (pulse ? 0.5 : 1.0) : 1.0)
            Text(shortLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .onAppear {
            if shouldPulse {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
        .accessibilityLabel("Status: \(shortLabel)")
    }

    private var shouldPulse: Bool { status == .failed || status == .requiresReview }

    private var color: Color {
        switch status {
        case .passed: .clear_; case .failed: .flagged; case .requiresReview: .review
        case .pending: Color.secondary.opacity(0.5); case .inProgress: Color.secondary.opacity(0.6); case .incomplete: Color.secondary.opacity(0.4)
        }
    }
    private var shortLabel: String {
        switch status {
        case .passed: L10n.Status.clear; case .failed: L10n.Status.flagged; case .requiresReview: L10n.Status.review
        case .pending: L10n.Status.pending; case .inProgress: L10n.Status.active; case .incomplete: L10n.Status.draft
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

// MARK: - Verdict (with optional review audit trail)

struct VerdictBanner: View {
    let status: KYCCheck.CheckStatus
    var reviewDecision: KYCCheck.ReviewDecision? = nil
    var reviewedBy: String? = nil
    var reviewedAt: Date? = nil
    var reviewReason: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title).font(Typo.context)
                Spacer()
            }

            // Review audit trail (only when a decision has been made)
            if let decision = reviewDecision {
                VStack(alignment: .leading, spacing: 4) {
                    if let by = reviewedBy, !by.isEmpty {
                        Text("\(decision.rawValue) by \(by)")
                            .font(Typo.meta).foregroundStyle(.secondary)
                    }
                    if let at = reviewedAt {
                        Text(at.formatted(date: .abbreviated, time: .shortened))
                            .font(Typo.meta).foregroundStyle(.tertiary)
                    }
                    if let reason = reviewReason, !reason.isEmpty {
                        Text("\"\(reason)\"")
                            .font(Typo.meta).foregroundStyle(.secondary).italic()
                    }
                }
                .padding(.leading, 22) // Align with text after the dot
            }
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

// MARK: - Step Indicator (setup flow)

struct StepIndicator: View {
    let totalSteps: Int
    let currentStep: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(Color.primary.opacity(i == currentStep ? 1 : 0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.3), value: currentStep)
    }
}

// MARK: - Role Chip (setup + settings)

struct RoleChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(Typo.body)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.primary : Color.surfaceMuted)
            .foregroundStyle(isSelected ? Color.surface : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(isSelected ? 1 : 1)
            .animation(.spring(response: 0.2), value: isSelected)
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let value: Int
    let total: Int
    var height: CGFloat = 3

    private var fraction: CGFloat {
        total > 0 ? CGFloat(min(value, total)) / CGFloat(total) : 0
    }

    private var fillColor: Color {
        total > 0 && value >= total ? .clear_ : .secondary
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surfaceMuted)
                Capsule().fill(fillColor)
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(value) of \(total) complete")
    }
}

// MARK: - Hero Image View

struct HeroImageView: View {
    let imageData: Data?
    var fallbackIcon: String = "ferry"
    var overlayTitle: String?
    var aspectRatio: CGFloat = 16.0 / 9.0
    var height: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let h = height ?? (geo.size.width / aspectRatio)
            ZStack(alignment: .bottomLeading) {
                if let data = imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width, height: h)
                        .clipped()

                    // Gradient overlay for text readability
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        .frame(height: h * 0.6)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    Color.surfaceMuted
                        .overlay {
                            Image(systemName: fallbackIcon)
                                .font(.system(size: 36))
                                .foregroundStyle(.quaternary)
                        }
                }

                if let title = overlayTitle, imageData != nil {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .padding(.horizontal, 18).padding(.bottom, 14)
                }
            }
            .frame(width: geo.size.width, height: h)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

// MARK: - Metadata Pill

struct MetadataPill: View {
    let icon: String?
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(text).font(Typo.meta)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.surfaceMuted)
        .clipShape(Capsule())
    }
}

// MARK: - Custom Segmented Picker

struct CustomSegmentedPicker: View {
    let items: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3)) { selection = i }
                } label: {
                    Text(items[i])
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == i ? Color.surface : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selection == i {
                                    Capsule().fill(Color.primary)
                                        .matchedGeometryEffect(id: "seg", in: segmentNS)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.surfaceMuted)
        .clipShape(Capsule())
    }

    @Namespace private var segmentNS
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(Typo.meta).fontWeight(.medium)
            .foregroundStyle(isSelected ? Color.surface : .secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? Color.primary : Color.surfaceMuted)
            .clipShape(Capsule())
    }
}

// MARK: - Expandable Section

struct ExpandableSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let content: Content

    init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title.uppercased()).font(Typo.meta).foregroundStyle(.secondary).tracking(0.6)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Readiness Card

struct ReadinessCard: View {
    let completed: Int
    let total: Int
    var expiringCount: Int = 0
    var expiredCount: Int = 0
    var label: String = "required documents"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(completed) of \(total) \(label)").font(Typo.context)
            ProgressBar(value: completed, total: total)

            if expiringCount > 0 || expiredCount > 0 {
                HStack(spacing: 8) {
                    if expiredCount > 0 {
                        MetadataPill(icon: "xmark.circle", text: "\(expiredCount) Expired")
                    }
                    if expiringCount > 0 {
                        MetadataPill(icon: "exclamationmark.triangle", text: "\(expiringCount) Expiring")
                    }
                }
            }
        }
        .padding(16)
        .background(Color.surfaceMuted.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Tree Connector

struct TreeConnector: View {
    let depth: Int
    let isLast: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { level in
                if level < depth - 1 {
                    // Vertical continuation line for parent levels
                    Rectangle().fill(Color.primary.opacity(0.1))
                        .frame(width: 2)
                        .padding(.leading, 12)
                } else {
                    // Branch connector for this level
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.primary.opacity(0.1))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                        if isLast {
                            Color.clear.frame(width: 2).frame(maxHeight: .infinity)
                        } else {
                            Rectangle().fill(Color.primary.opacity(0.1))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 2)
                    .padding(.leading, 12)

                    // Horizontal branch
                    Rectangle().fill(Color.primary.opacity(0.1))
                        .frame(width: 14, height: 2)
                }
            }
        }
        .frame(width: CGFloat(depth) * 28)
    }
}

// MARK: - Review Ceremony View

struct ReviewCeremonyView: View {
    let personName: String
    let documentType: String?
    let amlStatus: String?
    let decision: ReviewDecisionType
    @Binding var reason: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    enum ReviewDecisionType {
        case approve, flag, decline

        var title: String {
            switch self {
            case .approve: return "Approve"
            case .flag: return "Flag for Review"
            case .decline: return "Decline"
            }
        }

        var icon: String {
            switch self {
            case .approve: return "checkmark.circle.fill"
            case .flag: return "flag.circle.fill"
            case .decline: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .approve: return .clear_
            case .flag: return .review
            case .decline: return .flagged
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 16)

            Image(systemName: decision.icon)
                .font(.system(size: 48))
                .foregroundStyle(decision.color)

            Text(decision.title).font(Typo.context)

            // Summary
            VStack(spacing: 4) {
                Text(personName).font(Typo.body).fontWeight(.medium)
                if let doc = documentType {
                    Text(doc).font(Typo.meta).foregroundStyle(.secondary)
                }
                if let aml = amlStatus {
                    Text("AML: \(aml)").font(Typo.meta).foregroundStyle(.secondary)
                }
            }

            // Reason
            VStack(alignment: .leading, spacing: 4) {
                Text("Reason").font(Typo.meta).foregroundStyle(.secondary)
                TextField("Required — record your decision", text: $reason, axis: .vertical)
                    .font(Typo.body)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)

            // Confirm
            Button {
                Haptics.success()
                onConfirm()
                // Brief delay for haptic to register, then dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
            } label: {
                Text("Confirm \(decision.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(reason.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : decision.color)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24)

            Button("Cancel") { dismiss() }
                .font(Typo.meta).foregroundStyle(.secondary)

            Spacer(minLength: 16)
        }
        .background(Color.surface.ignoresSafeArea())
    }
}
