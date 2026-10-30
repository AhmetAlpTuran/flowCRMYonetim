-- Durable campaign execution. Legacy message_jobs remain historical records.
-- All dispatch mutation RPCs are service-only; end users can read their progress.
alter table public.campaigns
  add column queued_at timestamptz,
  add column queued_by uuid references auth.users(id) on delete set null,
  add column send_snapshot jsonb,
  add column recipient_count integer,
  add column finished_at timestamptz,
  add constraint campaigns_snapshot_shape check (
    (queued_at is null and send_snapshot is null and recipient_count is null)
    or (queued_at is not null and send_snapshot is not null and recipient_count is not null
      and jsonb_typeof(send_snapshot) = 'object' and recipient_count > 0)
  );
alter table public.campaigns drop constraint campaigns_status_check;
alter table public.campaigns add constraint campaigns_status_check check (
  status in ('draft', 'scheduled', 'queued', 'running', 'completed', 'partial',
    'failed', 'needs_attention', 'cancelled')
);
alter table public.campaigns add constraint campaigns_tenant_id_id_key unique (tenant_id, id);
alter table public.consented_contacts add constraint consented_contacts_tenant_id_id_key unique (tenant_id, id);
alter table public.templates add constraint templates_tenant_id_id_key unique (tenant_id, id);
-- Historical invalid references must be audited before validating this constraint.
-- NOT VALID still checks every new or changed reference immediately.
alter table public.campaigns add constraint campaigns_template_tenant_fk
  foreign key (tenant_id, template_id) references public.templates(tenant_id, id) not valid;

create or replace function public.normalize_campaign_phone(p_phone text)
returns text language sql immutable security invoker set search_path = '' as $$
  select case when btrim(coalesce(p_phone, '')) ~ '^\+?[0-9][0-9 ().-]*$' then
    regexp_replace(regexp_replace(p_phone, '[^0-9]', '', 'g'), '^00', '') else '' end;
$$;

-- Preserve the shared filter contract, then choose one consented record per phone.
-- Invalid phone values remain individual failures rather than disappearing silently.
create or replace function public.campaign_recipient_audience(p_tenant_id uuid, p_filter jsonb default '{}')
returns setof public.consented_contacts language sql stable security invoker set search_path = '' as $$
  select distinct on (
    case when public.normalize_campaign_phone(c.phone) ~ '^[1-9][0-9]{7,14}$'
      then public.normalize_campaign_phone(c.phone) else c.id::text end
  ) c.* from public.campaign_audience(p_tenant_id, p_filter) c
  order by case when public.normalize_campaign_phone(c.phone) ~ '^[1-9][0-9]{7,14}$'
    then public.normalize_campaign_phone(c.phone) else c.id::text end,
    c.consented_at desc, c.id;
$$;

create or replace function public.count_campaign_audience(p_tenant_id uuid, p_filter jsonb default '{}')
returns bigint language sql stable security invoker set search_path = '' as $$
  select count(*) from public.campaign_recipient_audience(p_tenant_id, p_filter);
$$;
revoke all on function public.normalize_campaign_phone(text) from public, anon;
revoke all on function public.campaign_recipient_audience(uuid, jsonb) from public, anon;
grant execute on function public.normalize_campaign_phone(text) to authenticated, service_role;
grant execute on function public.campaign_recipient_audience(uuid, jsonb) to authenticated, service_role;

create table public.campaign_dispatches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  campaign_id uuid not null,
  consented_contact_id uuid references public.consented_contacts(id) on delete set null,
  recipient_key text not null,
  recipient_phone text not null,
  contact_snapshot jsonb not null,
  state text not null default 'queued' check (state in
    ('queued', 'leased', 'sending', 'retry_wait', 'accepted', 'failed', 'unknown', 'cancelled')),
  attempts integer not null default 0 check (attempts between 0 and 5),
  available_at timestamptz not null default now(),
  lease_token uuid,
  leased_until timestamptz,
  dispatch_started_at timestamptz,
  provider_message_id text,
  accepted_at timestamptz,
  delivery_status text check (delivery_status in ('sent', 'delivered', 'read', 'failed')),
  delivered_at timestamptz,
  read_at timestamptz,
  error_code text,
  error_detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, campaign_id) references public.campaigns(tenant_id, id) on delete cascade,
  foreign key (tenant_id, consented_contact_id) references public.consented_contacts(tenant_id, id),
  unique (campaign_id, recipient_key),
  check (jsonb_typeof(contact_snapshot) = 'object'),
  check (error_detail is null or length(error_detail) <= 500),
  check (state not in ('leased', 'sending') or (lease_token is not null and leased_until is not null)),
  check (state not in ('sending', 'unknown') or (attempts > 0 and dispatch_started_at is not null)),
  check (state <> 'accepted' or (provider_message_id is not null and accepted_at is not null))
);
create unique index campaign_dispatch_provider_message on public.campaign_dispatches
  (tenant_id, provider_message_id) where provider_message_id is not null;
