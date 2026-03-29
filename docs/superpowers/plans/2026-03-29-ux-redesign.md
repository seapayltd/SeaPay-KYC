# OceanCheck UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace 3-tab navigation with a single scrolling Apple Health-style dashboard, enforce a strict design system, and use push navigation everywhere.

**Architecture:** Single `DashboardView` replaces `HomeView` tabs. All content screens use `NavigationStack` push. Workspace collaboration woven into `VesselDetailView` instead of a separate `FleetTabView`. Design system tokens (`Space`, `Typo`, card component) enforced across all views.

**Tech Stack:** SwiftUI, iOS 16+, existing `KYCViewModel` + `CollaborationService`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `SeaPay KYC/DesignSystem.swift` | Rewrite | Spacing tokens, typography, buttons, card component, colors |
| `SeaPay KYC/DashboardView.swift` | Create | Single scrolling dashboard (replaces HomeView) |
| `SeaPay KYC/VesselDetailView.swift` | Refactor | Add workspace section, enforce card style, push crew |
| `SeaPay KYC/PersonDetailView.swift` | Create | Push-based crew/person detail (replaces VerificationSheet usage) |
| `SeaPay KYC/SeaPay_KYCApp.swift` | Simplify | Remove tab state, use DashboardView |
| `SeaPay KYC/SetupView.swift` | Refactor | Push from gear icon, collaborator scoping |
| `SeaPay KYC/HomeView.swift` | Delete | Replaced by DashboardView |
| `SeaPay KYC/WorkspaceView.swift` | Delete | Workspace woven into VesselDetailView |

---

### Task 1: Design System Foundation

**Files:**
- Modify: `SeaPay KYC/DesignSystem.swift`

- [ ] **Step 1: Add spacing tokens**

Add after the `Color` extension (line 57):

```swift
// MARK: - Spacing (4pt grid)

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
```

- [ ] **Step 2: Replace Typo enum**

Replace the existing `enum Typo` (lines 66-72) with:

```swift
enum Typo {
    static let title: Font = .system(size: 20, weight: .semibold)
    static let body: Font = .system(size: 14)
    static let caption: Font = .system(size: 12, weight: .medium)
    static let micro: Font = .system(size: 10)

    // Legacy — remove after full migration
    static let hero: Font = .system(size: 32, weight: .bold)
    static let context: Font = .system(size: 16, weight: .semibold)
    static let stat: Font = .system(size: 18, weight: .bold, design: .rounded)
    static let meta: Font = .system(size: 11)
}
```

Keep legacy aliases so existing views don't break. They'll be removed in Task 9.

- [ ] **Step 3: Add semantic color tokens**

Add to the `extension Color` block (after line 56):

```swift
    // Semantic text
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(.tertiaryLabel)

    // Dividers
    static let separator = Color.primary.opacity(0.06)
```

- [ ] **Step 4: Add InlineButtonStyle**

Add after `SecondaryButtonStyle`:

```swift
struct InlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.primary)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
```

- [ ] **Step 5: Add CardView component**

Add after the button styles:

```swift
// MARK: - Card Component

struct CardView<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(Space.lg)
            .background(Color.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.separator, lineWidth: 0.5))
    }
}
```

