# Operations: deploy, schedules, monitoring, backups (roadmap Phase 4)

This is the runbook for a hosted Supabase project (staging first, then production). Every
step here is done by the owner; nothing in the app provisions paid resources.

## 1. Deploy order

1. **Database.** `supabase link --project-ref <ref>`, then `supabase db push`. Migrations
   are additive; never reset a hosted database.
2. **Secrets.** Copy `supabase/functions/.env.example`, fill every value, then run
   `supabase secrets set --env-file <file>`. Use fresh values: the keys exposed during
   earlier debugging must be rotated first.
3. **Functions.** `supabase functions deploy` (all functions). `supabase/config.toml`
   marks the public and worker endpoints that verify their own secrets
   (`verify_jwt = false`).
4. **Vault and schedules** (SQL editor):
   1. Store `project_url` (`https://<ref>.supabase.co`) and each worker secret in Vault
      under the names below.
   2. Run each `supabase/ops/schedule_*.sql` once.
5. **External settings.**
   - Meta webhook URL: `…/functions/v1/whatsapp-webhook`.
   - iyzico notification URL: `…/functions/v1/iyzico-gateway/webhook`.
   - GitHub Pages for `docs/` (privacy policy and payment page). See `docs/BILLING.md`
     and `docs/RELEASE.md`.

| Worker | Interval | Secret (Edge env) | Vault name | Script |
|---|---|---|---|---|
| `webhook-worker` | 10 s | `WEBHOOK_WORKER_SECRET` | `webhook_worker_secret` | `schedule_webhook_worker.sql` |
| `inbox-worker` | 10 s | `INBOX_WORKER_SECRET` | `inbox_worker_secret` | `schedule_inbox_worker.sql` |
| `bot-worker` | 10 s | `BOT_WORKER_SECRET` | `bot_worker_secret` | `schedule_bot_worker.sql` |
| `campaign-worker` | 10 s | `CAMPAIGN_WORKER_SECRET` | `campaign_worker_secret` | `schedule_campaign_worker.sql` |
| `media-worker` | 30 s | `MEDIA_WORKER_SECRET` | `media_worker_secret` | `schedule_media_worker.sql` |
| `knowledge-worker` | 1 min | `KNOWLEDGE_WORKER_SECRET` | `knowledge_worker_secret` | `schedule_knowledge_worker.sql` |

Check the schedules: `select jobname, schedule, active from cron.job;` and the latest runs:
`select * from cron.job_run_details order by start_time desc limit 20;`.

## 2. Health monitoring

`ops_health()` (service only) reports every background queue, and the `health` Edge
Function serves it:

```
GET https://<ref>.supabase.co/functions/v1/health
Authorization: Bearer <HEALTH_CHECK_SECRET>
```

It answers **200** when healthy and **503** with `problems` otherwise. Point any uptime
monitor at it every 5 minutes with that header, and alert on anything but 200. Examples:
Better Stack, UptimeRobot (custom HTTP headers), cron-job.org. Keep the secret out of the
monitor's public status page.

| Problem | Meaning | What to do |
|---|---|---|
| `webhook_events_stuck` | Meta events waiting > 10 min | Check `webhook-worker` schedule and logs |
| `inbox_dispatches_stuck` / `campaign_dispatches_stuck` | Sends waiting past their time | Check the worker schedule, the connection token (status `needs_attention`) and Meta status |
| `inbox_outcome_unknown` / `campaign_outcome_unknown` | A send may or may not have reached WhatsApp | Never resend blindly. Check the conversation (and Meta delivery receipts), then resolve it by hand |
| `bot_jobs_stuck` | Bot replies not being picked up | Check `bot-worker` (`configuration_ready` in its response, OpenAI key and limits) |
| `ai_reservations_stale` | AI calls whose usage was never settled | Usually a crashed bot run; `mark_stale_ai_reservations` runs every bot cycle |
| `media_downloads_stuck` | Customer photos/files not downloaded | Check `media-worker` and the connection token |
| `knowledge_documents_stuck` | Uploaded documents not processed | Check `knowledge-worker`; large PDFs may exceed the Edge CPU limit |
| `billing_events_unmatched` | An iyzico webhook for an unknown subscription (7 days) | Look it up in `billing_events` and in the iyzico panel |

Edge Function logs (Supabase dashboard → Edge Functions → Logs) contain only a request ID
and an error code, never message bodies, tokens or provider payloads. Match the
`request_id` a user reports.

## 3. Backups and restore

- **Production needs Supabase Pro.** It includes daily backups; the point-in-time recovery
  add-on gives minute-level restores.
- **Storage objects are not part of database backups.** These are the `inbox-media`,
  `knowledge-documents` and `catalog-photos` buckets. Export them periodically, or accept
  that the loss of media only affects old attachments.
- **Restore drill**, at least once before launch and then every quarter:
  1. Restore the latest backup into a new project.
  2. Point a staging build of the app at it.
  3. Sign in, open the inbox and a few conversations, check the bot settings and catalog.
  4. Record the time it took.

## 4. Error tracking (optional, owner account)

The app and functions do not send error reports to a third party yet. Sentry, for
example, would need:
- a project and DSN
- a KVKK review (no message content may be sent)
- a disclosure in the privacy policy

Until then, use the Edge Function logs and the health endpoint.

## Verified

- SQL fixture `ops_health.sql`: empty queues are healthy; a reply stuck for 20 minutes and
  an unmatched billing event are reported; clients cannot read the report.
- The `health` function on the local Edge runtime: 401 without the secret; 200 and healthy
  over GET and POST.
