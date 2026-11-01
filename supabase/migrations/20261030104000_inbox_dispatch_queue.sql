-- Message content remains in messages. Private dispatch rows hold worker leases.
alter table public.messages
  add column outbound_state text,
  add column outbound_error_code text,
  add column sent_by uuid references auth.users(id) on delete set null;
revoke all on public.messages from public, anon, authenticated;
grant select on public.messages to authenticated;
grant all on public.messages to service_role;
-- The current client edits tags. Channel identity, previews and lifecycle state
-- are written by authorized RPCs and workers.
revoke all on public.conversations from public, anon, authenticated;
grant select, update(tags) on public.conversations to authenticated;
grant all on public.conversations to service_role;

create table public.inbox_dispatches (
  id uuid primary key,
  sequence bigint generated always as identity unique,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  conversation_id uuid not null,
  connection_id uuid not null,
  recipient_phone text not null check (recipient_phone ~ '^[1-9][0-9]{7,14}$'),
  actor_id uuid references auth.users(id) on delete set null,
  state text not null default 'queued'
    check (state in ('queued', 'leased', 'sending', 'retry_wait', 'blocked', 'accepted', 'failed', 'unknown', 'cancelled')),
  attempts integer not null default 0 check (attempts between 0 and 5),
  available_at timestamptz not null default now(),
  expires_at timestamptz not null,
  lease_token uuid,
  leased_until timestamptz,
  dispatch_started_at timestamptz,
  provider_message_id text,
  accepted_at timestamptz,
  error_code text check (length(error_code) <= 100),
  delivery_status text check (delivery_status in ('sent', 'delivered', 'read', 'failed')),
  delivery_error_code text,
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inbox_dispatches_message_tenant_fk foreign key (tenant_id, id)
    references public.messages(tenant_id, id) on delete cascade,
  foreign key (tenant_id, conversation_id) references public.conversations(tenant_id, id) on delete cascade,
  foreign key (tenant_id, connection_id) references public.whatsapp_connections(tenant_id, id),
  check (state not in ('leased', 'sending') or (lease_token is not null and leased_until is not null))
);
create unique index inbox_dispatches_provider_id on public.inbox_dispatches(connection_id, provider_message_id)
  where provider_message_id is not null;
create index inbox_dispatches_pending on public.inbox_dispatches(available_at, sequence)
  where state in ('queued', 'retry_wait', 'blocked', 'leased', 'sending');
create index inbox_dispatches_conversation on public.inbox_dispatches(conversation_id, sequence);
alter table public.inbox_dispatches enable row level security;
revoke all on public.inbox_dispatches from public, anon, authenticated;
grant all on public.inbox_dispatches to service_role;
grant usage, select on sequence public.inbox_dispatches_sequence_seq to service_role;

-- Publish display state through the existing messages realtime subscription.
-- Worker tokens never become client-readable. Both writes share one transaction.
create function public.sync_inbox_dispatch_message()
returns trigger language plpgsql set search_path = '' as $$
begin
  update public.messages set outbound_state = new.state,
    outbound_error_code = coalesce(new.delivery_error_code, new.error_code),
    wa_message_id = new.provider_message_id, wa_status = new.delivery_status,
    delivered_at = new.delivered_at, read_at = new.read_at
    where tenant_id = new.tenant_id and id = new.id;
  return new;
end;
$$;
create trigger sync_inbox_dispatch_message after insert or update on public.inbox_dispatches
  for each row execute function public.sync_inbox_dispatch_message();
revoke all on function public.sync_inbox_dispatch_message() from public, anon, authenticated;

