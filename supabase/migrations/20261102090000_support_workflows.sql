alter table public.conversations
  add column assigned_to uuid,
  add column workflow_revision bigint not null default 0,
  add constraint conversation_assignee_membership_fk foreign key (tenant_id, assigned_to)
    references public.tenant_memberships(tenant_id, user_id) on delete set null (assigned_to);
create index conversations_assignee on public.conversations(tenant_id, assigned_to, updated_at desc);

create table public.support_episodes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  conversation_id uuid not null,
  opened_at timestamptz,
  opened_source text not null check (opened_source in ('customer', 'manual', 'system', 'legacy')),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  resolution_kind text check (resolution_kind in ('human', 'customer', 'automation', 'system')),
  first_human_response_at timestamptz,
  first_human_responder_id uuid references auth.users(id) on delete set null,
  first_bot_response_at timestamptz,
  created_at timestamptz not null default now(),
  unique (tenant_id, conversation_id, id),
  foreign key (tenant_id, conversation_id) references public.conversations(tenant_id, id) on delete cascade,
  check ((resolved_at is null) = (resolution_kind is null))
);
create unique index support_episode_active on public.support_episodes(conversation_id) where resolved_at is null;
create index support_episodes_resolved on public.support_episodes(tenant_id, resolved_at desc);
alter table public.support_episodes enable row level security;
revoke all on public.support_episodes from public, anon, authenticated;
grant select on public.support_episodes to authenticated;
grant all on public.support_episodes to service_role;
create policy support_episodes_read on public.support_episodes for select to authenticated
  using (public.user_has_permission(tenant_id, 'inbox'));

alter table public.messages
  add column support_episode_id uuid,
  add constraint message_support_episode_fk foreign key (tenant_id, conversation_id, support_episode_id)
    references public.support_episodes(tenant_id, conversation_id, id) on delete set null (support_episode_id);
alter table public.handoff_requests
  add column claimed_at timestamptz,
  add column completed_at timestamptz,
  add column completed_by uuid references auth.users(id) on delete set null;

-- Historical start times cannot be inferred from the current conversation status.
insert into public.support_episodes(tenant_id, conversation_id, opened_source)
  select tenant_id, id, 'legacy' from public.conversations where status <> 'closed';

create table public.conversation_actions (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  conversation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  request jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  foreign key (tenant_id, conversation_id) references public.conversations(tenant_id, id) on delete cascade
);
alter table public.conversation_actions enable row level security;
revoke all on public.conversation_actions from public, anon, authenticated;
grant all on public.conversation_actions to service_role;

create function public.latest_actionable_input(p_tenant_id uuid, p_conversation_id uuid, p_time timestamptz, p_type text)
returns boolean language sql stable security invoker set search_path = '' as $$
  select p_type <> 'reaction' and exists (
    select 1 from public.conversations c where c.tenant_id = p_tenant_id and c.id = p_conversation_id
      and not exists (select 1 from public.messages previous
        where previous.id = c.last_customer_message_id and previous.tenant_id = c.tenant_id
          and previous.conversation_id = c.id and least(previous.sent_at, previous.received_at) > p_time)
  );
$$;

create function public.ensure_support_episode(p_tenant_id uuid, p_conversation_id uuid, p_opened_at timestamptz, p_source text)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare episode_id uuid;
begin
  perform 1 from public.conversations where tenant_id = p_tenant_id and id = p_conversation_id for update;
  if not found then raise exception 'Conversation unavailable' using errcode = 'P0002'; end if;
  select id into episode_id from public.support_episodes
    where tenant_id = p_tenant_id and conversation_id = p_conversation_id and resolved_at is null;
  if found then return episode_id; end if;
  insert into public.support_episodes(tenant_id, conversation_id, opened_at, opened_source)
    values(p_tenant_id, p_conversation_id, case when p_opened_at is null then null else least(p_opened_at, clock_timestamp()) end, p_source)
    returning id into episode_id;
  return episode_id;
end;
$$;

