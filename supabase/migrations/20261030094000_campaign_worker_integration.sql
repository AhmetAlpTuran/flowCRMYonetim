-- Bind queue snapshots to one immutable tenant connection and distinguish
-- configuration-blocked work from external attempts and unknown outcomes.
alter table public.campaign_dispatches drop constraint campaign_dispatches_state_check;
alter table public.campaign_dispatches add constraint campaign_dispatches_state_check
  check (state in ('queued', 'leased', 'sending', 'retry_wait', 'blocked', 'accepted', 'failed', 'unknown', 'cancelled'));
drop index public.campaign_dispatch_ready;
create index campaign_dispatch_ready on public.campaign_dispatches (available_at, id)
  where state in ('queued', 'retry_wait', 'blocked');

create or replace function public.enqueue_campaign(p_campaign_id uuid, p_actor_id uuid, p_expected jsonb)
returns integer language plpgsql security invoker set search_path = '' as $$
declare c public.campaigns; t public.templates; w public.whatsapp_connections; actual jsonb; recipients integer;
begin
  perform public.require_service_role();
  select * into c from public.campaigns where id = p_campaign_id for update;
  if not found then raise exception 'Campaign not found' using errcode = 'P0002'; end if;
  if p_actor_id is null or not exists (select 1 from public.tenant_memberships m
    where m.tenant_id = c.tenant_id and m.user_id = p_actor_id
      and (m.role = 'admin' or 'campaigns' = any(m.permissions))) then
    raise exception 'Campaign permission required' using errcode = '42501';
  end if;
  if c.queued_at is not null then return c.recipient_count; end if;
  if c.status not in ('draft', 'scheduled') or exists (select 1 from public.message_jobs j
    where j.campaign_id = c.id and j.tenant_id = c.tenant_id) then
    raise exception 'Previously attempted campaign cannot be re-enqueued' using errcode = '55000';
  end if;
  select * into w from public.whatsapp_connections where tenant_id = c.tenant_id
    and id = coalesce(c.connection_id, (p_expected->>'connection_id')::uuid)
    and status = 'active' and (token_expires_at is null or token_expires_at > now() + interval '30 seconds') for share;
  if not found then raise exception 'Active tenant connection required' using errcode = '22023'; end if;
  if not exists (select 1 from public.whatsapp_connection_credentials s
    where s.connection_id = w.id and s.tenant_id = c.tenant_id) then
    raise exception 'Connection credentials required' using errcode = '22023';
  end if;
  select * into t from public.templates where id = c.template_id and tenant_id = c.tenant_id for share;
  if not found or upper(t.status) <> 'APPROVED' or t.waba_id is distinct from w.waba_id then
    raise exception 'Approved template from the selected WhatsApp account required' using errcode = '22023';
  end if;
  actual := jsonb_build_object('audience_filter', c.audience_filter, 'template_id', c.template_id,
    'template_bindings', c.template_bindings, 'connection_id', w.id,
    'connection', jsonb_build_object('id', w.id, 'waba_id', w.waba_id, 'phone_number_id', w.phone_number_id),
    'template', jsonb_build_object('name', t.name, 'language', t.language, 'components', t.components));
  if p_expected is distinct from actual then
    raise exception 'Campaign or template changed; review again' using errcode = '40001';
  end if;
  insert into public.campaign_dispatches(tenant_id, campaign_id, consented_contact_id,
    recipient_key, recipient_phone, contact_snapshot, state, error_code)
  select c.tenant_id, c.id, a.id,
    case when public.normalize_campaign_phone(a.phone) ~ '^[1-9][0-9]{7,14}$'
      then public.normalize_campaign_phone(a.phone) else a.id::text end,
    public.normalize_campaign_phone(a.phone),
    jsonb_build_object('full_name', a.full_name, 'phone', a.phone, 'email', a.email),
    case when public.normalize_campaign_phone(a.phone) ~ '^[1-9][0-9]{7,14}$' then 'queued' else 'failed' end,
    case when public.normalize_campaign_phone(a.phone) ~ '^[1-9][0-9]{7,14}$' then null else 'invalid_phone' end
  from public.campaign_recipient_audience(c.tenant_id, c.audience_filter) a;
  get diagnostics recipients = row_count;
  if recipients = 0 then raise exception 'Audience has no recipients' using errcode = '22023'; end if;
  update public.campaigns set queued_at = now(), queued_by = p_actor_id, connection_id = w.id,
    send_snapshot = actual, recipient_count = recipients, status = 'queued' where id = c.id;
  return recipients;
end;
$$;

create or replace function public.defer_campaign_dispatch(p_dispatch_id uuid, p_lease_token uuid, p_code text)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  update public.campaign_dispatches set state = 'blocked', error_code = left(p_code, 100),
    error_detail = 'Configuration unavailable; no provider attempt made',
    available_at = now() + interval '5 minutes', leased_until = null, updated_at = now()
    where id = p_dispatch_id and state = 'leased' and lease_token = p_lease_token and leased_until > now();
  return found;
end;
$$;

