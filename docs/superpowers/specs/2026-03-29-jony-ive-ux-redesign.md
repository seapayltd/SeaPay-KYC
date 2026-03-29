# OceanCheck UX Redesign — Apple Health-Inspired Dashboard

## Overview

Replace the 3-tab structure (Vessels/People/Fleet) with a single scrolling dashboard. Every screen follows push navigation. Strict design system with 4pt spacing grid, 4 typography levels, 3 button styles. Collaborators see the same structure scoped by role.

Reference: Apple Health — data-dense but breathable, summary cards, drill-down hierarchy.

---

## 1. Dashboard (replaces HomeView tabs)

Single scrolling page with 4 sections:

### Fleet Status
- Horizontal scroll of vessel "health cards" (like Health category cards)
- Each card: vessel photo/icon, name, flag, status dot (green/amber/red), crew count
- Tap → push to vessel detail
- Staggered fade-in on load (0.05s delay per card)

### Needs Attention
- Priority-sorted list: expired (red) → expiring (amber) → pending review
- Each row: status dot, document/person name, vessel name, time remaining
- Tap → push directly to the relevant detail (document, person, or vessel)

### Recent Activity
- Last 5 actions across all vessels/crew
- Agent avatar + action description + relative time
- Collapsible (default collapsed, tap header to expand)

### Quick Actions
- 2×2 grid of most common actions
- Agent: Add Vessel, Add Crew, Export, Batch Invite
- Collaborator: Upload Doc, Sync, Download, (empty or scenario checklist link)

### Toolbar
- Leading: "OceanCheck" in brand font (IvyMode)
- Trailing: Settings gear (push, not sheet)
- Trailing: Notification bell (if expiring items exist, shows badge)

---

## 2. Vessel Detail (pushed from dashboard card)

Single scroll page with sections:

### Hero Header
- Vessel photo (or gradient with icon if no photo)
- Vessel name (Typo.title), flag, IMO, GT, type as metadata pills
- Photo tap → camera/picker to change

### Compliance Summary Card
- Progress bar: X/Y certificates
- Crew count + verified count
- One-line status: "All clear" / "3 items need attention"

### Crew Section
- Rows: avatar, name, rank, status badge
- Sorted by status urgency (flagged first, then review, then clear)
- Tap row → push to person detail
- "+" button to add crew (push to form, not sheet)

### Certificates Section
- Rows: doc type icon, name, status, expiry date
- Grouped by category (Safety, Pollution, Insurance, etc.)
- Tap row → push to certificate detail
- "+" button to add certificate

### Ownership Section
- Collapsible. Shows structure type, shareholders, directors.
- Tap → push to ownership flow

### Workspace Section (conditional)
- Only shows if vessel is in a workspace
- Scenario name + agent avatars + sync status
- Sync button, Download Package in context menu
- Scenario checklist: X/Y docs ready (expandable)

---

## 3. Person Detail (pushed from crew row)

Single scroll page:

### Header
- Back button shows vessel name for context
- Avatar (large), name, rank, nationality
- Status badge + verification date

### Identity Card
- Passport type, number, expiry
- AML status + score
- No ID images for collaborators (PII protection)

### Documents Section
- Inline list with status per doc: ✓ valid, ⚠️ expiring (Xd), ● missing
- Progress: X/Y documents
- Tap row → push to document detail (image preview, metadata, share)

### Review Section
- Agent: Approve/Flag/Decline buttons
- Collaborator: read-only badge showing existing decision + reviewer name
- Agent notes field (agents only)

### Actions
- Generate PDF Report button at bottom

---

## 4. Transition Rules

### Navigation
- **Push** for going deeper into content (vessel → crew → document)
- **Sheet** for quick side-actions only: camera capture, date picker, share sheet, merge review
- **Never fullScreenCover** except first-launch onboarding
- Settings accessed via push (not sheet)

### Animations
- Push/pop: system default spring (0.35s) — never override
- Section expand/collapse: `.smooth(duration: 0.25)`
- Status changes: `.easeInOut(duration: 0.3)`
- Card load: staggered fade-in, 0.05s delay per card
- Sync overlay: spring in, ease-out disappear
- No `.repeatForever` animations (battery drain, feels anxious)

