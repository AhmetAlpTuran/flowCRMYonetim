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
| Campaign save | campaign repository, moving to Riverpod controller in milestone 5 | await persisted result, prevent duplicate clicks |
| Server validation | shared template module + PostgreSQL audience function | authoritative even if client validation is bypassed |

Date pickers and bulk table selection are outside this change; no new implementations
are introduced. Existing template creation and campaign creation both remain inline
after save; campaign list/draft reopening is a required follow-up.

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
  Errors retain input. Unknown send results must direct users to campaign status;
  durable status/retry/reconciliation screens remain milestone 4/5 work.
- Required fields have labels and inline errors. Action rows wrap, dropdowns shrink
  safely, and form errors remain available without relying on a toast.
- Draft filter/parameter values are transient and may contain customer data; do not
  put them in URLs or browser storage. Persist only via an explicit draft save.

## Deferred verification and known drift

Widget regressions are authored in `test/widget_test.dart`; server cases are in
`supabase/functions/_shared/template_parameters_test.ts`. Suites have not been run.
Full-route focus/error scrolling, screen-reader announcements, 200% zoom, session
expiry, tenant switching during sends and deployed-function failure cases require
the deferred verification phase. Dispatch now queues asynchronously and the submit
notice reports queued recipients, never a fabricated zero-success completion.
Stable client campaign identity across retries, history/progress, cross-screen error
handling and controller ownership remain open; they are not approved exceptions.