create function public.enqueue_inbox_message(
  p_tenant_id uuid, p_conversation_id uuid, p_message_id uuid, p_body text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  conversation public.conversations;
  existing public.inbox_dispatches;
  normalized_body text := btrim(p_body);
  sender_name text;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  if p_message_id is null or normalized_body is null or length(normalized_body) not between 1 and 4096
    or normalized_body !~ '[^[:space:]]' then
    raise exception 'Text must contain 1 to 4096 characters' using errcode = '22023';
  end if;
  select * into conversation from public.conversations
    where tenant_id = p_tenant_id and id = p_conversation_id for update;
  if not found then raise exception 'Conversation unavailable' using errcode = 'P0002'; end if;
  select * into existing from public.inbox_dispatches where id = p_message_id;
  if found then
    if existing.tenant_id <> p_tenant_id or existing.conversation_id <> p_conversation_id
      or existing.actor_id is distinct from auth.uid() then
      raise exception 'Message identity unavailable' using errcode = '42501';
    end if;
    if not exists (select 1 from public.messages where id = p_message_id and body = normalized_body) then
      raise exception 'Message identity already used' using errcode = '40001';
    end if;
    return jsonb_build_object('message_id', existing.id, 'state', existing.state);
  end if;
  if conversation.connection_id is null then
    raise exception 'Conversation requires an explicit WhatsApp account mapping' using errcode = 'P0003';
  end if;
  if conversation.last_customer_message_at is null
    or conversation.last_customer_message_at <= clock_timestamp() - interval '24 hours' then
    raise exception 'Customer service window closed' using errcode = 'P0004';
  end if;
  if not exists (select 1 from public.whatsapp_connections w
    join public.whatsapp_connection_credentials k on k.connection_id = w.id and k.tenant_id = w.tenant_id
    where w.id = conversation.connection_id and w.tenant_id = p_tenant_id and w.status = 'active'
      and (w.token_expires_at is null or w.token_expires_at > clock_timestamp() + interval '30 seconds')) then
    raise exception 'WhatsApp connection unavailable' using errcode = 'P0005';
  end if;
  select coalesce(nullif(left(btrim(display_name), 128), ''), 'Temsilci') into sender_name
    from public.user_profiles where id = auth.uid();
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, sent_by, is_from_customer)
    values(p_message_id, p_tenant_id, p_conversation_id, conversation.connection_id,
      coalesce(sender_name, 'Temsilci'), normalized_body, auth.uid(), false);
  insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, actor_id, expires_at)
    values(p_message_id, p_tenant_id, p_conversation_id, conversation.connection_id, conversation.customer_phone,
      auth.uid(), conversation.last_customer_message_at + interval '24 hours');
  -- A human reply takes ownership until an explicit support lifecycle action.
  update public.conversations set status = case when status = 'handoff' then 'handoff' else 'pending' end,
    last_message = normalized_body, last_message_at = clock_timestamp(), updated_at = clock_timestamp()
    where id = p_conversation_id;
  update public.bot_reply_jobs set state = 'cancelled', lease_token = null, leased_until = null,
    error_code = 'human_reply', updated_at = clock_timestamp()
    where tenant_id = p_tenant_id and conversation_id = p_conversation_id and state in ('queued', 'leased', 'ready');
  return jsonb_build_object('message_id', p_message_id, 'state', 'queued');
