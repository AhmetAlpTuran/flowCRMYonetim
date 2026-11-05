-- Operations health (roadmap Phase 4): one service-only report of every background
-- queue, for the `health` Edge Function and any uptime monitor polling it.
-- "Stuck" = still waiting well past the time its worker should have taken it (workers
-- run every 30-60 seconds); "failed" = ended badly in the last 24 hours.

create function public.ops_health()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare report jsonb; problems text[] := array[]::text[];
  day_ago timestamptz := now() - interval '24 hours';
begin
  perform public.require_service_role();
  report := jsonb_build_object(
    'webhook_events', (select jsonb_build_object(
      'pending', count(*) filter (where state = 'pending'),
      'stuck', count(*) filter (where state = 'pending' and available_at < now() - interval '10 minutes'),
      'failed_24h', count(*) filter (where state = 'error' and received_at > day_ago))
      from public.whatsapp_webhook_events where state in ('pending', 'error')),
    'inbox_dispatches', (select jsonb_build_object(
      'waiting', count(*) filter (where state in ('queued', 'retry_wait', 'blocked', 'leased', 'sending')),
      'stuck', count(*) filter (where state in ('queued', 'retry_wait') and available_at < now() - interval '10 minutes'),
      'unknown', count(*) filter (where state = 'unknown'),
      'failed_24h', count(*) filter (where state = 'failed' and updated_at > day_ago))
      from public.inbox_dispatches where state not in ('accepted', 'cancelled')),
    'campaign_dispatches', (select jsonb_build_object(
      'waiting', count(*) filter (where state in ('queued', 'retry_wait', 'blocked', 'leased', 'sending')),
      'stuck', count(*) filter (where state in ('queued', 'retry_wait') and available_at < now() - interval '30 minutes'),
      'unknown', count(*) filter (where state = 'unknown'),
      'failed_24h', count(*) filter (where state = 'failed' and updated_at > day_ago))
      from public.campaign_dispatches where state not in ('accepted', 'cancelled')),
    'bot_jobs', (select jsonb_build_object(
      'waiting', count(*) filter (where state in ('queued', 'leased')),
      'stuck', count(*) filter (where state = 'queued' and available_at < now() - interval '10 minutes'),
      'failed_24h', count(*) filter (where state = 'failed' and updated_at > day_ago))
      from public.bot_reply_jobs where state in ('queued', 'leased', 'failed')),
    'ai_reservations', (select jsonb_build_object(
      'unknown', count(*) filter (where status = 'unknown'),
      'stale', count(*) filter (where status = 'reserved' and created_at < now() - interval '30 minutes'))
      from public.ai_usage_reservations where status in ('reserved', 'unknown')),
    'media_downloads', (select jsonb_build_object(
      'waiting', count(*) filter (where state in ('queued', 'leased')),
      'stuck', count(*) filter (where state = 'queued' and available_at < now() - interval '15 minutes'),
      'failed_24h', count(*) filter (where state = 'failed' and updated_at > day_ago))
      from public.message_media where direction = 'inbound' and state in ('queued', 'leased', 'failed')),
    'knowledge_documents', (select jsonb_build_object(
      'waiting', count(*) filter (where state in ('queued', 'leased')),
      'stuck', count(*) filter (where state = 'queued' and available_at < now() - interval '30 minutes'),
      'failed_24h', count(*) filter (where state = 'failed' and updated_at > day_ago))
      from public.knowledge_documents where state in ('queued', 'leased', 'failed')),
    'billing', jsonb_build_object(
      'unmatched_events_7d', (select count(*) from public.billing_events
        where not applied and received_at > now() - interval '7 days'))
  );
  -- Anything stuck, or results nobody can confirm, needs a person.
  if (report->'webhook_events'->>'stuck')::int > 0 then problems := array_append(problems, 'webhook_events_stuck'); end if;
  if (report->'inbox_dispatches'->>'stuck')::int > 0 then problems := array_append(problems, 'inbox_dispatches_stuck'); end if;
  if (report->'inbox_dispatches'->>'unknown')::int > 0 then problems := array_append(problems, 'inbox_outcome_unknown'); end if;
  if (report->'campaign_dispatches'->>'stuck')::int > 0 then problems := array_append(problems, 'campaign_dispatches_stuck'); end if;
  if (report->'campaign_dispatches'->>'unknown')::int > 0 then problems := array_append(problems, 'campaign_outcome_unknown'); end if;
  if (report->'bot_jobs'->>'stuck')::int > 0 then problems := array_append(problems, 'bot_jobs_stuck'); end if;
  if (report->'ai_reservations'->>'stale')::int > 0 then problems := array_append(problems, 'ai_reservations_stale'); end if;
  if (report->'media_downloads'->>'stuck')::int > 0 then problems := array_append(problems, 'media_downloads_stuck'); end if;
  if (report->'knowledge_documents'->>'stuck')::int > 0 then problems := array_append(problems, 'knowledge_documents_stuck'); end if;
  if (report->'billing'->>'unmatched_events_7d')::int > 0 then problems := array_append(problems, 'billing_events_unmatched'); end if;
  return report || jsonb_build_object('healthy', cardinality(problems) = 0, 'problems', to_jsonb(problems),
    'checked_at', now());
end;
$$;
revoke all on function public.ops_health() from public, anon, authenticated;
grant execute on function public.ops_health() to service_role;