create index campaign_dispatch_ready on public.campaign_dispatches (available_at, id)
  where state in ('queued', 'retry_wait');
create index campaign_dispatch_leases on public.campaign_dispatches (leased_until)
  where state in ('leased', 'sending');
create index campaign_dispatch_progress on public.campaign_dispatches (tenant_id, campaign_id, state);
alter table public.campaign_dispatches enable row level security;
revoke all on public.campaign_dispatches from public, anon, authenticated;
grant select on public.campaign_dispatches to authenticated;
grant all on public.campaign_dispatches to service_role;
create policy campaign_dispatch_read on public.campaign_dispatches for select to authenticated
  using (public.user_has_permission(tenant_id, 'campaigns'));
-- Legacy jobs are also server records; clients must not forge send history.
revoke insert, update, delete, truncate, references, trigger on public.message_jobs from public, authenticated, anon;

-- Campaign operators must be able to select an approved template without the
-- separate permission to create/edit template definitions.
create policy templates_campaign_read on public.templates for select to authenticated
  using (public.user_has_permission(tenant_id, 'campaigns'));

create or replace function public.guard_campaign_execution()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.queued_at is not null and (
    new.id is distinct from old.id or new.tenant_id is distinct from old.tenant_id
    -- A deleted template may clear its live FK; the frozen definition survives.
    or (new.template_id is distinct from old.template_id and new.template_id is not null)
    or new.audience_filter is distinct from old.audience_filter
    or new.template_bindings is distinct from old.template_bindings
    or new.send_snapshot is distinct from old.send_snapshot
    or new.queued_at is distinct from old.queued_at
    or new.recipient_count is distinct from old.recipient_count
  ) then raise exception 'Queued campaign configuration is immutable' using errcode = '55000'; end if;
  if current_user not in ('postgres', 'supabase_admin', 'service_role') then
    if tg_op = 'DELETE' then
      if old.queued_at is not null then
        raise exception 'Cannot delete queued campaigns' using errcode = '42501';
      end if;
      return old;
    end if;
    if new.status <> 'draft' or new.queued_at is not null or new.queued_by is not null
      or new.send_snapshot is not null or new.recipient_count is not null or new.finished_at is not null then
      raise exception 'Execution fields are server managed' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and (new.id <> old.id or new.tenant_id <> old.tenant_id
      or new.created_at <> old.created_at) then
      raise exception 'Campaign identity is immutable' using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger campaign_execution_guard before insert or update or delete on public.campaigns
  for each row execute function public.guard_campaign_execution();
drop policy campaigns_access on public.campaigns;
create policy campaigns_read on public.campaigns for select to authenticated
  using (public.user_has_permission(tenant_id, 'campaigns'));
create policy campaigns_create_draft on public.campaigns for insert to authenticated
  with check (public.user_has_permission(tenant_id, 'campaigns') and status = 'draft' and queued_at is null);
create policy campaigns_edit_draft on public.campaigns for update to authenticated
  using (public.user_has_permission(tenant_id, 'campaigns') and status = 'draft' and queued_at is null)
  with check (public.user_has_permission(tenant_id, 'campaigns') and status = 'draft' and queued_at is null);
create policy campaigns_delete_draft on public.campaigns for delete to authenticated
  using (public.user_has_permission(tenant_id, 'campaigns') and status = 'draft' and queued_at is null);

