---
version: alpha
name: Flow CRM
description: A calm operations workspace for WhatsApp support and consented campaigns.
colors:
  primary: "#1F4B99"
  secondary: "#00A896"
  tertiary: "#F2A541"
  background: "#F4F6FA"
typography:
  body:
    fontFamily: "Inter, sans-serif"
  heading:
    fontFamily: "Manrope, sans-serif"
rounded:
  card: "18px"
  control: "14px"
  chip: "20px"
spacing:
  page-padding: "20px"
  section-gap: "16px"
  field-gap: "12px"
components:
  form-field:
    rounded: "{rounded.control}"
  card:
    rounded: "{rounded.card}"
---

# Flow CRM design context

## Overview

Product register: a working desk for business support and campaign operators.
Preserve the established Flutter Material 3 interface. The signature is the
business's brand color in an otherwise quiet workspace. Navigation, message
content and task states carry hierarchy; avoid marketing decoration in forms.
Primary current copy is Turkish; the product brief targets SMBs generally, not
a particular regulated market. Proper Turkish spelling is the standard for new
copy. Existing ASCII-only labels and missing locale infrastructure are tracked debt.

Runtime ownership is model B: `lib/features/app/app.dart` owns theme values.
This file mirrors that theme; it does not generate a second token system.
Tenant brand color overrides the default seed; derived Material colors must be
consumed through Theme.of(context).colorScheme, not copied as feature literals.

## Colors

The blue seed, teal secondary and amber tertiary come from the shared theme.
Light background separates flat surfaces. Errors use semantic Material colors
plus explanatory text; tenant branding must not redefine status. Dark mode is
not currently implemented.

## Typography

Inter handles forms/body copy; Manrope handles headings and titles. Use the shared
TextTheme. Keep labels readable when names, template variables or Turkish copy wrap.
Font loading/offline packaging remains an operations follow-up.

## Layout

Campaign pages own a vertical ListView with 20 logical-pixel padding. Form groups
use 16px gaps and fields 12px. Send-value fields stay in one column at all widths;
action groups wrap. Dropdowns expand within available width and long selected
template names may ellipsize while the preview retains their full name.
Never place vertical Expanded children in an unbounded scroll view.

## Elevation & Depth

Cards and the app bar use no elevation; tonal surfaces organize sections.
Overlays and focus treatment remain Material-owned.

## Shapes

Existing theme radii are 18px cards, 14px controls, 20px chips. New fields inherit
them without screen-local copies. Icons use the existing Material set.

## Components

| Role | Runtime owner | Contract |
|---|---|---|
| Palette, type, shapes | `lib/features/app/app.dart` | canonical theme |
| Send values | `TemplateParameterFields` | shared between campaign create/edit |
| Input manifests | `_shared/template_parameters.ts` | server parses definitions |
| Select/field/form | Flutter Material widgets | labels, validation, focus |
| Notices | ScaffoldMessenger + inline form errors | confirmed success only |
| Support actions | ConversationWorkflowSheet | one shared bounded sheet for inbox and handoff |
| Handoff queue | HandoffScreen | wrapping filters/actions, dated records, 20-row pages |

Rendering, keyboard, zoom, contrast and mobile checks are deferred by the owner's
test schedule. Code review/static analysis is not visual verification. The wider
app has known responsive drift, including template creation forms. Campaign summary
cards were replaced with truthful audience text and wrapping progress chips; account,
filter and template controls stay within the existing Material form/card system.
Campaign history/failures use bounded pages in the owning page scroll, with wrapped
actions and explicit refresh. Runtime visual checks remain deferred.

## Do's and Don'ts

Use business labels and explain how to correct inputs. Preserve entered values on
recoverable errors. Keep validation next to the field and server failures visible.
Do not present provider acceptance as delivery or estimate counts as frozen totals.
