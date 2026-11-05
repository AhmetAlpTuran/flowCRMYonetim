-- Per-agent performance for the dashboard (administrators only, since it names people):
-- replies sent, first responses and their median time, resolved support episodes, and
-- conversations currently assigned. Same period rules as dashboard_metrics.

create index if not exists inbox_dispatches_tenant_actor_accepted on public.inbox_dispatches(tenant_id, actor_id, accepted_at)
  where source = 'human' and accepted_at is not null;

create function public.dashboard_agent_metrics(
  p_tenant_id uuid, p_days integer default 7, p_timezone text default 'Europe/Istanbul'
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare since timestamptz; today date; result jsonb;
begin
  if p_tenant_id is null or not public.is_tenant_admin(p_tenant_id) then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if p_days is null or p_days not between 1 and 90 then
    raise exception 'Period must be 1-90 days' using errcode = '22023';
  end if;
  if p_timezone is null or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Unknown time zone' using errcode = '22023';
  end if;
  today := (now() at time zone p_timezone)::date;
  since := ((today - (p_days - 1))::timestamp) at time zone p_timezone;

  select coalesce(jsonb_agg(row order by (row->>'replies')::int desc, row->>'name'), '[]'::jsonb) into result from (
    select jsonb_build_object(
      'user_id', m.user_id,
      'name', coalesce(nullif(btrim(p.display_name), ''), p.email, 'Kullanıcı'),
      'role', m.role,
      'replies', (select count(*) from public.inbox_dispatches d where d.tenant_id = p_tenant_id
        and d.source = 'human' and d.actor_id = m.user_id and d.accepted_at >= since),
      'first_responses', (select count(*) from public.support_episodes e where e.tenant_id = p_tenant_id
        and e.first_human_responder_id = m.user_id and e.opened_at >= since),
      'median_first_response_seconds', (select percentile_cont(0.5) within group (order by
          extract(epoch from (e.first_human_response_at - e.opened_at)))
        from public.support_episodes e where e.tenant_id = p_tenant_id and e.first_human_responder_id = m.user_id
          and e.opened_at >= since and e.opened_source <> 'legacy' and e.first_human_response_at is not null),
      'resolved', (select count(*) from public.support_episodes e where e.tenant_id = p_tenant_id
        and e.resolved_by = m.user_id and e.resolved_at >= since),
      'open_assigned', (select count(*) from public.conversations c where c.tenant_id = p_tenant_id
        and c.assigned_to = m.user_id and c.status in ('open', 'pending', 'handoff'))
    ) as row
    from public.tenant_memberships m
    left join public.user_profiles p on p.id = m.user_id
    where m.tenant_id = p_tenant_id
  ) rows;
  return jsonb_build_object('period_days', p_days, 'since', since, 'agents', result);
end;
$$;
revoke all on function public.dashboard_agent_metrics(uuid, integer, text) from public, anon;
grant execute on function public.dashboard_agent_metrics(uuid, integer, text) to authenticated;
