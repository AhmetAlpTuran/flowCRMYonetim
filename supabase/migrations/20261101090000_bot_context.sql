alter table public.bot_settings alter column is_active set default false;

alter table public.conversations
  add column last_customer_message_id uuid,
  add column automation_revision bigint not null default 0,
  add constraint conversations_last_customer_message_fk foreign key (tenant_id, last_customer_message_id)
    references public.messages(tenant_id, id) on delete set null (last_customer_message_id);
create index conversations_current_customer_input on public.conversations(tenant_id, last_customer_message_id)
  where last_customer_message_id is not null;

-- A pointer identifies the exact latest input, including messages sharing a timestamp.
update public.conversations c set last_customer_message_id = (
  select m.id from public.messages m
  where m.tenant_id = c.tenant_id and m.conversation_id = c.id
    and m.connection_id = c.connection_id and m.is_from_customer
  order by least(m.sent_at, m.received_at) desc, m.received_at desc, m.id desc limit 1
) where c.connection_id is not null;

create function public.track_conversation_automation_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    new.automation_revision := old.automation_revision + 1;
  end if;
  return new;
end;
$$;
create trigger track_conversation_automation_revision before update on public.conversations
  for each row execute function public.track_conversation_automation_revision();

create function public.track_message_automation_context()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.is_from_customer and new.connection_id is not null then
    update public.conversations set last_customer_message_id = new.id
      where tenant_id = new.tenant_id and id = new.conversation_id and connection_id = new.connection_id
        and (last_customer_message_at is null or least(new.sent_at, new.received_at) >= last_customer_message_at);
  elsif new.sent_by is not null then
    update public.conversations set automation_revision = automation_revision + 1
      where tenant_id = new.tenant_id and id = new.conversation_id;
  end if;
  return new;
end;
$$;
create trigger track_message_automation_context after insert on public.messages
  for each row execute function public.track_message_automation_context();

-- A repeated handoff request retains the same revision because its RPC inserts once.
create function public.track_handoff_automation_context()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.created_by is not null then
    update public.conversations set automation_revision = automation_revision + 1
      where tenant_id = new.tenant_id and id = new.conversation_id;
  end if;
  return new;
end;
$$;
create trigger track_handoff_automation_context after insert on public.handoff_requests
  for each row execute function public.track_handoff_automation_context();

create table public.bot_context_versions (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  revision bigint not null default 1
);
alter table public.bot_context_versions enable row level security;
revoke all on public.bot_context_versions from public, anon, authenticated;
grant all on public.bot_context_versions to service_role;
insert into public.bot_context_versions(tenant_id) select id from public.tenants;

create function public.track_bot_context_version()
returns trigger language plpgsql security definer set search_path = '' as $$
declare affected_tenant uuid;
begin
  if tg_op = 'UPDATE' and new.tenant_id is distinct from old.tenant_id then
    raise exception 'Tenant identity is immutable' using errcode = '42501';
  end if;
  affected_tenant := case when tg_op = 'DELETE' then old.tenant_id else new.tenant_id end;
  -- Tenant deletion can cascade through settings after the tenant row is gone.
  if exists(select 1 from public.tenants where id = affected_tenant) then
    insert into public.bot_context_versions(tenant_id) values(affected_tenant)
      on conflict (tenant_id) do update set revision = bot_context_versions.revision + 1;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger track_bot_settings_context after insert or update or delete on public.bot_settings
  for each row execute function public.track_bot_context_version();
create trigger track_knowledge_context after insert or update or delete on public.knowledge_base
  for each row execute function public.track_bot_context_version();

alter table public.bot_settings add constraint bot_settings_bounds check (
  length(name) between 1 and 80 and length(tone) between 1 and 200 and length(language) between 1 and 80
  and length(system_prompt) between 1 and 8000 and model ~ '^[a-zA-Z0-9_.:-]{1,100}$'
  and temperature between 0 and 2 and memory_hours between 1 and 168 and max_history_messages between 1 and 50
) not valid;
alter table public.knowledge_base add constraint knowledge_content_bounds check (
  length(title) between 1 and 250 and length(content) between 1 and 50000 and cardinality(tags) <= 30
) not valid;
create index knowledge_full_text on public.knowledge_base using gin (
  to_tsvector('simple', left(title, 250) || ' ' || left(content, 50000))
);