end;
$$;
revoke all on function public.enqueue_inbox_message(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.enqueue_inbox_message(uuid, uuid, uuid, text) to authenticated;

create function public.claim_inbox_dispatches(p_limit integer default 10)
returns setof public.inbox_dispatches language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  if p_limit is null or p_limit not between 1 and 25 then
    raise exception 'Invalid batch limit' using errcode = '22023';
  end if;
  -- Expire unsent work even when credentials cannot be loaded by the worker.
  with expired_window as (
    select d.id from public.inbox_dispatches d
    join public.conversations c on c.id = d.conversation_id and c.tenant_id = d.tenant_id
    where d.state in ('queued', 'retry_wait', 'blocked')
      and (d.expires_at <= now() or c.last_customer_message_at is null
        or c.last_customer_message_at <= now() - interval '24 hours')
    order by d.sequence limit 500 for update of d skip locked
  )
  update public.inbox_dispatches d set state = 'failed', error_code = 'customer_service_window_closed',
    leased_until = null, updated_at = now() from expired_window where d.id = expired_window.id;
  with expired as (
    select id from public.inbox_dispatches where state in ('leased', 'sending') and leased_until <= now()
    order by leased_until limit 500 for update skip locked
  )
  update public.inbox_dispatches d set
    state = case when d.state = 'sending' then 'unknown' else 'queued' end,
    error_code = case when d.state = 'sending' then 'dispatch_outcome_unknown' else null end,
    lease_token = case when d.state = 'sending' then d.lease_token else null end,
    leased_until = null, updated_at = now() from expired where d.id = expired.id;
  return query
  with candidates as (
    select d.id from public.inbox_dispatches d
    where d.state in ('queued', 'retry_wait', 'blocked') and d.available_at <= now() and d.attempts < 5
      and not exists (select 1 from public.inbox_dispatches earlier
        where earlier.conversation_id = d.conversation_id and earlier.sequence < d.sequence
          and earlier.state in ('queued', 'leased', 'sending', 'retry_wait', 'blocked'))
    order by d.available_at, d.sequence limit p_limit for update of d skip locked
  )
  update public.inbox_dispatches d set state = 'leased', lease_token = gen_random_uuid(),
    leased_until = now() + interval '120 seconds', updated_at = now()
    from candidates where d.id = candidates.id returning d.*;
end;
$$;

create function public.start_inbox_dispatch(p_dispatch_id uuid, p_lease_token uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare job public.inbox_dispatches; conversation public.conversations; failure text;
begin
  perform public.require_service_role();
  select * into job from public.inbox_dispatches where id = p_dispatch_id;
  if not found then return false; end if;
  select * into conversation from public.conversations
    where id = job.conversation_id and tenant_id = job.tenant_id for update;
  select * into job from public.inbox_dispatches where id = p_dispatch_id for update;
  if not found or job.state <> 'leased' or job.lease_token is distinct from p_lease_token
    or job.leased_until <= clock_timestamp() then return false; end if;
  if conversation.connection_id is distinct from job.connection_id
    or conversation.customer_phone is distinct from job.recipient_phone then
    failure := 'conversation_identity_changed';
  elsif conversation.status = 'closed' then
    failure := 'conversation_closed';
  elsif not exists (select 1 from public.tenant_memberships where tenant_id = job.tenant_id and user_id = job.actor_id
    and (role = 'admin' or 'inbox' = any(permissions))) then
    failure := 'sender_permission_revoked';
  elsif job.expires_at <= clock_timestamp() or conversation.last_customer_message_at is null
    or conversation.last_customer_message_at <= clock_timestamp() - interval '24 hours' then
    failure := 'customer_service_window_closed';
  end if;
  if failure is not null then
    update public.inbox_dispatches set state = 'failed', error_code = failure, leased_until = null, updated_at = now()
      where id = job.id;
    return false;
  end if;
  if not exists (select 1 from public.whatsapp_connections w
    join public.whatsapp_connection_credentials k on k.connection_id = w.id and k.tenant_id = w.tenant_id
    where w.id = job.connection_id and w.tenant_id = job.tenant_id and w.status = 'active'
      and (w.token_expires_at is null or w.token_expires_at > clock_timestamp() + interval '30 seconds')) then
    update public.inbox_dispatches set state = 'blocked', error_code = 'connection_unavailable',
      leased_until = null, available_at = now() + interval '5 minutes', updated_at = now() where id = job.id;
    return false;
  end if;
  update public.inbox_dispatches set state = 'sending', attempts = attempts + 1,
    dispatch_started_at = clock_timestamp(), leased_until = clock_timestamp() + interval '120 seconds', updated_at = now()
    where id = job.id;
  return true;
end;
$$;

create function public.defer_inbox_dispatch(p_dispatch_id uuid, p_lease_token uuid, p_code text)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  update public.inbox_dispatches set state = 'blocked', error_code = left(p_code, 100), leased_until = null,
    available_at = now() + interval '5 minutes', updated_at = now()
    where id = p_dispatch_id and state = 'leased' and lease_token = p_lease_token and leased_until > now();
  return found;
end;
$$;

create function public.finish_inbox_dispatch(
  p_dispatch_id uuid, p_lease_token uuid, p_outcome text, p_provider_message_id text default null,
  p_error_code text default null, p_retry_after_seconds integer default 0
) returns boolean language plpgsql security invoker set search_path = '' as $$
declare job public.inbox_dispatches;
begin
  perform public.require_service_role();
  if p_outcome is null or p_outcome not in ('accepted', 'failed', 'retry', 'unknown') then
    raise exception 'Invalid dispatch outcome' using errcode = '22023';
  end if;
  if p_outcome = 'accepted' and (p_provider_message_id is null or p_provider_message_id !~ '^wamid\.[^[:space:]]{1,506}$') then
    raise exception 'Provider message ID required' using errcode = '22023';
  end if;
  select * into job from public.inbox_dispatches where id = p_dispatch_id for update;
  if not found or job.lease_token is distinct from p_lease_token then return false; end if;
  if job.state = 'accepted' and p_outcome = 'accepted' and job.provider_message_id = p_provider_message_id then return true; end if;
  if job.state not in ('sending', 'unknown') then return false; end if;
  update public.inbox_dispatches set
    state = case when p_outcome = 'retry' then case when attempts < 5 then 'retry_wait' else 'failed' end else p_outcome end,
    available_at = case when p_outcome = 'retry' then now() + make_interval(secs =>
      greatest(least(coalesce(p_retry_after_seconds, 0), 3600), least(3600, (30 * power(2, greatest(attempts - 1, 0)))::int)))
      else available_at end,
    provider_message_id = case when p_outcome = 'accepted' then p_provider_message_id else null end,
    accepted_at = case when p_outcome = 'accepted' then clock_timestamp() else null end,
    error_code = case when p_outcome = 'accepted' then null else left(p_error_code, 100) end,
    leased_until = null, updated_at = now() where id = job.id;
  return true;
end;
$$;

create function public.apply_inbox_receipt(p_event_key text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  event public.whatsapp_webhook_events;
  job public.inbox_dispatches;
  callback_id uuid;
  callback_token uuid;
  incoming text;
  effective text;
begin
  perform public.require_service_role();
  select * into event from public.whatsapp_webhook_events where event_key = p_event_key;
  if not found or event.kind <> 'status' or event.tenant_id is null then return false; end if;
  incoming := event.payload->>'status';
  if incoming is null or incoming not in ('sent', 'delivered', 'read', 'failed') then
    raise exception 'Invalid receipt state' using errcode = '22023';
  end if;
  if event.payload->>'callback' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    callback_id := split_part(event.payload->>'callback', ':', 1)::uuid;
    callback_token := split_part(event.payload->>'callback', ':', 2)::uuid;
  end if;
  select * into job from public.inbox_dispatches
    where tenant_id = event.tenant_id and connection_id = event.connection_id
      and recipient_phone = event.payload->>'recipient_phone'
      and (provider_message_id = event.provider_message_id or
        (id = callback_id and lease_token = callback_token and state in ('sending', 'unknown') and provider_message_id is null))
    order by (provider_message_id = event.provider_message_id) desc nulls last limit 1 for update;
  if not found then return false; end if;
  effective := case
    when job.delivery_status = 'read' or incoming = 'read' then 'read'
    when job.delivery_status = 'delivered' or incoming = 'delivered' then 'delivered'
    when job.delivery_status = 'failed' or incoming = 'failed' then 'failed'
    else 'sent' end;
  update public.inbox_dispatches set state = 'accepted', provider_message_id = event.provider_message_id,
    accepted_at = coalesce(accepted_at, event.occurred_at), leased_until = null, error_code = null,
    delivery_status = effective,
    delivered_at = case when incoming in ('delivered', 'read') then least(delivered_at, event.occurred_at) else delivered_at end,
    read_at = case when incoming = 'read' then least(read_at, event.occurred_at) else read_at end,
    delivery_error_code = case when effective = 'failed' then coalesce(event.payload->>'error_code', delivery_error_code) else null end,
    updated_at = now() where id = job.id;
  return true;
end;
$$;

revoke all on function public.claim_inbox_dispatches(integer) from public, anon, authenticated;
revoke all on function public.start_inbox_dispatch(uuid, uuid) from public, anon, authenticated;
revoke all on function public.defer_inbox_dispatch(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.finish_inbox_dispatch(uuid, uuid, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.apply_inbox_receipt(text) from public, anon, authenticated;
grant execute on function public.claim_inbox_dispatches(integer) to service_role;
grant execute on function public.start_inbox_dispatch(uuid, uuid) to service_role;
grant execute on function public.defer_inbox_dispatch(uuid, uuid, text) to service_role;
grant execute on function public.finish_inbox_dispatch(uuid, uuid, text, text, text, integer) to service_role;
grant execute on function public.apply_inbox_receipt(text) to service_role;

-- One receipt consumer reconciles both outbound paths.
create or replace function public.process_whatsapp_receipts(p_limit integer default 50)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare e public.whatsapp_webhook_events; w public.whatsapp_connections; applied integer:=0; deferred integer:=0; failures integer:=0; matched boolean;
begin
  perform public.require_service_role();
  if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid batch limit' using errcode='22023'; end if;
  for e in select * from public.whatsapp_webhook_events where kind='status' and state='pending' and available_at<=now()
    order by available_at,event_key limit p_limit for update skip locked loop
    begin
      if e.connection_id is null then
        select * into w from public.whatsapp_connections where phone_number_id=e.phone_number_id and waba_id=e.waba_id;
        if found then
          update public.whatsapp_webhook_events set tenant_id=w.tenant_id,connection_id=w.id where event_key=e.event_key;
        end if;
      end if;
      matched := public.apply_campaign_receipt(e.event_key);
      if not matched then matched := public.apply_inbox_receipt(e.event_key); end if;
      if matched then
        update public.whatsapp_webhook_events set state='applied',processed_at=now(),error_code=null,attempts=attempts+1 where event_key=e.event_key;
        applied:=applied+1;
      else
        update public.whatsapp_webhook_events set state=case when received_at<now()-interval '7 days' then 'error' else 'pending' end,
          error_code='receipt_unmatched',available_at=now()+interval '5 minutes',attempts=attempts+1 where event_key=e.event_key;
        deferred:=deferred+1;
      end if;
    exception when others then
      -- Roll back only this event's application. Never persist raw database/provider errors.
      update public.whatsapp_webhook_events set state=case when attempts>=19 then 'error' else 'pending' end,
        error_code='receipt_processing_failed',attempts=attempts+1,available_at=now()+interval '5 minutes' where event_key=e.event_key;
      failures:=failures+1;
    end;
  end loop;
  return jsonb_build_object('applied',applied,'deferred',deferred,'failed',failures);
end;
$$;