---

## 5. Design System

### Spacing (4pt grid)

| Token | Value | Usage |
|-------|-------|-------|
| `Space.xs` | 4pt | Inline gaps, icon spacing |
| `Space.sm` | 8pt | Between related items |
| `Space.md` | 12pt | Section internal padding |
| `Space.lg` | 16pt | Card padding, section margins |
| `Space.xl` | 24pt | Between sections |
| `Space.xxl` | 32pt | Page top/bottom margins |

### Typography (4 levels)

| Token | Spec | Usage |
|-------|------|-------|
| `Typo.title` | 20pt semibold | Screen titles, vessel names |
| `Typo.body` | 14pt regular | Body content, row labels |
| `Typo.caption` | 12pt medium | Badges, metadata, secondary info |
| `Typo.micro` | 10pt regular | Timestamps, IDs, fine print |

Brand font (IvyMode) only for "OceanCheck" header on dashboard.

### Buttons (3 styles)

| Style | Look | Rule |
|-------|------|------|
| `Primary` | Filled dark, full width | One per screen, the main action |
| `Secondary` | Outlined, full width | Alternative action |
| `Inline` | Text-only, tinted | Row actions, links |

No `.buttonStyle(.plain)` anywhere. Every tappable element uses one of these three.

### Colors

| Token | Value | Usage |
|-------|-------|-------|
| `Color.surface` | System background | Page backgrounds |
| `Color.surfaceRaised` | Secondary system bg | Cards |
| `Color.surfaceMuted` | System gray 6 | Avatars, pills |
| `Color.separator` | primary at 6% | All dividers |
| `Color.textPrimary` | primary | Titles |
| `Color.textSecondary` | secondary | Labels |
| `Color.textTertiary` | tertiary | Timestamps |
| `Color.clear_` | #33A062 | Passed/verified |
| `Color.flagged` | #D93939 | Failed |
| `Color.review` | #D19419 | Needs review |

### Card Component

```
16pt padding
surfaceRaised background
14pt corner radius
0.5pt separator stroke (Color.separator)
No shadow
```

Every card, row container, and section box uses this recipe.

---

## 6. Collaborator Scoping

Same dashboard structure, different content:

### Dashboard differences
- Leads with workspace context: scenario name, agent count, sync time
- "Shared Vessels" instead of "Fleet Status"
- Scenario checklist prominent: "14/18 docs ready for survey"
- Quick actions: Upload Doc, Sync, Download (no Add Vessel, Batch Invite, Export)
- No notification bell

### Vessel detail differences
- No "+" buttons for crew or certificates
- No verification triggers

### Person detail differences
- No review buttons (read-only badge with reviewer name)
- No ID document images (PII)
- Can view extracted data and document portfolio

### Settings differences
- No Connections section (API keys)
- No API Usage, no Demo Mode
- "Upgrade to Full Agent" banner at top

### Upgrade
- Banner in Settings pushes to API key entry
- Once key entered, dashboard transforms to full agent view immediately
- No app restart

---

## 7. Files Affected

| Current File | Action |
|-------------|--------|
| `HomeView.swift` | **Rewrite** — dashboard replaces tabs |
| `VesselDetailView.swift` | **Refactor** — add workspace section, enforce card style |
| `VerificationSheet.swift` | **Refactor** — push navigation instead of sheet, enforce design system |
| `DocumentPortfolioView.swift` | **Refactor** — inline in vessel/person detail, not separate view |
| `WorkspaceView.swift` | **Remove** — workspace woven into vessel detail |
| `DesignSystem.swift` | **Rewrite** — new spacing tokens, typography, button styles, card component |
| `SetupView.swift` | **Refactor** — push from settings gear, not sheet |
| `SeaPay_KYCApp.swift` | **Simplify** — remove tab state, sheet management |

---

## 8. Implementation Order

1. Design system foundation (DesignSystem.swift rewrite)
2. Dashboard (HomeView rewrite)
3. Vessel detail (refactor with workspace integration)
4. Person detail (push instead of sheet)
5. Certificate/document detail (consistent card style)
6. Settings (push navigation)
7. Collaborator scoping pass
8. Animation polish pass
9. Remove dead code (old tab system, WorkspaceView, etc.)