create function public.bind_message_support_episode()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare conversation public.conversations;
begin
  if new.support_episode_id is not null then return new; end if;
  select * into conversation from public.conversations where tenant_id = new.tenant_id and id = new.conversation_id for update;
  if not found then return new; end if;
  if new.is_from_customer and new.connection_id is not null and new.connection_id = conversation.connection_id and public.latest_actionable_input(
    new.tenant_id, new.conversation_id, least(new.sent_at, new.received_at), new.message_type
  ) then
    new.support_episode_id := public.ensure_support_episode(new.tenant_id, new.conversation_id, new.received_at, 'customer');
    if conversation.status = 'closed' then
      update public.conversations set status = 'open', assigned_to = null where id = conversation.id;
    end if;
  elsif conversation.status <> 'closed' and new.message_type <> 'reaction' then
    new.support_episode_id := public.ensure_support_episode(new.tenant_id, new.conversation_id,
      case when new.sent_by is not null then clock_timestamp() else null end,
      case when new.sent_by is not null then 'manual' else 'legacy' end);
  else
    select id into new.support_episode_id from public.support_episodes where tenant_id = new.tenant_id
      and conversation_id = new.conversation_id order by resolved_at desc nulls last, created_at desc limit 1;
  end if;
  return new;
end;
$$;
create trigger bind_message_support_episode before insert on public.messages
  for each row execute function public.bind_message_support_episode();

create function public.track_conversation_workflow()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.workflow_revision := old.workflow_revision;
  if new.status is distinct from old.status or new.assigned_to is distinct from old.assigned_to
    or new.last_customer_message_id is distinct from old.last_customer_message_id then
    new.workflow_revision := old.workflow_revision + 1;
  end if;
  return new;
end;
$$;
create trigger track_conversation_workflow before update on public.conversations
  for each row execute function public.track_conversation_workflow();

create or replace function public.track_conversation_automation_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status or new.assigned_to is distinct from old.assigned_to then
    new.automation_revision := old.automation_revision + 1;
  end if;
  return new;
end;
$$;

create function public.sync_support_episode_status()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'closed' and old.status <> 'closed' then
    update public.support_episodes set resolved_at = clock_timestamp(),
      resolved_by = case when auth.role() = 'authenticated' then auth.uid() else null end,
      resolution_kind = case when auth.role() = 'authenticated' then 'human' else 'system' end
      where tenant_id = new.tenant_id and conversation_id = new.id and resolved_at is null;
  elsif old.status = 'closed' and new.status <> 'closed' then
    perform public.ensure_support_episode(new.tenant_id, new.id, clock_timestamp(),
      case when auth.role() = 'authenticated' then 'manual' else 'system' end);
  end if;
  return new;
end;
$$;
create trigger sync_support_episode_status after update on public.conversations
  for each row execute function public.sync_support_episode_status();

create function public.record_support_response()
returns trigger language plpgsql set search_path = '' as $$
declare episode_id uuid; response_at timestamptz;
begin
  if new.state <> 'accepted' or new.accepted_at is null then return new; end if;
  select support_episode_id into episode_id from public.messages where tenant_id = new.tenant_id and id = new.id;
  if episode_id is null then return new; end if;
  response_at := least(new.accepted_at, clock_timestamp());
  if new.source = 'human' then
    update public.support_episodes set
      first_human_responder_id = case when first_human_response_at is null or greatest(opened_at, response_at) < first_human_response_at
        then new.actor_id else first_human_responder_id end,
      first_human_response_at = least(first_human_response_at, greatest(opened_at, response_at))
      where tenant_id = new.tenant_id and conversation_id = new.conversation_id and id = episode_id;
  elsif new.source = 'bot' then
    update public.support_episodes set first_bot_response_at = least(first_bot_response_at, greatest(opened_at, response_at))
      where tenant_id = new.tenant_id and conversation_id = new.conversation_id and id = episode_id;
  end if;
  return new;
end;
$$;
create trigger record_support_response after update on public.inbox_dispatches
  for each row when (new.state = 'accepted' and (old.state is distinct from new.state or old.accepted_at is distinct from new.accepted_at))
  execute function public.record_support_response();

-- Private helper used by authenticated owner RPCs and trusted workers.
create function public.cancel_conversation_automation(p_tenant_id uuid, p_conversation_id uuid, p_reason text)
returns void language sql security invoker set search_path = '' as $$
  update public.bot_reply_jobs set state = 'cancelled', lease_token = null, leased_until = null,
    error_code = left(p_reason, 100), updated_at = now()
    where tenant_id = p_tenant_id and conversation_id = p_conversation_id and state in ('queued', 'leased', 'ready');
  update public.inbox_dispatches set state = 'cancelled', lease_token = null, leased_until = null,
    error_code = left(p_reason, 100), updated_at = now()
    where tenant_id = p_tenant_id and conversation_id = p_conversation_id and source <> 'human'
      and state in ('queued', 'leased', 'retry_wait', 'blocked');