create or replace function public.require_campaign_worker()
returns void language plpgsql stable security invoker set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Campaign worker access required' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.enqueue_campaign(
  p_campaign_id uuid, p_actor_id uuid, p_expected jsonb
) returns integer language plpgsql security invoker set search_path = '' as $$
declare c public.campaigns; t public.templates; actual jsonb; recipients integer;
begin
  perform public.require_campaign_worker();
  select * into c from public.campaigns where id = p_campaign_id for update;
  if not found then raise exception 'Campaign not found' using errcode = 'P0002'; end if;
  if p_actor_id is null or not exists (
    select 1 from public.tenant_memberships m where m.tenant_id = c.tenant_id
      and m.user_id = p_actor_id and (m.role = 'admin' or 'campaigns' = any(m.permissions))
  ) then raise exception 'Campaign permission required' using errcode = '42501'; end if;
  -- A repeated request returns the original frozen audience, never enqueues twice.
  if c.queued_at is not null then return c.recipient_count; end if;
  if c.status not in ('draft', 'scheduled') or exists (
    select 1 from public.message_jobs j where j.campaign_id = c.id and j.tenant_id = c.tenant_id
  ) then raise exception 'Previously attempted campaign cannot be re-enqueued' using errcode = '55000'; end if;
  select * into t from public.templates where id = c.template_id and tenant_id = c.tenant_id for share;
  if not found or upper(t.status) <> 'APPROVED' then
    raise exception 'Approved tenant template required' using errcode = '22023';
  end if;
  actual := jsonb_build_object('audience_filter', c.audience_filter,
    'template_id', c.template_id, 'template_bindings', c.template_bindings,
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
  update public.campaigns set queued_at = now(), queued_by = p_actor_id,
    send_snapshot = actual, recipient_count = recipients, status = 'queued'
    where id = c.id;
  return recipients;
end;
$$;

create or replace function public.claim_campaign_dispatches(p_limit integer default 10, p_campaign_id uuid default null)
returns setof public.campaign_dispatches language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_campaign_worker();
  if p_limit is null or p_limit not between 1 and 25 then
    raise exception 'Claim limit must be 1 through 25' using errcode = '22023';
  end if;
  -- Before the dispatch marker, a lost lease is safe to reclaim. After the marker,
  -- the external outcome may be unknown: no automatic replay is allowed.
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
    where j.state in ('queued', 'retry_wait') and j.available_at <= now()
      and j.attempts < 5 and c.queued_at is not null and c.status <> 'cancelled'
      and (p_campaign_id is null or j.campaign_id = p_campaign_id)
    order by j.available_at, j.id limit p_limit for update of j skip locked
  )
  update public.campaign_dispatches j set state = 'leased', lease_token = gen_random_uuid(),
    leased_until = now() + interval '120 seconds', updated_at = now()
    from candidates where j.id = candidates.id returning j.*;
end;
$$;

