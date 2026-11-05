---
name: flow-crm-design
description: House style for Flow CRM ("Gece mesaisi"). Use for any UI work in this repo, Flutter screens, the docs/ website or the payment pages, before writing or restyling a widget, page or component.
---

# Flow CRM design rules

1. Read `DESIGN.md` at the repo root first. It is binding.
2. Flutter: import `package:wpapp/ui/ui.dart` (or the relative `ui/ui.dart`) and build from
   its components (`AppPage`, `PageToolbar`, `SectionCard`, `StatusBadge`, `StatTile`,
   `EmptyState`, `ErrorState`, `LoadingList`, `FilterChipsRow`, `SearchField`, `RoleTag`,
   `InitialsAvatar`, `confirmAction`, `showAppSnack`) and `lib/ui/format.dart`.
   - Colors only from `FlowColors.of(context)` / `colorScheme`; no `Colors.x`, no hex.
   - Numbers, times, prices and phone numbers in mono (`FlowText`).
   - The shell owns the page title and tabs; screens render only their body.
   - One lime primary button per view.
3. Website (`docs/`): same tokens as CSS variables, self-hosted fonts from
   `docs/assets/fonts`, dark first with a light toggle, no external font CDN.
4. Before finishing: `flutter analyze`, `flutter test --timeout 60s` (includes the design
   guard and contrast tests), and check 320 px and 1280 px in both themes.
