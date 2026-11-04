# Support ownership and case timing

Updated 2026-11-04. Backend actions and Flutter entry points are implemented in
source. Deploy the migration, updated send endpoint and matching client together.
Fixtures are authored and unexecuted. Static checks do not verify database
execution, browser behavior or concurrency.

## Ownership protocol

`apply_conversation_action` takes tenant, conversation, stable request UUID,
expected workflow revision, action and optional assignee. Supported actions are
`claim`, `assign`, `release`, `resolve` and `reopen`. Only `assign` takes an assignee.
The conversation row serializes actions, incoming inputs, human enqueue and send
authorization. The revision changes on assignment, status or actionable input.
An action commits its audit record and private request/result ledger atomically.
An identical retry returns the recorded result even after later conversation
changes. The client must refresh authoritative state after success rather than
replace current state with that potentially historical result.

An inbox employee can claim unassigned work and manage their own conversations.
An administrator can override ownership and assign eligible inbox members.
`conversation_team` exposes only member IDs and bounded display names from the
requested tenant. Missing names receive a short member-ID label. Cross-tenant
requests and direct client writes to assignment, case timing and the action ledger
are denied. Membership deletion clears assignment while preserving case history.

Human enqueue claims unassigned conversations and advances active handoff requests
to `in_progress`. All employees, including administrators, must take ownership
before replying to another employee's conversation. A closed conversation requires
an explicit reopen. Existing stable message IDs retain replay behavior after these
state changes. The send endpoint maps these rejections to actionable client errors.

Ownership changes and resolution are blocked while a human message is queued,
leased, sending, waiting for retry or blocked by connection health. The employee
can wait or use `cancel_inbox_message` for their own unstarted work. Administrators
can cancel any unstarted human message in their tenant. Cancellation locks the
conversation and dispatch, clears its lease, publishes message state and audits
the change. Repeated cancellation succeeds. Sending, accepted, failed and unknown
outcomes cannot be recalled through this operation. Unknown sends remain visible
and can receive late acknowledgements after a case closes.

Every human lifecycle action cancels queued bot generation and unstarted bot
transport. Already-started external sends may finish. Existing ownership/context
fences protect subsequent bot finalization. Releasing an employee-owned conversation
keeps it under human control and creates or reopens an outstanding handoff task.
Resolution completes outstanding handoff tasks. Manual reopen starts a new case
assigned to the caller. A new actionable customer message after closure opens an
unassigned case eligible for normal automation. Reactions and older inputs preserve
the current actionable pointer and do not reopen a closed conversation.

## Support episode metrics

`support_episodes` preserves each case independently. Only one episode per
conversation can remain unresolved. Incoming actionable messages bind the case
before bot input tracking. Manual work creates a case if one is missing. Existing
active conversations receive a legacy episode with an unknown opening time.
Historical messages remain unassigned to cases because their case boundaries
cannot be inferred reliably.

Messages retain their original episode ID. Provider acceptance of a human or bot
reply updates that episode's first response timestamp, including a late acceptance
after resolution or another reopening. Bot handoff notices are excluded. These
timestamps measure **API acceptance**, and analytics must label that distinction.
Delivery/read states remain separately available. Unknown legacy starts must be
excluded from elapsed-duration averages and reported as missing history. A late
acceptance can occur after resolution, which is valid evidence of delayed sending.

## Flutter workflow

The chat toolbar and handoff list open the same `ConversationWorkflowSheet`.
It loads the current conversation and tenant team through `SupabaseInboxRepository`.
`ConversationWorkflowController` owns the action UUID, revision and assignee.
Uncertain results freeze the original request for explicit retry, even when a
later attempt receives a permission error. Confirmed responses trigger fresh
reads instead of applying the historical replay result to current UI state.
Tenant/session changes invalidate the sheet, and late completions cannot navigate
or refresh a different business. Closing during an uncertain result explains that
the action may have committed. Retry identity persists while the panel is open.
Browser reload recovery remains a broader application follow-up.

The handoff list has status filters, deterministic 20-row pages, a one-row sentinel
for Next, explicit refresh, empty/error states and links into the chat. Filter and
confirmed workflow changes reset paging. List state stays in tenant/user-scoped
memory under the existing Flutter navigation architecture. Pages use offset
pagination and can shift as other employees change the queue, so refresh returns
to the first page. Message cancellation appears on eligible human messages and
requires confirmation. A worker-start race produces a localized correction message.

The existing Material theme, scroll containers and expanding dropdown own the
new controls. Tag editing and requesting handoff moved into the chat's overflow
menu to leave room for management and refresh actions on narrow screens. These
layout changes still need browser/keyboard verification.

## Deferred verification

Run `supabase/tests/support_workflows.sql` only in an isolated fully migrated
database when the owner starts the testing phase. It covers permission boundaries,
stable action replay, stale revisions, competing employees, pending human sends,
cancel restrictions, prepared bot cancellation, manual/customer reopen and late
acceptance attribution. Controller rejection cases are in `test/inbox_send_test.dart`.
`test/conversation_workflow_test.dart` adds repository scoping/paging, immutable
retries, revision conflicts, duplicate clicks, narrow layout, tenant changes,
modal completion, disappearing team options and cancellation race cases.

Also verify with separate concurrent sessions and the real Flutter entry points.

- Two employees claim the same revision. Exactly one claim commits.
- Repeat the same request while its first transaction is uncommitted. Verify one
  audit entry and one ledger result. Reusing the UUID on another conversation must
  roll back the competing transaction completely.
- Race cancellation against worker start. Either cancellation prevents dispatch,
  or start wins and cancellation is rejected. Verify no cleared sending fence.
- Race resolve/reassign against enqueue and provider completion. Confirm pending
  human work is preserved and accepted messages retain the original episode.
- Race membership removal or permission revocation against assignment/send.
  Verify FK behavior, rollback/retry handling and the dispatch permission check.
- Upgrade historical open/closed conversations and queued messages. Verify unknown
  timing remains unknown, channel mapping remains explicit and old fixtures still
  pass under the complete migration sequence.
- Verify uncertain client retries, refreshed revisions, tenant changes, narrow
  layouts, keyboard navigation and accessible loading/error states after UI wiring.