create function public.bot_reply_context(p_job_id uuid, p_lease_token uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  job public.bot_reply_jobs;
  conversation public.conversations;
  input_message public.messages;
  settings public.bot_settings;
  context_revision bigint;
  search_query tsquery;
  knowledge jsonb;
  history jsonb;
begin
  perform public.require_service_role();
  select * into job from public.bot_reply_jobs where id = p_job_id and state = 'leased'
    and lease_token = p_lease_token and leased_until > now();
  if not found then return null; end if;
  select * into conversation from public.conversations where tenant_id = job.tenant_id and id = job.conversation_id;
  if not found or conversation.status <> 'open' or conversation.last_customer_message_id is distinct from job.input_message_id then
    return null;
  end if;
  select * into input_message from public.messages where tenant_id = job.tenant_id and id = job.input_message_id
    and conversation_id = job.conversation_id and connection_id = conversation.connection_id and is_from_customer;
  if not found then return null; end if;
  select * into settings from public.bot_settings where tenant_id = job.tenant_id and is_active;
  if not found then return null; end if;
  select revision into context_revision from public.bot_context_versions where tenant_id = job.tenant_id;
  select string_agg(quote_literal(word), ' | ')::tsquery into search_query
    from unnest(tsvector_to_array(to_tsvector('simple', left(input_message.body, 4096)))) as word;
  select coalesce(jsonb_agg(to_jsonb(selected)), '[]'::jsonb) into knowledge from (
    select id, left(title, 250) as title,
      left(ts_headline('simple', left(content, 50000), search_query,
        'MaxWords=250, MinWords=50, MaxFragments=3'), 4000) as content
    from public.knowledge_base where tenant_id = job.tenant_id
      and to_tsvector('simple', left(title, 250) || ' ' || left(content, 50000)) @@ search_query
    order by ts_rank(to_tsvector('simple', left(title, 250) || ' ' || left(content, 50000)), search_query) desc,
      updated_at desc, id limit 5
  ) selected;
  if jsonb_array_length(knowledge) = 0 then
    select coalesce(jsonb_agg(to_jsonb(selected)), '[]'::jsonb) into knowledge from (
      select id, left(title, 250) as title, left(content, 4000) as content
      from public.knowledge_base where tenant_id = job.tenant_id order by updated_at desc, id limit 5
    ) selected;
  end if;
  select coalesce(jsonb_agg(to_jsonb(selected) order by selected.received_at, selected.id), '[]'::jsonb) into history from (
    select id, case when is_from_customer then 'user' else 'assistant' end as role,
      left(body, 2000) as body, received_at
    from public.messages where tenant_id = job.tenant_id and conversation_id = job.conversation_id
      and connection_id = conversation.connection_id and id <> input_message.id
      and received_at <= input_message.received_at
      and received_at >= input_message.received_at - make_interval(hours => greatest(1, least(settings.memory_hours, 168)))
      and (is_from_customer or (outbound_state = 'accepted' and wa_status is distinct from 'failed'))
    order by received_at desc, id desc limit greatest(1, least(settings.max_history_messages, 50))
  ) selected;
  return jsonb_build_object(
    'tenant_id', job.tenant_id, 'conversation_id', conversation.id, 'input_message_id', input_message.id,
    'automation_revision', conversation.automation_revision, 'context_revision', coalesce(context_revision, 0),
    'input', jsonb_build_object('type', input_message.message_type, 'body', input_message.body),
    'settings', jsonb_build_object('name', settings.name, 'tone', settings.tone, 'language', settings.language,
      'system_prompt', settings.system_prompt, 'model', settings.model, 'temperature', settings.temperature),
    'knowledge', knowledge, 'history', history
  );
end;
$$;

revoke all on function public.track_conversation_automation_revision() from public, anon, authenticated;
revoke all on function public.track_message_automation_context() from public, anon, authenticated;
revoke all on function public.track_handoff_automation_context() from public, anon, authenticated;
revoke all on function public.track_bot_context_version() from public, anon, authenticated;
revoke all on function public.bot_reply_context(uuid, uuid) from public, anon, authenticated;
grant execute on function public.bot_reply_context(uuid, uuid) to service_role;
