alter table public.handoff_requests
  add constraint handoff_conversation_tenant_fk foreign key (tenant_id, conversation_id)
    references public.conversations(tenant_id, id) on delete cascade not valid;
revoke all on public.handoff_requests from public, anon, authenticated;
grant select on public.handoff_requests to authenticated;
grant all on public.handoff_requests to service_role;

create or replace function public.protect_conversation_provider_fields()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.role() = 'service_role' or current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.connection_id is not null or new.customer_phone is not null
      or new.last_customer_message_at is not null or new.last_message_at is not null
      or new.last_opened_at is not null or new.last_opened_by is not null
      or new.last_opened_role is not null or new.unread_count <> 0 or new.status <> 'open' then
      raise exception 'Conversation lifecycle is server managed' using errcode = '42501';
    end if;
  elsif new.tenant_id is distinct from old.tenant_id
    or new.connection_id is distinct from old.connection_id
    or new.customer_phone is distinct from old.customer_phone
    or new.last_customer_message_at is distinct from old.last_customer_message_at
    or new.last_message_at is distinct from old.last_message_at
    or new.last_opened_at is distinct from old.last_opened_at
    or new.last_opened_by is distinct from old.last_opened_by
    or new.last_opened_role is distinct from old.last_opened_role
    or new.unread_count is distinct from old.unread_count
    or new.status is distinct from old.status then
    raise exception 'Conversation lifecycle is server managed' using errcode = '42501';
  end if;
  return new;
end;
$$;

create function public.mark_conversation_opened(p_tenant_id uuid, p_conversation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare actor_role text;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  select role into actor_role from public.tenant_memberships
    where tenant_id = p_tenant_id and user_id = auth.uid();
  -- This shared-inbox marker records opening at this transaction's lock boundary.
  -- Incoming materialization takes the same conversation row lock.
  update public.conversations set last_opened_at = clock_timestamp(),
    last_opened_by = auth.uid(), last_opened_role = actor_role, unread_count = 0
    where tenant_id = p_tenant_id and id = p_conversation_id;
  if not found then raise exception 'Conversation unavailable' using errcode = 'P0002'; end if;
end;
$$;

create function public.request_conversation_handoff(
  p_tenant_id uuid, p_conversation_id uuid, p_request_id uuid, p_note text default ''
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  conversation public.conversations;
  existing public.handoff_requests;
  normalized_note text := btrim(coalesce(p_note, ''));
begin
  if auth.uid() is null
    or not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false)
    or not coalesce(public.user_has_permission(p_tenant_id, 'handoff'), false) then
    raise exception 'Inbox and handoff permissions required' using errcode = '42501';
  end if;
  if p_request_id is null or length(normalized_note) > 2000 then
    raise exception 'Invalid handoff request' using errcode = '22023';
  end if;
  select * into conversation from public.conversations
    where tenant_id = p_tenant_id and id = p_conversation_id for update;
  if not found then raise exception 'Conversation unavailable' using errcode = 'P0002'; end if;
  select * into existing from public.handoff_requests where id = p_request_id;
  if found then
    if existing.tenant_id <> p_tenant_id or existing.conversation_id <> p_conversation_id
      or existing.created_by is distinct from auth.uid() then
      raise exception 'Request identity unavailable' using errcode = '42501';
    end if;
    if coalesce(existing.note, '') <> normalized_note then
      raise exception 'Request identity already used' using errcode = '40001';
    end if;
    return existing.id;
  end if;
  if conversation.status = 'handoff' then
    raise exception 'Conversation already handed off' using errcode = '55000';
  end if;
  insert into public.handoff_requests(id, tenant_id, conversation_id, note, status, created_by)
    values(p_request_id, p_tenant_id, p_conversation_id, normalized_note, 'open', auth.uid());
  update public.conversations set status = 'handoff', updated_at = clock_timestamp()
    where id = p_conversation_id and tenant_id = p_tenant_id;
  -- Future bot claims/finalization must use conversation -> job lock order and
  -- validate the lease token again before creating an outbound response.
  update public.bot_reply_jobs set state = 'cancelled', lease_token = null,
    leased_until = null, error_code = 'human_handoff', updated_at = clock_timestamp()
    where tenant_id = p_tenant_id and conversation_id = p_conversation_id
      and state in ('queued', 'leased', 'ready');
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values(p_tenant_id, auth.uid(), 'conversation.handoff_requested', p_conversation_id,
      jsonb_build_object('request_id', p_request_id));
  return p_request_id;
end;
$$;

revoke all on function public.mark_conversation_opened(uuid, uuid) from public, anon;
revoke all on function public.request_conversation_handoff(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.mark_conversation_opened(uuid, uuid) to authenticated;
grant execute on function public.request_conversation_handoff(uuid, uuid, uuid, text) to authenticated;
