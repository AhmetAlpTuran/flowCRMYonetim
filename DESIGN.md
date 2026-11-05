---
version: 1.0
name: Flow CRM · Gece mesaisi
description: A calm, dark command center for WhatsApp support, the AI assistant and consented campaigns.
colors:
  dark:
    canvas: "#0E1116"
    surface: "#161B22"
    raised: "#1C232D"
    sunken: "#0A0D12"
    border: "#262E3A"
    border-strong: "#3A4452"
    text: "#F4F6F8"
    muted: "#9AA4B2"
    faint: "#8692A2"
    lime: "#C6F432"
    on-lime: "#0E1116"
    accent-text: "#C6F432"
    teal: "#2DD4BF"
    warning: "#F5B841"
    info: "#7CB7FF"
    danger: "#FF6B5B"
  light:
    canvas: "#F4F5F0"
    surface: "#FFFFFF"
    raised: "#ECEEE7"
    border: "#DDE1D6"
    text: "#0E1116"
    muted: "#4A5361"
    lime: "#C6F432 (fill only, ink outline)"
    accent-text: "#3F6212"
    teal: "#0F766E"
    warning: "#8C5A00"
    info: "#1D4ED8"
    danger: "#B03A0A"
typography:
  heading: { fontFamily: "BricolageDisplay (Bricolage Grotesque, opsz 40)", weights: [700, 800] }
  body: { fontFamily: "Bricolage (Bricolage Grotesque, opsz 14)", weights: [400, 500, 600, 700] }
  mono: { fontFamily: "JetBrainsMono", weights: [400, 500, 600], fallback: "Bricolage for ₺" }
rounded: { control: "10px", card: "14px", panel: "18px", tag: "999px" }
spacing: [4, 8, 12, 16, 24, 32]
---

# Flow CRM design brief: "Gece mesaisi"

This file is binding for every screen, the website and the payment pages. The code
source of truth is `lib/ui/` (`tokens.dart`, `app_theme.dart`, `app_typography.dart`,
`components/`). The approved prototype is the "Flow CRM · Gece mesaisi" canvas artifact.
`test/ui/design_guard_test.dart` and `test/ui/tokens_contrast_test.dart` enforce it.

## Concept

Flow is the night-shift team that never sleeps: a calm, dark command center where the
live queue, the assistant and the team are visible at a glance. Dark is the default;
light ("Açık") is a full second theme. The sidebar stays ink in both.

## Color

- One ground (canvas → surface → raised) and **one accent, lime**. Lime is for primary
  buttons, focus, the live dot, selected navigation and meters. Text and icons on lime
  are always ink (`onLime`). In light mode lime is a fill only, outlined in ink; lime
  text becomes olive `accentText`.
- **Teal means the assistant / bot** everywhere (tags, bubbles, KPIs).
- Status uses `FlowTone`: accent (new, done), assistant, warning (waiting, near limit),
  info (needs reply), danger (errors, opted out), neutral (draft, closed).
- Read colors only through `FlowColors.of(context)` or `Theme.of(context).colorScheme`.
  No `Colors.x` and no `Color(0x…)` in `lib/features` (the guard test fails).
- Every text pair reaches 4.5:1 in both themes; meters reach 3:1 against their track.

## Typography

- Headings: Bricolage Grotesque display cut, 800 weight, tight tracking (TextTheme
  `display*`, `headline*`, `titleLarge`).
- UI text: Bricolage Grotesque text cut (`body*`, `label*`, `titleMedium/Small`).
- **Mono (JetBrains Mono) for everything numeric or live**: KPIs (`FlowText.number`),
  times, prices, phone numbers, counts (`FlowText.mono`) and small caps status labels
  (`FlowText.caps`, always via `upperTr` for Turkish capitals).
- Keep big jumps: KPI numerals are 3× or more their labels.
- Fonts are bundled (`assets/fonts`, OFL). Never fetch fonts at runtime.

## Shape, depth, motion

- Radii: 10 controls, 14 cards, 18 panels and sheets, pill tags. No other radii.
- No shadows in dark mode: depth comes from surface steps and 1 px borders. Light mode
  may use one soft shadow on overlays only.
- One staggered entrance per page (`FlowMotion.entrance`, 60 ms stagger), the live-dot
  pulse, nothing else. Respect `FlowMotion.reduced(context)`.

## Signature motifs (sparingly)

- `DotGrid` behind welcome, sign-in, empty states and hero cards; never behind lists.
- `SignalRings` in empty states and hero cards.
- `LiveLine` ("● CANLI · 3 SOHBET BEKLİYOR") for live counts.
- Chat roles: customer = raised bubble on the left; bot = teal outline on the right
  with `RoleTag.bot()`; team = lime tint on the right with `RoleTag.agent(initials)`.

## Layout and navigation

- `AppShell` owns navigation and the page title: seven areas (Ana sayfa, Sohbetler,
  Müşteriler, Asistan, Katalog, Kampanyalar, Ayarlar), each showing its screens as tabs.
  Below 720 px it uses a bottom bar (4 areas + "Daha fazla"); from 1100 px the sidebar
  shows labels.
- Screens render only their body with `AppPage` (gutters 16/24/40, max width 1120),
  `PageToolbar` for search and actions, and `SectionCard` panels. Wrap, don't overflow,
  at 320 px.
- One primary (lime) button per view; secondary actions are outlined, tertiary are text.

## Components (`lib/ui/components`)

| Need | Use |
|---|---|
| Page body, toolbar, panel, eyebrow, list + detail | `AppPage`, `PageToolbar`, `SectionCard`, `Eyebrow`, `ListDetailLayout` |
| Status, roles, counts, avatars | `StatusBadge`, `RoleTag`, `CountPill`, `InitialsAvatar` |
| Numbers and limits | `StatTile`, `UsageBar`, `KeyValueRow` |
| Search and filters | `SearchField`, `FilterChipsRow` |
| Empty, failed, loading | `EmptyState`, `ErrorState`, `LoadingList` |
| Motifs and logo | `DotGrid`, `SignalRings`, `FlowLogo` (the lime f on an ink tile, `assets/brand`), `LiveDot`, `LiveLine` |
| Feedback | `confirmAction`, `showAppSnack` |
| Formatting | `lib/ui/format.dart` (local time, ₺, phone, Turkish dates, initials) |

## Copy

Turkish with proper letters, plain words ("İşletme", not "Tenant"; "Temsilciye aktar",
not "handoff"). Verbs on buttons. Empty states invite one action. Never show raw
backend errors; map them with the feature's `*ErrorMessage` helper.

## Don'ts

Inter, Roboto or system fonts; purple or rainbow gradients; colored shadows; emoji as
icons; lime text on light backgrounds; more than one primary button per view; a dot
grid behind dense content; raw error strings; English or ASCII-only Turkish labels.
