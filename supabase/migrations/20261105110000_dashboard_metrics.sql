-- Tenant dashboard metrics. Aggregates only (no message content or identities), so
-- it runs as definer behind an explicit dashboard-permission check, which lets a
-- dashboard-only member see totals without inbox/campaign row access.

create index if not exists messages_tenant_sent_at on public.messages(tenant_id, sent_at);
create index if not exists inbox_dispatches_tenant_accepted on public.inbox_dispatches(tenant_id, accepted_at)
  where accepted_at is not null;
create index if not exists campaign_dispatches_tenant_accepted on public.campaign_dispatches(tenant_id, accepted_at)
  where accepted_at is not null;
create index if not exists support_episodes_tenant_opened on public.support_episodes(tenant_id, opened_at);
create index if not exists handoff_requests_tenant_created on public.handoff_requests(tenant_id, created_at);

create or replace function public.dashboard_metrics(
  p_tenant_id uuid, p_days integer default 7, p_timezone text default 'Europe/Istanbul'
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  since timestamptz;
  today date;
  result jsonb;
begin
  if not coalesce(public.user_has_permission(p_tenant_id, 'dashboard'), false) then
    raise exception 'Dashboard permission required' using errcode = '42501';
  end if;
  if p_days is null or p_days not between 1 and 90 then
    raise exception 'Period must be 1-90 days' using errcode = '22023';
  end if;
  if p_timezone is null or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Unknown time zone' using errcode = '22023';
  end if;
  -- The period covers whole local days: today plus the previous p_days - 1 days.
  today := (now() at time zone p_timezone)::date;
  since := ((today - (p_days - 1))::timestamp) at time zone p_timezone;

  select jsonb_build_object(
    'period_days', p_days,
    'since', since,
    'generated_at', now(),
    'conversations', (
      select jsonb_build_object(
        'open', count(*) filter (where status = 'open'),
        'pending', count(*) filter (where status = 'pending'),
        'handoff', count(*) filter (where status = 'handoff'),
        'unassigned_waiting', count(*) filter (where status in ('open', 'pending', 'handoff') and assigned_to is null),
        'started', count(*) filter (where created_at >= since))
      from public.conversations where tenant_id = p_tenant_id),
    'messages', jsonb_build_object(
      'inbound', (select count(*) from public.messages
        where tenant_id = p_tenant_id and is_from_customer and sent_at >= since),
      'human_replies', (select count(*) from public.inbox_dispatches
        where tenant_id = p_tenant_id and accepted_at >= since and source = 'human'),
      'bot_replies', (select count(*) from public.inbox_dispatches
        where tenant_id = p_tenant_id and accepted_at >= since and source = 'bot'),
      'failed_replies', (select count(*) from public.inbox_dispatches
        where tenant_id = p_tenant_id and created_at >= since and state = 'failed')),
    'support', (
      select jsonb_build_object(
        'opened', count(*),
        'resolved', count(*) filter (where resolved_at is not null),
        'resolved_by_automation', count(*) filter (where resolution_kind = 'automation'),
        'median_first_response_seconds', percentile_cont(0.5) within group (order by
          extract(epoch from (least(first_human_response_at, first_bot_response_at) - opened_at)))
          filter (where least(first_human_response_at, first_bot_response_at) is not null and opened_source <> 'legacy'),
        'median_first_human_response_seconds', percentile_cont(0.5) within group (order by
          extract(epoch from (first_human_response_at - opened_at)))
          filter (where first_human_response_at is not null and opened_source <> 'legacy'),
        'median_resolution_seconds', percentile_cont(0.5) within group (order by
          extract(epoch from (resolved_at - opened_at)))
          filter (where resolved_at is not null and opened_source <> 'legacy'))
      from public.support_episodes where tenant_id = p_tenant_id and opened_at >= since),
    'handoffs', (select count(*) from public.handoff_requests
      where tenant_id = p_tenant_id and created_at >= since),
    'campaigns', (
      select jsonb_build_object(
        'accepted', count(*),
        'delivered', count(*) filter (where delivery_status in ('delivered', 'read') or delivered_at is not null),
        'read', count(*) filter (where delivery_status = 'read' or read_at is not null),
        'failed', count(*) filter (where delivery_status = 'failed'))
      from public.campaign_dispatches where tenant_id = p_tenant_id and accepted_at >= since),
    'daily', (
      select coalesce(jsonb_agg(jsonb_build_object('day', d.day::date, 'inbound', coalesce(i.n, 0), 'replies', coalesce(o.n, 0))
        order by d.day), '[]'::jsonb)
      from generate_series(today - (p_days - 1), today, interval '1 day') as d(day)
      left join (
        select (sent_at at time zone p_timezone)::date as day, count(*) as n from public.messages
        where tenant_id = p_tenant_id and is_from_customer and sent_at >= since group by 1
      ) i on i.day = d.day::date
      left join (
        select (accepted_at at time zone p_timezone)::date as day, count(*) as n from public.inbox_dispatches
        where tenant_id = p_tenant_id and accepted_at >= since and source in ('human', 'bot') group by 1
      ) o on o.day = d.day::date)
  ) into result;
  return result;
end;
$$;
revoke all on function public.dashboard_metrics(uuid, integer, text) from public, anon;
grant execute on function public.dashboard_metrics(uuid, integer, text) to authenticated;