create or replace function public.start_campaign_dispatch(p_dispatch_id uuid, p_lease_token uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare j public.campaign_dispatches; snapshot jsonb; current_template jsonb;
begin
  perform public.require_campaign_worker();
  select * into j from public.campaign_dispatches where id = p_dispatch_id for update;
  if not found or j.state <> 'leased' or j.lease_token is distinct from p_lease_token
    or j.leased_until <= now() then return false; end if;
  if not exists (select 1 from public.consented_contacts c
    where c.id = j.consented_contact_id and c.tenant_id = j.tenant_id
      and public.normalize_campaign_phone(c.phone) = j.recipient_phone) then
    update public.campaign_dispatches set state = 'cancelled', error_code = 'consent_unavailable',
      leased_until = null, updated_at = now() where id = j.id;
    return false;
  end if;
  select c.send_snapshot->'template', jsonb_build_object('name', t.name, 'language', t.language, 'components', t.components)
    into snapshot, current_template from public.campaigns c
    join public.templates t on t.id = c.template_id and t.tenant_id = c.tenant_id and upper(t.status) = 'APPROVED'
    where c.id = j.campaign_id and c.tenant_id = j.tenant_id and c.status <> 'cancelled';
  if not found or snapshot is distinct from current_template then
    update public.campaign_dispatches set state = 'failed', error_code = 'template_changed_or_unavailable',
      leased_until = null, updated_at = now() where id = j.id;
    return false;
  end if;
  update public.campaign_dispatches set state = 'sending', attempts = attempts + 1,
    dispatch_started_at = now(), leased_until = now() + interval '120 seconds', updated_at = now()
    where id = j.id;
  return true;
end;
$$;

-- Validation failures happen while leased, before the irreversible dispatch marker.
create or replace function public.fail_campaign_validation(p_dispatch_id uuid, p_lease_token uuid, p_detail text)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_campaign_worker();
  update public.campaign_dispatches set state = 'failed', error_code = 'invalid_template_values',
    error_detail = left(p_detail, 500), leased_until = null, updated_at = now()
    where id = p_dispatch_id and state = 'leased' and lease_token = p_lease_token and leased_until > now();
  return found;
end;
$$;

create or replace function public.finish_campaign_dispatch(
  p_dispatch_id uuid, p_lease_token uuid, p_outcome text,
  p_provider_message_id text default null, p_error_code text default null,
  p_detail text default null, p_retry_after_seconds integer default 0
) returns boolean language plpgsql security invoker set search_path = '' as $$
declare j public.campaign_dispatches;
begin
  perform public.require_campaign_worker();
  if p_outcome is null or p_outcome not in ('accepted', 'failed', 'retry', 'unknown') then
    raise exception 'Invalid dispatch outcome' using errcode = '22023';
  end if;
  if p_outcome = 'accepted' and (p_provider_message_id is null
    or p_provider_message_id not like 'wamid.%' or length(p_provider_message_id) > 512) then
    raise exception 'Provider message ID required' using errcode = '22023';
  end if;
  select * into j from public.campaign_dispatches where id = p_dispatch_id for update;
  if not found or j.lease_token is distinct from p_lease_token then return false; end if;
  if j.state = 'accepted' and p_outcome = 'accepted' and j.provider_message_id = p_provider_message_id then
    return true; -- retrying this database acknowledgement does not send a message.
  end if;
  if j.state not in ('sending', 'unknown') then return false; end if;
  update public.campaign_dispatches set
    state = case when p_outcome = 'retry' then case when attempts < 5 then 'retry_wait' else 'failed' end else p_outcome end,
    available_at = case when p_outcome = 'retry' then now() + make_interval(secs =>
      greatest(least(coalesce(p_retry_after_seconds, 0), 3600),
        least(3600, (30 * power(2, greatest(attempts - 1, 0)))::int))) else available_at end,
    provider_message_id = case when p_outcome = 'accepted' then p_provider_message_id else null end,
    accepted_at = case when p_outcome = 'accepted' then now() else null end,
    error_code = case when p_outcome = 'accepted' then null else left(p_error_code, 100) end,
    error_detail = case when p_outcome = 'accepted' then null else left(p_detail, 500) end,
    leased_until = null, updated_at = now() where id = j.id;
  if p_outcome = 'accepted' then
    update public.consented_contacts set last_contacted_at = now()
      where id = j.consented_contact_id and tenant_id = j.tenant_id
        and public.normalize_campaign_phone(phone) = j.recipient_phone;
  end if;
  return true;
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
  result_status := case
    when c.queued_at is null then c.status
    when pending > 0 then 'running'
    when (counts->>'unknown')::bigint > 0 then 'needs_attention'
    when failures > 0 and successes > 0 then 'partial'
    when failures > 0 then 'failed'
    else 'completed' end;
  return counts || jsonb_build_object('campaign_id', c.id, 'status', result_status,
    'queued_at', c.queued_at, 'legacy', c.queued_at is null and c.status <> 'draft');
end;
$$;

-- Refresh is separate from job acknowledgement: it locks only the campaign row,
-- avoiding a campaign/job lock-order cycle between independent workers.
create or replace function public.refresh_campaign_progress(p_campaign_id uuid)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare progress jsonb;
begin
  perform public.require_campaign_worker();
  perform 1 from public.campaigns where id = p_campaign_id for update;
  progress := public.campaign_progress(p_campaign_id);
  update public.campaigns set status = progress->>'status', finished_at = case
    when progress->>'status' in ('completed', 'partial', 'failed') then coalesce(finished_at, now())
    else null end where id = p_campaign_id and queued_at is not null;
  return progress;
end;
$$;

revoke all on function public.guard_campaign_execution() from public, anon, authenticated;
revoke all on function public.require_campaign_worker() from public, anon, authenticated;
revoke all on function public.enqueue_campaign(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.claim_campaign_dispatches(integer, uuid) from public, anon, authenticated;
revoke all on function public.start_campaign_dispatch(uuid, uuid) from public, anon, authenticated;
revoke all on function public.fail_campaign_validation(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.finish_campaign_dispatch(uuid, uuid, text, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.refresh_campaign_progress(uuid) from public, anon, authenticated;
revoke all on function public.campaign_progress(uuid) from public, anon;
grant execute on function public.require_campaign_worker() to service_role;
grant execute on function public.enqueue_campaign(uuid, uuid, jsonb) to service_role;
grant execute on function public.claim_campaign_dispatches(integer, uuid) to service_role;
grant execute on function public.start_campaign_dispatch(uuid, uuid) to service_role;
grant execute on function public.fail_campaign_validation(uuid, uuid, text) to service_role;
grant execute on function public.finish_campaign_dispatch(uuid, uuid, text, text, text, text, integer) to service_role;
grant execute on function public.refresh_campaign_progress(uuid) to service_role;
grant execute on function public.campaign_progress(uuid) to authenticated, service_role;
