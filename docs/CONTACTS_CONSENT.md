# Contacts and marketing consent

Updated 2026-11-05. Implemented and verified against the local Supabase stack.

## Model

- `contacts` is the CRM list used by the inbox (inbox permission). Customers who write
  on WhatsApp are added automatically; users add or import more. Numbers are stored as
  E.164 digits without `+` (the WhatsApp `wa_id` form) and deduplicated per tenant.
- `consented_contacts` is the campaign audience (campaigns permission). A row records
  `consent_source` (`manual`, `import`, `form`, `whatsapp`, `legacy` for rows that existed
  before this change), `consent_note` (how consent was obtained), `consented_by` and
  `consented_at`. An opt-out sets `opted_out_at`/`opt_out_source` and keeps the row as
  evidence.
- Opted-out numbers are excluded by `campaign_audience` (preview, count and enqueue) and
  by `start_campaign_dispatch`, so a dispatch queued before the opt-out is cancelled with
  `consent_unavailable` instead of being sent.
- Clients can no longer write `consented_contacts` directly. CRM edits of name, email
  and tags are copied into the audience by a trigger, so tag segments follow the CRM.

## RPCs (`20261105100000_contacts_consent.sql`)

- `upsert_contact(tenant, name, phone, email, tags)` — inbox permission; one contact per number.
- `list_contacts(tenant, search, limit, offset)` — search by name, digits or exact tag;
  consent fields are returned only to callers with the campaigns permission.
- `set_marketing_consent(tenant, phone, consent, note, source)` — campaigns permission;
  granting requires a 3-500 character basis note; changes are audited with only the last
  four digits of the number.
- `import_contacts(tenant, rows, consent_note)` — up to 1000 rows per call (the app sends
  5000-row files in chunks); rows marked `consent: true` need the campaigns permission and
  a shared basis note; numbers that opted out are never re-subscribed by an import
  (`opted_out`); invalid numbers and rows are reported back by row.

## App

The "Kişiler" screen (`lib/features/contacts`) lists, searches and edits contacts,
records or revokes consent with its basis, and imports CSV files exported from Excel or
Google Sheets: comma, semicolon or tab separators, UTF-8 or Windows-1254, Turkish or
English headers (`Ad Soyad`, `Telefon`, `E-posta`, `Etiketler`, `İzin`), local Turkish
numbers such as `0555 111 22 33`. Importing consent requires a basis and an explicit
confirmation that consent was obtained.

## Opt-out by WhatsApp keyword (`20261110090000_keyword_opt_out.sql`)

A customer text matching `is_marketing_stop` opts the number out of that business's
marketing. The rule applies with or without Turkish letters and with any capitalization:

- **Stop word first:** `STOP`, `RET` or `unsubscribe`, at most three words in total (for
  example "RET MARKA").
- **Refusal phrase:** a short message containing a phrase such as "abonelikten çık",
  "listeden çıkarın", "mesaj göndermeyin" or "reklam/kampanya istemiyorum".

A bare "iptal" is **not** a stop word, because customers use it for bookings and booking
buttons.

- The trigger on `messages` sets `opted_out_at` and `opt_out_source = 'whatsapp_keyword'` on
  every consent row of that number, whatever its stored format. A number without a row gets a
  refusal row, so a later import cannot subscribe it.
- The opt-out is audited (`contact.opted_out`). Queued campaign dispatches to the number are
  cancelled at send time.
- The bot job for that message is cancelled (`marketing_opt_out`); an agent sees the message
  in the inbox. No automatic confirmation is sent.
- Re-subscribing requires a recorded consent (`set_marketing_consent`), never a keyword.
- Verified by SQL fixture `keyword_opt_out.sql`: 13 stop phrases, 10 look-alikes (booking
  "iptal", "stop lambası", …), format-independent matching, tenant isolation, the refusal
  row, the audience, bot skipping, and agent messages.

## Not yet

- `.xlsx` files: save as CSV first.
- Whether İYS registration applies to WhatsApp messages needs legal confirmation (roadmap
  Phase 4); the recorded source, basis, actor and time are kept to support that.