- [ ] **Step 6: Build and verify**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`
Expected: No errors (legacy aliases keep existing views working)

- [ ] **Step 7: Commit**

```bash
git add "SeaPay KYC/DesignSystem.swift"
git commit -m "feat: design system foundation — spacing tokens, new typography, card component"
```

---

### Task 2: Dashboard View

**Files:**
- Create: `SeaPay KYC/DashboardView.swift`

- [ ] **Step 1: Create DashboardView with fleet status section**

```swift
//
//  DashboardView.swift
//  OceanCheck
//
//  Apple Health-inspired single scrolling dashboard.
//  Replaces the 3-tab HomeView.
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.xl) {
                    // Fleet Status
                    fleetStatusSection

                    // Needs Attention
                    needsAttentionSection

                    // Recent Activity
                    recentActivitySection

                    // Quick Actions
                    quickActionsSection

                    Spacer(minLength: Space.xxl)
                }
                .padding(.top, Space.lg)
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("OceanCheck").font(BrandFont.brand(20))
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { SettingsSheet(vm: vm, appState: appState) } label: {
                        Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Fleet Status (horizontal vessel cards)

    private var fleetStatusSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(isCollaborator ? "Shared Vessels" : "Fleet Status")
                .font(Typo.caption).foregroundStyle(.secondary).tracking(0.3)
                .padding(.horizontal, Space.lg)

            if vm.vessels.isEmpty {
                CardView {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "ferry").font(.system(size: 28)).foregroundStyle(.quaternary)
                        Text("No vessels yet").font(Typo.body).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Space.xl)
                }
                .padding(.horizontal, Space.lg)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.md) {
                        ForEach(Array(vm.vessels.enumerated()), id: \.element.id) { index, vessel in
                            NavigationLink { VesselDetailView(vm: vm, vessel: vessel) } label: {
                                vesselHealthCard(vessel)
                            }
                            .buttonStyle(.plain)
                            .opacity(1)
                            .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: vm.vessels.count)
                        }
                    }
                    .padding(.horizontal, Space.lg)
                }
            }
        }
    }

    private func vesselHealthCard(_ vessel: Vessel) -> some View {
        let crew = vm.checksForVessel(vessel.id)
        let passed = crew.filter { $0.status == .passed }.count
        let hasFlag = crew.contains { $0.status == .failed }
        let hasWarning = !hasFlag && crew.contains { $0.status == .requiresReview }
        let photoData = vessel.photoFilename.flatMap { vm.loadDocumentImage(filename: $0) }

        return VStack(alignment: .leading, spacing: Space.sm) {
            // Photo or icon
            ZStack {
                if let data = photoData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 140, height: 80).clipped()
                } else {
                    Color.surfaceMuted
                        .overlay { Image(systemName: vessel.vesselType?.icon ?? "ferry").font(.system(size: 20)).foregroundStyle(.secondary) }
                        .frame(width: 140, height: 80)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(vessel.name).font(Typo.body).fontWeight(.semibold).lineLimit(1)
                    Circle().fill(hasFlag ? Color.flagged : hasWarning ? Color.review : Color.clear_)
                        .frame(width: 6, height: 6)
                }
                Text("\(crew.count) crew \u{2022} \(passed) clear")
                    .font(Typo.micro).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.xs)
        }
        .frame(width: 148)
        .padding(.bottom, Space.sm)
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.separator, lineWidth: 0.5))
    }

    // MARK: - Needs Attention

    private var needsAttentionSection: some View {
        let expiredChecks = vm.expiredChecks
        let expiringChecks = vm.expiringChecks
        let reviewChecks = vm.checks.filter { $0.status == .requiresReview }
        let items: [(icon: String, color: Color, text: String, id: String)] =
            expiredChecks.map { ("circle.fill", .flagged, "\($0.displayName) — ID expired", $0.id) } +
            expiringChecks.map { ("circle.fill", .review, "\($0.displayName) — expiring soon", $0.id) } +
            reviewChecks.map { ("circle.fill", .review, "\($0.displayName) — needs review", $0.id) }

        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Needs Attention")
                        .font(Typo.caption).foregroundStyle(.secondary).tracking(0.3)
                        .padding(.horizontal, Space.lg)

                    CardView {
                        VStack(spacing: 0) {
                            ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading, Space.xl) }
                                HStack(spacing: Space.md) {
                                    Circle().fill(item.color).frame(width: 8, height: 8)
                                    Text(item.text).font(Typo.body).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, Space.md)
                            }
                        }
                    }
                    .padding(.horizontal, Space.lg)
                }
            }
        }
    }

    // MARK: - Recent Activity

    @State private var showActivity = false

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Button { withAnimation(.smooth(duration: 0.25)) { showActivity.toggle() } } label: {
                HStack {
                    Text("Recent Activity")
                        .font(Typo.caption).foregroundStyle(.secondary).tracking(0.3)
                    Spacer()
                    Image(systemName: showActivity ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.lg)

            if showActivity {
                CardView {
                    VStack(spacing: Space.sm) {
                        if vm.checks.isEmpty {
                            Text("No activity yet").font(Typo.body).foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.checks.prefix(5)) { check in
                                HStack(spacing: Space.sm) {
                                    Circle().fill(Color.surfaceMuted).frame(width: 24, height: 24)
                                        .overlay { Text(String(check.displayName.prefix(1)).uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                                    Text(check.displayName).font(Typo.body).lineLimit(1)
                                    Spacer()
                                    Text(check.status.rawValue).font(Typo.micro).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.lg)
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Quick Actions")
                .font(Typo.caption).foregroundStyle(.secondary).tracking(0.3)
                .padding(.horizontal, Space.lg)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.sm) {
                if isCollaborator {
                    quickAction(icon: "doc.badge.plus", label: "Upload Doc")
                    quickAction(icon: "arrow.triangle.2.circlepath", label: "Sync")
                    quickAction(icon: "square.and.arrow.down", label: "Download")
                } else {
                    NavigationLink { VesselSheet(vm: vm) } label: { quickAction(icon: "ferry", label: "Add Vessel") }
                    quickAction(icon: "person.badge.plus", label: "Add Crew")
                    quickAction(icon: "tablecells", label: "Export")
                    quickAction(icon: "person.2.badge.plus", label: "Batch Invite")
                }
            }
            .padding(.horizontal, Space.lg)
        }
    }

    private func quickAction(icon: String, label: String) -> some View {
        VStack(spacing: Space.sm) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.secondary)
            Text(label).font(Typo.caption).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.lg)
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.separator, lineWidth: 0.5))
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`
Expected: No errors (DashboardView not yet wired in)

- [ ] **Step 3: Commit**

```bash
git add "SeaPay KYC/DashboardView.swift"
git commit -m "feat: dashboard view — fleet cards, needs attention, activity, quick actions"
```

---

### Task 3: Wire Dashboard into App Entry

**Files:**
- Modify: `SeaPay KYC/SeaPay_KYCApp.swift`

- [ ] **Step 1: Replace HomeView with DashboardView**

Find in `SeaPay_KYCApp.swift` the line:
```swift
HomeView(vm: vm, appState: appState)
```

Replace with:
```swift
DashboardView(vm: vm, appState: appState)
```

- [ ] **Step 2: Remove sheet for settings (now push)**

Find and remove:
```swift
.sheet(isPresented: $showSettings) { SettingsSheet(vm: vm, appState: appState) }
```

Settings is now accessed via NavigationLink push inside DashboardView's toolbar.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`
Expected: No errors. App launches to dashboard instead of tabs.

- [ ] **Step 4: Commit**

```bash
git add "SeaPay KYC/SeaPay_KYCApp.swift"
git commit -m "feat: wire dashboard as main view, settings via push"
```

---

### Task 4: Vessel Detail — Workspace Integration

**Files:**
- Modify: `SeaPay KYC/VesselDetailView.swift`

- [ ] **Step 1: Add workspace section to VesselDetailView**

After the existing ownership section in VesselDetailView, add a workspace section. Find the end of the ownership section and add:

```swift
// MARK: - Workspace Section (if vessel is in a workspace)

@ViewBuilder
private var workspaceSection: some View {
    if CollaborationService.shared.isConnected {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("WORKSPACE").font(Typo.caption).foregroundStyle(.secondary).tracking(0.5)
                .padding(.horizontal, Space.lg)

            CardView {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack {
                        Image(systemName: "person.3").font(.system(size: 14)).foregroundStyle(.secondary)
                        Text(CollaborationService.shared.workspace?.name ?? "Workspace")
                            .font(Typo.body).fontWeight(.medium)
                        Spacer()
                        Button {
                            Task {
                                let v = vm.vessels.first(where: { $0.id == vessel.id })
                                guard let v else { return }
                                _ = try? await CollaborationService.shared.pushVessel(vessel: v, checks: vm.checksForVessel(v.id))
                                await FilesSyncService.shared.uploadMissingFiles(vesselId: v.id, vm: vm)
                                Haptics.success()
                            }
                        } label: {
                            HStack(spacing: Space.xs) {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                                Text("Sync").font(Typo.caption)
                            }.foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.lg)
        }
    }
}
```

Then include `workspaceSection` in the vessel detail scroll view body after ownership.

- [ ] **Step 2: Enforce card style on crew rows**

Replace any `.padding(.horizontal, 20)` on crew rows with `.padding(.horizontal, Space.lg)` and ensure crew rows use consistent spacing.

- [ ] **Step 3: Change crew tap from sheet to push**

Find where crew member tap opens a sheet (`.sheet(item: $activeCheck)`) and change to `NavigationLink`:

```swift
NavigationLink { PersonDetailView(vm: vm, check: check) } label: {
    crewRow(check)
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`

- [ ] **Step 5: Commit**

```bash
git add "SeaPay KYC/VesselDetailView.swift"
git commit -m "feat: vessel detail — workspace section, push crew, card style"
```

---

### Task 5: Person Detail View

**Files:**
- Create: `SeaPay KYC/PersonDetailView.swift`

- [ ] **Step 1: Create PersonDetailView**

```swift
//
//  PersonDetailView.swift
//  OceanCheck
//
//  Push-based person/crew detail. Replaces sheet-based VerificationSheet
//  for viewing existing crew members.
//

import SwiftUI

struct PersonDetailView: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    private var c: KYCCheck { vm.checks.first(where: { $0.id == check.id }) ?? check }
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                // Header
                headerSection

                // Identity
                identitySection

                // Documents
                documentsSection

                // Review (agents only)
                if !isCollaborator { reviewSection }

                // PDF Report
                Button { /* generate report */ } label: { Text("Generate PDF Report") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Space.xxl)

                Spacer(minLength: Space.xxl)
            }
            .padding(.top, Space.lg)
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Space.md) {
            // Avatar
            Circle().fill(Color.surfaceMuted).frame(width: 64, height: 64)
                .overlay {
                    if let photo = c.profilePhoto, let data = vm.loadDocumentImage(filename: photo), let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill().clipShape(Circle())
                    } else {
                        Text(String(c.displayName.prefix(1)).uppercased()).font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }

            VStack(spacing: Space.xs) {
                Text(c.displayName).font(Typo.title)
                HStack(spacing: Space.sm) {
                    if let rank = c.crewRank { Text(rank.rawValue).font(Typo.caption).foregroundStyle(.secondary) }
                    if let nat = c.nationality { Text(nat).font(Typo.caption).foregroundStyle(.secondary) }
                }
                StatusBadge(status: c.status)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Identity

    private var identitySection: some View {
        CardView {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("IDENTITY").font(Typo.caption).foregroundStyle(.secondary).tracking(0.5)
                if let dt = c.documentType { infoRow("Document", dt) }
                if let dn = c.documentNumber { infoRow("Number", dn) }
                if let exp = c.expiryDate { infoRow("Expires", exp) }
                if let aml = c.amlStatus { infoRow("AML", aml) }
            }
        }
        .padding(.horizontal, Space.lg)
    }

    // MARK: - Documents

    private var documentsSection: some View {
        let docs = (c.documents ?? []).filter { !$0.isArchived }
        let valid = docs.filter { $0.status == .valid }.count

        return VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("DOCUMENTS").font(Typo.caption).foregroundStyle(.secondary).tracking(0.5)
                Spacer()
                Text("\(valid)/\(docs.count)").font(Typo.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.lg)

            if docs.isEmpty {
                CardView {
                    Text("No documents").font(Typo.body).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Space.lg)
            } else {
                CardView {
                    VStack(spacing: 0) {
                        ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                            if index > 0 { Divider().padding(.leading, Space.xl) }
                            NavigationLink {
                                DocumentDetailSheet(vm: vm, checkId: c.id, document: doc)
                            } label: {
                                HStack(spacing: Space.md) {
                                    Circle().fill(doc.statusColor.opacity(0.15)).frame(width: 28, height: 28)
                                        .overlay { Image(systemName: doc.type.icon).font(.system(size: 11)).foregroundStyle(doc.statusColor) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(doc.type.displayName).font(Typo.body).lineLimit(1)
                                        Text(doc.statusLabel).font(Typo.micro).foregroundStyle(doc.statusColor)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                                }
                                .padding(.vertical, Space.md)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Space.lg)
            }
        }
    }

    // MARK: - Review

    @State private var pendingReview: KYCCheck.ReviewDecision?
    @State private var reviewReason = ""

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("REVIEW").font(Typo.caption).foregroundStyle(.secondary).tracking(0.5)
                .padding(.horizontal, Space.lg)

            CardView {
                if let decision = c.reviewDecision {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack {
                            StatusBadge(status: c.status)
                            Spacer()
                            if let by = c.reviewedBy { Text("by \(by)").font(Typo.micro).foregroundStyle(.secondary) }
                        }
                        if let reason = c.reviewReason, !reason.isEmpty {
                            Text(reason).font(Typo.body).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: Space.sm) {
                        Button { vm.submitReview(checkId: c.id, decision: .approved, reason: "") } label: {
                            Text("Approve").font(Typo.caption).foregroundStyle(Color.clear_).frame(maxWidth: .infinity).padding(.vertical, Space.md)
                                .background(Color.clear_.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button { vm.submitReview(checkId: c.id, decision: .flagged, reason: "") } label: {
                            Text("Flag").font(Typo.caption).foregroundStyle(Color.review).frame(maxWidth: .infinity).padding(.vertical, Space.md)
                                .background(Color.review.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button { vm.submitReview(checkId: c.id, decision: .declined, reason: "") } label: {
                            Text("Decline").font(Typo.caption).foregroundStyle(Color.flagged).frame(maxWidth: .infinity).padding(.vertical, Space.md)
                                .background(Color.flagged.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(.horizontal, Space.lg)
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Typo.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).font(Typo.body)
            Spacer()
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`

- [ ] **Step 3: Commit**

```bash
git add "SeaPay KYC/PersonDetailView.swift"
git commit -m "feat: person detail view — push-based, card style, role-scoped"
```

---

### Task 6: Settings Push Navigation

**Files:**
- Modify: `SeaPay KYC/SetupView.swift`

- [ ] **Step 1: Change SettingsSheet to be push-compatible**

The `SettingsSheet` is currently presented as a `.sheet`. Since `DashboardView` uses `NavigationLink` to push it, it needs to work inside a `NavigationStack`. The current implementation already uses `NavigationStack` internally — remove the inner `NavigationStack` wrapper so it doesn't double-nest:

Find the opening `NavigationStack {` in `SettingsSheet` and remove it (keep the content). The parent `DashboardView`'s `NavigationStack` provides the navigation context.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`

- [ ] **Step 3: Commit**

```bash
git add "SeaPay KYC/SetupView.swift"
git commit -m "refactor: settings compatible with push navigation"
```

---

### Task 7: Collaborator Scoping Pass

**Files:**
- Modify: `SeaPay KYC/DashboardView.swift`
- Modify: `SeaPay KYC/PersonDetailView.swift`

- [ ] **Step 1: Dashboard collaborator variant**

The `isCollaborator` computed property already exists in `DashboardView`. Verify the following are correctly scoped:
- Fleet Status title shows "Shared Vessels" for collaborators
- Quick Actions grid shows Upload/Sync/Download for collaborators
- "Add Vessel" and "Batch Invite" hidden for collaborators

- [ ] **Step 2: Person detail collaborator variant**

In `PersonDetailView`, verify:
- Review section hidden (already gated by `!isCollaborator`)
- ID images hidden — add to identity section:

```swift
if !isCollaborator, let paths = c.documentImagePaths, !paths.isEmpty {
    // Show ID thumbnails (agents only)
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`

- [ ] **Step 4: Commit**

```bash
git add "SeaPay KYC/DashboardView.swift" "SeaPay KYC/PersonDetailView.swift"
git commit -m "feat: collaborator scoping — dashboard + person detail"
```

---

### Task 8: Animation Polish

**Files:**
- Modify: `SeaPay KYC/DashboardView.swift`
- Modify: `SeaPay KYC/DesignSystem.swift`

- [ ] **Step 1: Remove all .repeatForever animations**

Search entire project for `.repeatForever` and remove. Replace with static opacity or single-fire animations.

In `DesignSystem.swift`, find the `StatusBadge` pulse animation:
```swift
withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
```

Replace with a single subtle scale:
```swift
withAnimation(.easeInOut(duration: 0.6)) { pulse = true }
```

- [ ] **Step 2: Ensure section expand uses .smooth**

In `DashboardView`, verify the activity toggle uses:
```swift
withAnimation(.smooth(duration: 0.25)) { showActivity.toggle() }
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`

- [ ] **Step 4: Archive build**

Run: `xcodebuild archive -scheme "SeaPay KYC" -archivePath /tmp/OceanCheckRedesign.xcarchive -configuration Release -sdk iphoneos 2>&1 | grep -E "error:|warning:" | grep -v ONLY_ACTIVE_ARCH`
Expected: Zero errors, zero warnings

- [ ] **Step 5: Commit**

```bash
git add "SeaPay KYC/DashboardView.swift" "SeaPay KYC/DesignSystem.swift"
git commit -m "polish: animation standards — no repeatForever, smooth transitions"
```

---

### Task 9: Dead Code Removal

**Files:**
- Delete: `SeaPay KYC/HomeView.swift`
- Delete: `SeaPay KYC/WorkspaceView.swift`
- Modify: `SeaPay KYC/DesignSystem.swift`

- [ ] **Step 1: Delete HomeView.swift**

```bash
git rm "SeaPay KYC/HomeView.swift"
```

- [ ] **Step 2: Delete WorkspaceView.swift**

```bash
git rm "SeaPay KYC/WorkspaceView.swift"
```

- [ ] **Step 3: Remove legacy Typo aliases**

In `DesignSystem.swift`, remove:
```swift
    // Legacy — remove after full migration
    static let hero: Font = .system(size: 32, weight: .bold)
    static let context: Font = .system(size: 16, weight: .semibold)
    static let stat: Font = .system(size: 18, weight: .bold, design: .rounded)
    static let meta: Font = .system(size: 11)
```

- [ ] **Step 4: Build and fix any remaining references**

Run: `xcodebuild -target "SeaPay KYC" -sdk iphonesimulator -configuration Debug build 2>&1 | grep "error:"`

Any errors from deleted files mean other views still reference `HomeView` or `WorkspaceView` or legacy `Typo` tokens. Fix each reference:
- `Typo.hero` → `Typo.title`
- `Typo.context` → `Typo.title` (or `Typo.body` depending on context)
- `Typo.meta` → `Typo.caption` or `Typo.micro`
- `Typo.stat` → `Typo.title`
- `FleetTabView` references → remove (workspace now in vessel detail)

- [ ] **Step 5: Archive build**

Run: `xcodebuild archive -scheme "SeaPay KYC" -archivePath /tmp/OceanCheckFinal.xcarchive -configuration Release -sdk iphoneos 2>&1 | grep -E "error:|warning:" | grep -v ONLY_ACTIVE_ARCH`
Expected: Zero errors, zero warnings

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "cleanup: remove HomeView, WorkspaceView, legacy Typo tokens"
```
