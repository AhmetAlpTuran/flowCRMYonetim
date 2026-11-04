# Catalog, bookings and leads (roadmap Phase 2b)

Updated 2026-11-07. Backend implemented and verified locally
(`20261107090000_catalog_bookings_leads.sql`, `supabase/tests/catalog_bookings.sql`).
The "Katalog" screen is implemented; the bot tools that call the bot functions are next.

## Model

- **`resource_types`** — per business: `key` (e.g. `room`, `vehicle`), name, `kind`
  (`bookable` with a `booking_unit` of night/day/hour, or `listing`), and `fields`
  (`[{key, label, type: text|number|select|boolean, options?, filterable?}]`, max 30,
  validated by `valid_resource_fields`).
- **`resources`** — items of a type with `attributes` checked against the type's fields
  by a trigger (unknown keys, wrong types and unknown select options are rejected), price
  and currency, capacity, status (`active`, `inactive`, `reserved`, `sold`), up to 10
  photo paths, and nullable `external_source`/`external_id`/`external_synced_at` for a
  future sheet sync.
- **`bookings`** — `period` is a half-open `tstzrange` (`[start, end)`, so back-to-back
  stays are allowed), status `hold`/`confirmed`/`cancelled`, `hold_expires_at`, customer
  name/phone, optional conversation, `source` (`agent`, `bot`, `import`) and an optional
  `request_key` for idempotent retries. **`bookings_no_overlap`** (a GiST exclusion
  constraint over resource and period for every non-cancelled booking) makes overlapping
  bookings impossible, including under concurrency. Expired holds are cancelled before
  every availability decision and can no longer be confirmed.
- **`leads`** — `inquiry`, `test_drive`, `trade_in`, `financing`, `booking_request`,
  `other`; details JSON, preferred time, status `new`/`contacted`/`won`/`lost`.

Module permission `catalog` (added to every business and to admins). Catalog members
read and write types, resources and leads directly under RLS; bookings are read directly
but written only through functions.

## Functions

Agent-facing (catalog permission): `create_booking(...)` (confirmed, phone normalized,
idempotent with `p_request_key`), `set_booking_status(tenant, booking, confirmed|cancelled)`.

Bot-facing (service role only; the customer's phone always comes from the conversation,
never from model output):

| Function | Purpose |
|---|---|
| `bot_search_resources(tenant, type_key, query, filters, limit)` | Active items; filters `{"field": value}` or `{"field": {"min","max"}}`, plus `price` |
| `bot_check_availability(tenant, resource, start, end)` | `available` plus busy periods ±7 days |
| `bot_create_booking_hold(tenant, conversation, resource, start, end, name, request_key, hold_minutes)` | Hold (default 15 min), idempotent per request key and bound to the conversation |
| `bot_set_booking_status(tenant, conversation, booking, confirmed\|cancelled)` | Only for bookings of that conversation; expired holds fail with `P0016` |
| `bot_create_lead(tenant, conversation, kind, resource, details, preferred_at, name, request_key)` | Idempotent lead |

Errors: `P0015` overlap, `P0016` hold expired or cancelled, `P0002` not found, `22023`
invalid input, `42501` permission.

Customers confirm a bot hold by tapping the "Onayla" WhatsApp button the bot attaches to
the hold message, or "İptal" to release it (see `docs/AI_WORKER.md`, Booking confirm buttons).

## Verified

Fixture covers field/attribute validation, search filters, tenant isolation, hold
idempotency and conversation binding, overlap refusal with adjacency allowed, expired
holds, cross-conversation confirmation refusal, leads, direct-write revocation and
permission checks. A live race of two concurrent sessions booking the same nights,
repeated five times, left exactly one booking.

## App ("Katalog", `lib/features/catalog`)

- **Kayıtlar:** start from a preset type (Oda — nightly, Araç — listing, Hizmet — hourly),
  add/edit/delete items with inputs generated from the type's fields, price, capacity,
  status and a description the bot will use.
- **Rezervasyonlar:** upcoming bookings with live/expired hold state, confirm and cancel,
  and agent bookings for phone or walk-in customers (nightly stays 14:00 check-in to 11:00
  check-out, hourly slots with a start time and duration). Overlaps show a clear error.
- **Talepler:** leads with kind, customer, item, preferred time and a status selector.
- Visible to members with the `catalog` permission ("Katalog ve rezervasyon" in Users).

## Industry packs (roadmap Phase 2c, `20261107110000_industry_packs.sql`)

`apply_industry_pack(tenant, pack, answers)` (admins only) sets a business up in one step:

| Pack | Catalog type | Questions turned into knowledge entries |
|---|---|---|
| `rental` — Konaklama ve kiralama | Oda (nightly) | check-in/out times, address, payment and deposit, cancellation, amenities and rules |
| `auto_dealer` — Oto galeri | Araç (listing) | address and hours, test drive, financing, trade-in, inspection and warranty |
| `appointments` — Randevulu hizmet | Hizmet (hourly) | address and hours, services and prices, cancellation, preparation |

- Pack definitions (types, tone, a Turkish bot prompt per sector) live in
  `industry_pack_definition`; the app reads names and questions from `industry_packs()`.
- Only non-empty answers become knowledge entries (tagged `paket:<pack>`), so the bot never
  quotes placeholder text; re-applying updates those entries instead of duplicating them.
- The pack prompt replaces only the default prompt or another pack's prompt; a custom
  prompt is kept. The bot is never switched on by a pack.
- App: "Sektör paketi kur" in the empty Katalog screen and at the top of the Bot screen
  (administrators only), with example answers for every question.