create or replace function public.guard_campaign_dispatch_connection()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.state = 'sending' and old.state = 'leased' and not exists (
    select 1 from public.campaigns c
    join public.whatsapp_connections w on w.id = c.connection_id and w.tenant_id = c.tenant_id
    join public.whatsapp_connection_credentials s on s.connection_id = w.id and s.tenant_id = w.tenant_id
    join public.templates t on t.id = c.template_id and t.tenant_id = c.tenant_id and t.waba_id = w.waba_id
    where c.id = new.campaign_id and c.tenant_id = new.tenant_id
      and w.status = 'active' and (w.token_expires_at is null or w.token_expires_at > now() + interval '30 seconds')
      and c.send_snapshot->'connection' = jsonb_build_object('id', w.id, 'waba_id', w.waba_id, 'phone_number_id', w.phone_number_id)
  ) then raise exception 'Campaign connection unavailable' using errcode = '55000'; end if;
  return new;
end;
$$;
create trigger campaign_dispatch_connection_guard before update on public.campaign_dispatches
  for each row execute function public.guard_campaign_dispatch_connection();

create or replace function public.claim_campaign_dispatches(p_limit integer default 10, p_campaign_id uuid default null)
returns setof public.campaign_dispatches language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  if p_limit is null or p_limit not between 1 and 25 then
    raise exception 'Claim limit must be 1 through 25' using errcode = '22023';
  end if;
  with expired as (
    select id from public.campaign_dispatches
    where state in ('leased', 'sending') and leased_until < now()
      and (p_campaign_id is null or campaign_id = p_campaign_id)
    order by leased_until limit 500 for update skip locked
  )
  update public.campaign_dispatches j set state = case when j.state = 'leased' then 'queued' else 'unknown' end,
    error_code = case when j.state = 'sending' then 'dispatch_outcome_unknown' else j.error_code end,
    lease_token = case when j.state = 'leased' then null else j.lease_token end,
    leased_until = null, updated_at = now() from expired where j.id = expired.id;
  return query
  with candidates as (
    select j.id from public.campaign_dispatches j
    join public.campaigns c on c.id = j.campaign_id and c.tenant_id = j.tenant_id
    where j.state in ('queued', 'retry_wait', 'blocked') and j.available_at <= now()
      and j.attempts < 5 and c.queued_at is not null and c.status <> 'cancelled'
      and (p_campaign_id is null or j.campaign_id = p_campaign_id)
    order by j.available_at, j.id limit p_limit for update of j skip locked
  )
  update public.campaign_dispatches j set state = 'leased', lease_token = gen_random_uuid(),
    leased_until = now() + interval '120 seconds', updated_at = now()
    from candidates where j.id = candidates.id returning j.*;
end;
$$;

create or replace function public.campaign_progress(p_campaign_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare c public.campaigns; counts jsonb; pending bigint; failures bigint; successes bigint; result_status text;
begin
  select * into c from public.campaigns where id = p_campaign_id;
  if not found then raise exception 'Campaign not found' using errcode = 'P0002'; end if;
  if coalesce(auth.role(), '') <> 'service_role'
    and not coalesce(public.user_has_permission(c.tenant_id, 'campaigns'), false) then
    raise exception 'Campaign permission required' using errcode = '42501';
  end if;
  select jsonb_build_object('total', count(*),
    'queued', count(*) filter (where state = 'queued'),
    'leased', count(*) filter (where state = 'leased'),
    'sending', count(*) filter (where state = 'sending'),
    'retry_wait', count(*) filter (where state = 'retry_wait'),
    'blocked', count(*) filter (where state = 'blocked'),
    'accepted', count(*) filter (where state = 'accepted'),
    'failed', count(*) filter (where state = 'failed'),
    'unknown', count(*) filter (where state = 'unknown'),
    'cancelled', count(*) filter (where state = 'cancelled'),
    'delivered', count(*) filter (where delivery_status in ('delivered', 'read')),
    'read', count(*) filter (where delivery_status = 'read'),
    'delivery_failed', count(*) filter (where delivery_status = 'failed')) into counts
    from public.campaign_dispatches where campaign_id = c.id and tenant_id = c.tenant_id;
  pending := (counts->>'queued')::bigint + (counts->>'leased')::bigint
    + (counts->>'sending')::bigint + (counts->>'retry_wait')::bigint;
  failures := (counts->>'failed')::bigint + (counts->>'delivery_failed')::bigint + (counts->>'cancelled')::bigint;
  successes := (counts->>'accepted')::bigint - (counts->>'delivery_failed')::bigint;
  result_status := case when c.queued_at is null then c.status
    when pending > 0 then 'running'
    when (counts->>'unknown')::bigint > 0 or (counts->>'blocked')::bigint > 0 then 'needs_attention'
    when failures > 0 and successes > 0 then 'partial'
    when failures > 0 then 'failed' else 'completed' end;
  return counts || jsonb_build_object('campaign_id', c.id, 'status', result_status,
    'queued_at', c.queued_at, 'legacy', c.queued_at is null and c.status <> 'draft');
end;
$$;

revoke all on function public.defer_campaign_dispatch(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.guard_campaign_dispatch_connection() from public, anon, authenticated;
grant execute on function public.defer_campaign_dispatch(uuid, uuid, text) to service_role;