$$;

revoke all on function public.latest_actionable_input(uuid, uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function public.ensure_support_episode(uuid, uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function public.bind_message_support_episode() from public, anon, authenticated;
revoke all on function public.track_conversation_workflow() from public, anon, authenticated;
revoke all on function public.sync_support_episode_status() from public, anon, authenticated;
revoke all on function public.record_support_response() from public, anon, authenticated;
revoke all on function public.cancel_conversation_automation(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.latest_actionable_input(uuid, uuid, timestamptz, text) to service_role;
grant execute on function public.ensure_support_episode(uuid, uuid, timestamptz, text) to service_role;
grant execute on function public.cancel_conversation_automation(uuid, uuid, text) to service_role;

-- Keep case binding and bot input selection on the same ordering rule.
create or replace function public.track_message_automation_context()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.is_from_customer and new.connection_id is not null then
    update public.conversations c set last_customer_message_id = new.id
      where c.tenant_id = new.tenant_id and c.id = new.conversation_id and c.connection_id = new.connection_id
        and public.latest_actionable_input(new.tenant_id, new.conversation_id,
          least(new.sent_at, new.received_at), new.message_type);
  elsif new.sent_by is not null then
    update public.conversations set automation_revision = automation_revision + 1
      where tenant_id = new.tenant_id and id = new.conversation_id;
  end if;
  return new;
end;
$$;

create function public.conversation_team(p_tenant_id uuid)
returns table(user_id uuid, display_name text) language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  return query select m.user_id, coalesce(nullif(left(btrim(p.display_name), 128), ''), 'Üye ' || left(m.user_id::text, 8))
    from public.tenant_memberships m left join public.user_profiles p on p.id = m.user_id
    where m.tenant_id = p_tenant_id and (m.role = 'admin' or 'inbox' = any(m.permissions))
    order by 2, 1;
end;
$$;

create function public.apply_conversation_action(
  p_tenant_id uuid, p_conversation_id uuid, p_request_id uuid,
  p_expected_revision bigint, p_action text, p_assignee_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  conversation public.conversations;
  previous public.conversation_actions;
  action_request jsonb;
  action_result jsonb;
  administrator boolean;
  target_assignee uuid;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  if p_request_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_action is null or p_action not in ('claim', 'assign', 'release', 'resolve', 'reopen')
    or (p_action = 'assign' and p_assignee_id is null)
    or (p_action <> 'assign' and p_assignee_id is not null) then
    raise exception 'Invalid conversation action' using errcode = '22023';
  end if;
  action_request := jsonb_build_object('action', p_action, 'assignee_id', p_assignee_id, 'revision', p_expected_revision);
  select * into conversation from public.conversations
    where tenant_id = p_tenant_id and id = p_conversation_id for update;
  if not found then raise exception 'Conversation unavailable' using errcode = 'P0002'; end if;
  select * into previous from public.conversation_actions where id = p_request_id;
  if found then
    if previous.tenant_id <> p_tenant_id or previous.conversation_id <> p_conversation_id
      or previous.actor_id is distinct from auth.uid() then
      raise exception 'Request identity unavailable' using errcode = '42501';
    end if;
    if previous.request <> action_request then
      raise exception 'Request identity already used' using errcode = '40001';
    end if;
    return previous.result;
  end if;
  if conversation.workflow_revision <> p_expected_revision then
    raise exception 'Conversation changed; refresh before acting' using errcode = '40001';
  end if;
  administrator := coalesce(public.is_tenant_admin(p_tenant_id), false);
  if (p_action = 'assign' and not administrator)
    or (conversation.assigned_to is not null and conversation.assigned_to <> auth.uid() and not administrator) then
    raise exception 'Conversation belongs to another employee' using errcode = '42501';
  end if;
  if (p_action = 'reopen' and conversation.status <> 'closed')
    or (p_action <> 'reopen' and conversation.status = 'closed')
    or (p_action = 'release' and conversation.assigned_to is null) then
    raise exception 'Action unavailable in current conversation state' using errcode = '55000';
  end if;
  -- Enqueue/start and these actions serialize on the conversation row. Workers
  -- can finish a send concurrently, so this may conservatively require a retry.
  if exists(select 1 from public.inbox_dispatches where tenant_id = p_tenant_id
    and conversation_id = p_conversation_id and source = 'human'
    and state in ('queued', 'leased', 'sending', 'retry_wait', 'blocked')) then
    raise exception 'Wait for pending replies or cancel them before changing ownership' using errcode = 'P0006';
  end if;
  target_assignee := case when p_action = 'assign' then p_assignee_id
    when p_action in ('claim', 'reopen') then auth.uid() else conversation.assigned_to end;
  if p_action in ('claim', 'assign', 'reopen') then
    perform 1 from public.tenant_memberships where tenant_id = p_tenant_id and user_id = target_assignee
      and (role = 'admin' or 'inbox' = any(permissions)) for share;
    if not found then raise exception 'Assignee is unavailable' using errcode = '22023'; end if;
  end if;
  perform public.cancel_conversation_automation(p_tenant_id, p_conversation_id, 'human_workflow');
  perform public.ensure_support_episode(p_tenant_id, p_conversation_id, clock_timestamp(), 'manual');
  update public.conversations set
    status = case when p_action = 'resolve' then 'closed' when p_action = 'release' then 'handoff' else 'pending' end,
    assigned_to = case when p_action = 'release' then null else target_assignee end,
    updated_at = clock_timestamp()
    where tenant_id = p_tenant_id and id = p_conversation_id returning * into conversation;
  if p_action = 'resolve' then
    update public.handoff_requests set status = 'done', completed_at = clock_timestamp(), completed_by = auth.uid()
      where tenant_id = p_tenant_id and conversation_id = p_conversation_id and status <> 'done';
  elsif p_action = 'release' then
    update public.handoff_requests set status = 'open', claimed_at = null
      where tenant_id = p_tenant_id and conversation_id = p_conversation_id and status <> 'done';
    if not found then
      insert into public.handoff_requests(tenant_id, conversation_id, status, created_by, note)
        values(p_tenant_id, p_conversation_id, 'open', auth.uid(), 'Temsilci konuşmayı ekibe bıraktı.');
    end if;
  else
    update public.handoff_requests set status = 'in_progress', claimed_at = clock_timestamp()
      where tenant_id = p_tenant_id and conversation_id = p_conversation_id and status <> 'done';
  end if;
  action_result := jsonb_build_object('conversation_id', conversation.id, 'status', conversation.status,
    'assigned_to', conversation.assigned_to, 'workflow_revision', conversation.workflow_revision);
  insert into public.conversation_actions(id, tenant_id, conversation_id, actor_id, request, result)
    values(p_request_id, p_tenant_id, p_conversation_id, auth.uid(), action_request, action_result);
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values(p_tenant_id, auth.uid(), 'conversation.' || p_action, p_conversation_id,
      jsonb_build_object('request_id', p_request_id, 'assigned_to', conversation.assigned_to,
        'workflow_revision', conversation.workflow_revision));
  return action_result;
end;
$$;

create function public.cancel_inbox_message(p_tenant_id uuid, p_conversation_id uuid, p_message_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare dispatch public.inbox_dispatches;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  perform 1 from public.conversations where tenant_id = p_tenant_id and id = p_conversation_id for update;
  if not found then raise exception 'Conversation unavailable' using errcode = 'P0002'; end if;
  select * into dispatch from public.inbox_dispatches
    where tenant_id = p_tenant_id and conversation_id = p_conversation_id and id = p_message_id for update;
  if not found then raise exception 'Message unavailable' using errcode = 'P0002'; end if;
  if dispatch.source <> 'human' or (dispatch.actor_id is distinct from auth.uid()
    and not coalesce(public.is_tenant_admin(p_tenant_id), false)) then
    raise exception 'Message belongs to another employee' using errcode = '42501';
  end if;
  if dispatch.state = 'cancelled' then return true; end if;
  if dispatch.state not in ('queued', 'leased', 'retry_wait', 'blocked') then
    raise exception 'Message can no longer be cancelled' using errcode = '55000';
  end if;
  update public.inbox_dispatches set state = 'cancelled', lease_token = null, leased_until = null,
    error_code = 'cancelled_by_employee', updated_at = clock_timestamp() where id = p_message_id;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id)
    values(p_tenant_id, auth.uid(), 'inbox.message_cancelled', p_message_id);
  return true;
end;
$$;

revoke all on function public.conversation_team(uuid) from public, anon;
revoke all on function public.apply_conversation_action(uuid, uuid, uuid, bigint, text, uuid) from public, anon;
revoke all on function public.cancel_inbox_message(uuid, uuid, uuid) from public, anon;
grant execute on function public.conversation_team(uuid) to authenticated;
grant execute on function public.apply_conversation_action(uuid, uuid, uuid, bigint, text, uuid) to authenticated;
grant execute on function public.cancel_inbox_message(uuid, uuid, uuid) to authenticated;

-- Integrate ownership with the existing enqueue and handoff entry points.
create or replace function public.enqueue_inbox_message(
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
  if conversation.status = 'closed' then
    raise exception 'Reopen the conversation before replying' using errcode = 'P0007';
  end if;
  if conversation.assigned_to is not null and conversation.assigned_to <> auth.uid() then
    raise exception 'Claim the conversation before replying' using errcode = 'P0008';
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
  update public.conversations set status = 'pending', assigned_to = auth.uid(),
    last_message = normalized_body, last_message_at = clock_timestamp(), updated_at = clock_timestamp()
    where id = p_conversation_id;
  update public.handoff_requests set status = 'in_progress', claimed_at = coalesce(claimed_at, clock_timestamp())
    where tenant_id = p_tenant_id and conversation_id = p_conversation_id and status <> 'done';
  perform public.cancel_conversation_automation(p_tenant_id, p_conversation_id, 'human_reply');
  if conversation.assigned_to is null then
    insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
      values(p_tenant_id, auth.uid(), 'conversation.claim', p_conversation_id,
        jsonb_build_object('source', 'human_reply', 'message_id', p_message_id));
  end if;
  return jsonb_build_object('message_id', p_message_id, 'state', 'queued');
end;
$$;

create or replace function public.request_conversation_handoff(
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
  if conversation.status = 'closed' then
    raise exception 'Reopen the conversation before requesting handoff' using errcode = '55000';
  end if;
  if conversation.assigned_to is not null and conversation.assigned_to <> auth.uid()
    and not coalesce(public.is_tenant_admin(p_tenant_id), false) then
    raise exception 'Conversation belongs to another employee' using errcode = '42501';
  end if;
  if exists(select 1 from public.inbox_dispatches where tenant_id = p_tenant_id and conversation_id = p_conversation_id
    and source = 'human' and state in ('queued', 'leased', 'sending', 'retry_wait', 'blocked')) then
    raise exception 'Wait for pending replies or cancel them before handoff' using errcode = 'P0006';
  end if;
  if conversation.status = 'handoff' then
    raise exception 'Conversation already handed off' using errcode = '55000';
  end if;
  perform public.ensure_support_episode(p_tenant_id, p_conversation_id, clock_timestamp(), 'manual');
  insert into public.handoff_requests(id, tenant_id, conversation_id, note, status, created_by)
    values(p_request_id, p_tenant_id, p_conversation_id, normalized_note, 'open', auth.uid());
  update public.conversations set status = 'handoff', assigned_to = null, updated_at = clock_timestamp()
    where id = p_conversation_id and tenant_id = p_tenant_id;
  update public.handoff_requests set status = 'open', claimed_at = null
    where tenant_id = p_tenant_id and conversation_id = p_conversation_id and status <> 'done';
  perform public.cancel_conversation_automation(p_tenant_id, p_conversation_id, 'human_handoff');
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values(p_tenant_id, auth.uid(), 'conversation.handoff_requested', p_conversation_id,
      jsonb_build_object('request_id', p_request_id));
  return p_request_id;
end;
$$;

create or replace function public.start_inbox_dispatch(p_dispatch_id uuid, p_lease_token uuid)
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
  if job.source <> 'human' then
    perform 1 from public.bot_context_versions where tenant_id = job.tenant_id for share;
  end if;
  if conversation.connection_id is distinct from job.connection_id
    or conversation.customer_phone is distinct from job.recipient_phone then
    failure := 'conversation_identity_changed';
  elsif conversation.status = 'closed' then
    failure := 'conversation_closed';
  elsif job.source = 'human' and conversation.assigned_to is not null
    and conversation.assigned_to is distinct from job.actor_id then
    failure := 'conversation_assignee_changed';
  elsif job.source <> 'human' and not public.bot_dispatch_allowed(job.bot_job_id, job.tenant_id, job.conversation_id, job.source) then
    failure := 'bot_ownership_changed';
  elsif job.source = 'human' and not exists (select 1 from public.tenant_memberships where tenant_id = job.tenant_id and user_id = job.actor_id
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
