# Flow CRM interaction contract

Scope: incremental production contract for the existing Flutter product.
Visual ownership is in [DESIGN.md](DESIGN.md). Business scope and unfinished work
are in [DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md). This document states the target
contract; a documented legacy gap is not evidence of completion.

## Canonical UI ownership

| Capability | Owner | Variants / evidence |
|---|---|---|
| Select | Material DropdownButtonFormField | expanded within bounded width; default keyboard/popup behavior |
| Form | Material Form/TextFormField | create/edit; TemplateParameterFields adapts the server manifest |
| Scroll | owning ListView/SingleChildScrollView | no unbounded Expanded on scroll axis |
| Feedback | ScaffoldMessenger for confirmation, inline errors for correction | Turkish copy; no raw backend diagnostics |
| Campaign save | CampaignActions Riverpod controller + versioned repository RPC | stable ID, immutable retry snapshot, conflict recovery |
| Campaign history/results | CampaignHistory / CampaignProgressPanel | 20-row pages, explicit refresh, acceptance separate from delivery |
| Inbox handoff | HandoffRequestSheet + SupabaseInboxRepository + atomic RPC | stable request ID, immutable retry note, tenant-change guard |
| Inbox send | InboxSendController + repository + enqueue RPC | stable message ID, immutable uncertain retry, authoritative dispatch state |
| Delivery display | MessageDeliveryStatus | queue, acceptance, delivery, read and uncertainty are distinct |
| Server validation | shared template module + PostgreSQL audience function | authoritative even if client validation is bypassed |

Date pickers and bulk table selection are outside this change; no new implementations
are introduced. Existing template creation and campaign creation both remain inline
after save. Campaign history below the form supports draft reopening and result review.

## Campaign form behavior

- Tenant or template change invalidates old requests and clears old send values.
  Template input loading, error and ready states are separate from audience preview.
- Input manifests load before sending or saving a new draft. Unknown/unsupported
  definitions block submission; Retry reloads the manifest.
- Drafts may contain unfinished values. Send validates required fields first;
  the server revalidates against the selected approved template and each contact.
- Missing contact fields use an explicit optional fallback. No value and no fallback
  records a recipient validation failure; no accidental blank message is sent.
- Media send values are an HTTPS link or WhatsApp media ID, separate from the
  resumable-upload handle used as a creation example.
- Controls disable during a mutation. Confirmed persistence earns a saved notice.
  Errors retain input. Unknown request results freeze the exact pending draft and
  expose a same-ID retry. Confirmed saved drafts are not saved again on enqueue retry.
  Version conflicts require reopening history; no automatic overwrite or new ID.
  Sending asks for confirmation of the account and template before queueing.
- Required fields have labels and inline errors. Action rows wrap, dropdowns shrink
  safely, and form errors remain available without relying on a toast.
- Draft filter/parameter values are transient and may contain customer data; do not
  put them in URLs or browser storage. Persist only via an explicit draft save.

## Deferred verification and known drift

Opening bot settings reads existing configuration or presents an inactive draft.
Activation requires an explicit save. Existing saved activation is preserved.
The worker/usage integration and its operational UI remain in progress.

Inbox text replies use the scoped Supabase queue. The composer freezes during a
pending or uncertain enqueue and retains its original text/ID for retries. Confirmed
persistence clears the composer and reloads messages. A window or permission rejection
shows localized correction guidance. Pending, accepted and delivered labels reflect
their separate backend states. Back navigation guards an unsaved draft or uncertain
request. A changed session/business invalidates the chat and requires reopening it.
These behaviors have authored controller/status fixtures in `test/inbox_send_test.dart`.
Runtime interaction and browser reload recovery remain deferred. Attachments remain
disabled pending their scoped upload/send implementation.

Inbox handoff preserves the existing requirement for both inbox and handoff
permissions. The Material bottom sheet wraps actions, owns its scroll area, accounts
for the keyboard and retains the submitted note on uncertain results. Duplicate
clicks are blocked while busy. Retrying reuses the same request ID and note.
Confirmed success closes the sheet and refreshes both the inbox and handoff list.
Conflicts and permission changes leave an inline message with recovery guidance.
Changing businesses disables submission from the old sheet. Tests for these states
are authored in `test/inbox_lifecycle_test.dart`, with execution deferred.

Opening a chat records one shared-inbox opened marker through a server-authorized
RPC. The server records the employee and time and resets the shared unread count at
the conversation lock boundary. Per-agent unread cursors and viewport-level message
read acknowledgement remain future work. This marker does not send a WhatsApp read
receipt. Failed persistence offers a retry without inventing a successful marker.

Widget regressions are authored in `test/widget_test.dart`; server cases are in
`supabase/functions/_shared/template_parameters_test.ts`. Suites have not been run.
Full-route focus/error scrolling, screen-reader announcements, 200% zoom, session
expiry, tenant switching during sends and deployed-function failure cases require
the deferred verification phase. Dispatch now queues asynchronously and the submit
notice reports queued recipients, never a fabricated zero-success completion.
Stable campaign identity, versioned drafts, Riverpod ownership and paginated history/
progress are now implemented. Default filter labels describe actual tags/recency;
there are no purchase-count or campaign-response claims backed only by tags.
Progress/failure panels refresh explicitly and do not imply live push updates.
Unsaved form values remain in memory only; leaving the entire campaign tab or
reloading can discard them. Global unsaved-navigation protection, refreshed-template
preview confirmation and cross-screen errors remain
open. These are not approved release exceptions.
