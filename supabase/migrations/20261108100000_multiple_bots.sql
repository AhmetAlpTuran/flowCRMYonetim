-- Multiple bots per business (roadmap Phase 2g).
--
-- bot_settings stays the business's main bot ("Ana bot"). bot_profiles holds up to ten
-- more bots with their own name, tone, language, instructions and model. Each WhatsApp
-- number uses the main bot unless it is assigned another one, and the bot can be
-- switched off for a single number (humans only). effective_bot_settings resolves the
-- bot of a conversation's number; every bot job function uses it, so a change to a
-- bot or to a number's assignment bumps the bot context version and an in-flight reply
-- hands off instead of answering with stale settings.

create table public.bot_profiles (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null default 'Ava',
  tone text not null default 'Profesyonel ve net',
  language text not null default 'Türkçe',
  system_prompt text not null default 'Kısa, profesyonel bir müşteri temsilcisi gibi yanıt ver.',
  model text not null default 'gpt-4o-mini',
  temperature numeric not null default 0.3,
  memory_hours integer not null default 6,
  max_history_messages integer not null default 12,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint bot_profiles_bounds check (
    length(btrim(name)) between 1 and 80 and length(btrim(tone)) between 1 and 200
    and length(btrim(language)) between 1 and 80 and length(btrim(system_prompt)) between 1 and 8000
    and model ~ '^[a-zA-Z0-9_.:-]{1,100}$' and temperature between 0 and 2
    and memory_hours between 1 and 168 and max_history_messages between 1 and 50)
);
create index bot_profiles_tenant on public.bot_profiles(tenant_id, created_at);
alter table public.bot_profiles enable row level security;
create policy bot_profiles_read on public.bot_profiles for select to authenticated
  using (public.user_has_permission(tenant_id, 'bot'));
revoke insert, update, delete on public.bot_profiles from anon, authenticated;
grant all on public.bot_profiles to service_role;
create trigger track_bot_profile_context after insert or update or delete on public.bot_profiles
  for each row execute function public.track_bot_context_version();

-- Per-number routing: null bot_profile_id = the main bot; bot_enabled = false = humans only.
alter table public.whatsapp_connections
  add column if not exists bot_enabled boolean not null default true,
  add column if not exists bot_profile_id uuid;
alter table public.whatsapp_connections add constraint whatsapp_connections_bot_profile_fkey
  foreign key (tenant_id, bot_profile_id) references public.bot_profiles(tenant_id, id)
  on delete set null (bot_profile_id);
create index whatsapp_connections_bot_profile on public.whatsapp_connections(tenant_id, bot_profile_id)
  where bot_profile_id is not null;

-- Which bot finalized a job (null = the main bot), for per-bot reporting.
alter table public.bot_reply_jobs add column if not exists bot_profile_id uuid;
alter table public.bot_reply_jobs add constraint bot_reply_jobs_bot_profile_fkey
  foreign key (tenant_id, bot_profile_id) references public.bot_profiles(tenant_id, id)
  on delete set null (bot_profile_id);

create function public.track_connection_bot_context()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- A tenant being deleted cascades through here; its version row is going too.
  if (new.bot_enabled is distinct from old.bot_enabled or new.bot_profile_id is distinct from old.bot_profile_id)
    and exists (select 1 from public.tenants where id = new.tenant_id) then
    perform public.bump_bot_context_version(new.tenant_id);
  end if;
  return new;
end;
$$;
create trigger track_connection_bot_context after update of bot_enabled, bot_profile_id
  on public.whatsapp_connections for each row execute function public.track_connection_bot_context();

-- The bot answering on a number, shaped like bot_settings so job functions keep their
-- checks (is_active, name, language, model, memory). No row means no bot there.
-- Conversations without a number (legacy rows) use the main bot.
create function public.effective_bot_settings(p_tenant_id uuid, p_connection_id uuid)
returns setof public.bot_settings language sql stable set search_path = '' as $$
  select s.* from public.bot_settings s
  where s.tenant_id = p_tenant_id
    and (p_connection_id is null or exists (select 1 from public.whatsapp_connections c
      where c.tenant_id = p_tenant_id and c.id = p_connection_id and c.bot_enabled and c.bot_profile_id is null))
  union all
  select p.tenant_id, p.name, p.tone, p.language, p.system_prompt, p.model, p.temperature,
    p.memory_hours, p.max_history_messages, p.is_active, p.created_at, p.updated_at
  from public.whatsapp_connections c
  join public.bot_profiles p on p.tenant_id = c.tenant_id and p.id = c.bot_profile_id
  where c.tenant_id = p_tenant_id and c.id = p_connection_id and c.bot_enabled;
$$;

-- Creates or updates an extra bot under a client-generated stable ID.
create function public.save_bot_profile(
  p_tenant_id uuid, p_profile_id uuid, p_name text, p_tone text, p_language text, p_system_prompt text,
  p_model text, p_temperature numeric, p_memory_hours integer, p_max_history_messages integer, p_is_active boolean
) returns public.bot_profiles language plpgsql security definer set search_path = '' as $$
declare existing public.bot_profiles; saved public.bot_profiles;
begin
  if p_tenant_id is null or p_profile_id is null or not public.user_has_permission(p_tenant_id, 'bot') then
    raise exception 'Bot permission required' using errcode = '42501';
  end if;
  select * into existing from public.bot_profiles where id = p_profile_id for update;
  if found and existing.tenant_id <> p_tenant_id then
    raise exception 'Bot permission required' using errcode = '42501';
  end if;
  begin
    if found then
      update public.bot_profiles set name = btrim(p_name), tone = btrim(p_tone), language = btrim(p_language),
        system_prompt = btrim(p_system_prompt), model = p_model, temperature = p_temperature,
        memory_hours = p_memory_hours, max_history_messages = p_max_history_messages,
        is_active = coalesce(p_is_active, false), updated_at = now()
        where id = p_profile_id returning * into saved;
    else
      perform pg_advisory_xact_lock(hashtext('bot_profiles:' || p_tenant_id::text));
      if (select count(*) from public.bot_profiles where tenant_id = p_tenant_id) >= 10 then
        raise exception 'Bot limit reached' using errcode = 'P0001', hint = 'bot_limit';
      end if;
      insert into public.bot_profiles(id, tenant_id, name, tone, language, system_prompt, model, temperature,
          memory_hours, max_history_messages, is_active)
        values (p_profile_id, p_tenant_id, btrim(p_name), btrim(p_tone), btrim(p_language), btrim(p_system_prompt),
          p_model, p_temperature, p_memory_hours, p_max_history_messages, coalesce(p_is_active, false))
        returning * into saved;
    end if;
  exception when check_violation or not_null_violation then
    raise exception 'Invalid bot settings' using errcode = '22023';
  end;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (p_tenant_id, auth.uid(), 'bot.profile_saved', saved.id,
      jsonb_build_object('name', saved.name, 'is_active', saved.is_active));
  return saved;
end;
$$;

-- Deleting a bot moves its numbers back to the main bot.
create function public.delete_bot_profile(p_tenant_id uuid, p_profile_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare removed public.bot_profiles;
begin
  if p_tenant_id is null or not public.user_has_permission(p_tenant_id, 'bot') then
    raise exception 'Bot permission required' using errcode = '42501';
  end if;
  delete from public.bot_profiles where tenant_id = p_tenant_id and id = p_profile_id returning * into removed;
  if not found then return false; end if;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (p_tenant_id, auth.uid(), 'bot.profile_deleted', removed.id, jsonb_build_object('name', removed.name));
  return true;
end;
$$;

-- Chooses the bot of one WhatsApp number: p_profile_id null = the main bot.
create function public.set_connection_bot(
  p_tenant_id uuid, p_connection_id uuid, p_bot_enabled boolean, p_profile_id uuid default null
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_tenant_id is null or not public.user_has_permission(p_tenant_id, 'bot') then
    raise exception 'Bot permission required' using errcode = '42501';
  end if;
  if p_bot_enabled is null then
    raise exception 'Invalid bot assignment' using errcode = '22023';
  end if;
  if p_profile_id is not null and not exists (
    select 1 from public.bot_profiles where tenant_id = p_tenant_id and id = p_profile_id
  ) then
    raise exception 'Unknown bot' using errcode = '22023';
  end if;
  update public.whatsapp_connections set bot_enabled = p_bot_enabled, bot_profile_id = p_profile_id, updated_at = now()
    where tenant_id = p_tenant_id and id = p_connection_id;
  if not found then return false; end if;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (p_tenant_id, auth.uid(), 'connection.bot_assigned', p_connection_id,
      jsonb_build_object('bot_enabled', p_bot_enabled, 'bot_profile_id', p_profile_id));
  return true;
end;
$$;

revoke all on function public.track_connection_bot_context() from public, anon, authenticated;
revoke all on function public.effective_bot_settings(uuid, uuid) from public, anon, authenticated;
grant execute on function public.effective_bot_settings(uuid, uuid) to service_role;
revoke all on function public.save_bot_profile(uuid, uuid, text, text, text, text, text, numeric, integer, integer, boolean) from public, anon;
revoke all on function public.delete_bot_profile(uuid, uuid) from public, anon;
revoke all on function public.set_connection_bot(uuid, uuid, boolean, uuid) from public, anon;
grant execute on function public.save_bot_profile(uuid, uuid, text, text, text, text, text, numeric, integer, integer, boolean) to authenticated;
grant execute on function public.delete_bot_profile(uuid, uuid) to authenticated;
grant execute on function public.set_connection_bot(uuid, uuid, boolean, uuid) to authenticated;

-- The six functions that checked the tenant's single bot now resolve the bot of the
-- conversation's WhatsApp number. These are the previous definitions with only that
-- lookup changed (and complete_bot_reply recording which bot replied).
CREATE OR REPLACE FUNCTION public.materialize_whatsapp_message(p_event_key text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  event public.whatsapp_webhook_events;
  connection public.whatsapp_connections;
  conversation public.conversations;
  contact public.contacts;
  sender_phone text;
  message_type text;
  message_body text;
  input_id uuid;
  customer_time timestamptz;
  latest_input boolean;
begin
  perform public.require_service_role();
  select * into event from public.whatsapp_webhook_events
    where event_key = p_event_key for update;
  if not found or event.kind <> 'message' then
    raise exception 'Invalid message event' using errcode = '22023';
  end if;
  select * into connection from public.whatsapp_connections
    where waba_id = event.waba_id and phone_number_id = event.phone_number_id for share;
  if not found then return 'unmatched'; end if;
  if event.connection_id is not null and
    (event.connection_id <> connection.id or event.tenant_id <> connection.tenant_id) then
    raise exception 'Event identity changed' using errcode = '55000';
  end if;
  update public.whatsapp_webhook_events
    set tenant_id = connection.tenant_id, connection_id = connection.id
    where event_key = p_event_key;
  if connection.status = 'inactive' then return 'disconnected'; end if;

  sender_phone := event.payload->>'sender_phone';
  message_type := event.payload->>'type';
  if sender_phone is null or sender_phone !~ '^[1-9][0-9]{7,14}$'
    or message_type is null or message_type !~ '^[a-z_]{1,40}$'
    or jsonb_typeof(event.payload->'content') is distinct from 'object' then
    raise exception 'Invalid inbound content' using errcode = '22023';
  end if;
  -- Serialize contact creation across the tenant's business numbers. All materializers
  -- take this lock before a conversation row lock. Hash collisions only serialize work.
  perform pg_advisory_xact_lock(hashtextextended(connection.tenant_id::text || ':' || sender_phone, 0));
  if exists (select 1 from public.messages
    where connection_id = connection.id and wa_message_id = event.provider_message_id) then
    return 'duplicate';
  end if;
  select * into contact from public.contacts
    where tenant_id = connection.tenant_id and public.normalize_campaign_phone(phone) = sender_phone
    order by created_at, id limit 1;
  if not found then
    insert into public.contacts(tenant_id, full_name, phone)
      values(connection.tenant_id, coalesce(nullif(left(btrim(event.payload->>'contact_name'), 256), ''), sender_phone), sender_phone)
      returning * into contact;
  end if;
  insert into public.conversations(tenant_id, connection_id, customer_phone, contact_id, title, status)
    values(connection.tenant_id, connection.id, sender_phone, contact.id, contact.full_name, 'open')
    on conflict (connection_id, customer_phone) where connection_id is not null do nothing;
  select * into conversation from public.conversations
    where connection_id = connection.id and conversations.customer_phone = sender_phone for update;

  message_body := public.whatsapp_message_preview(event.payload);
  -- A provider clock ahead of receipt time must not extend the customer service window.
  customer_time := least(event.occurred_at, event.received_at);
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body,
    is_from_customer, sent_at, received_at, wa_message_id, message_type, provider_content)
    values(connection.tenant_id, conversation.id, connection.id, contact.full_name, message_body,
      true, event.occurred_at, event.received_at, event.provider_message_id, message_type, event.payload->'content')
    returning id into input_id;
  select last_customer_message_id = input_id into latest_input from public.conversations where id = conversation.id;
  update public.conversations set
    unread_count = unread_count + 1,
    last_customer_message_at = greatest(last_customer_message_at, customer_time),
    last_message = case when last_message_at is null or customer_time >= last_message_at then message_body else last_message end,
    last_message_at = greatest(last_message_at, customer_time),
    status = case when status = 'closed' and latest_input then 'open' else status end,
    updated_at = greatest(updated_at, event.received_at)
    where id = conversation.id
    returning * into conversation;

  -- Receiving a support message does not grant marketing consent. Human handoffs
  -- and pending conversations remain under human control. Older delayed inputs
  -- are displayed but do not create a new bot response job.
  if conversation.status = 'open' and latest_input and message_type <> 'reaction'
    and exists (select 1 from public.effective_bot_settings(connection.tenant_id, connection.id) where is_active) then
    insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id)
      values(connection.tenant_id, conversation.id, input_id)
      on conflict (input_message_id) do nothing;
  end if;
  return 'applied';
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_bot_reply()
 RETURNS SETOF bot_reply_jobs
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare conversation public.conversations; job public.bot_reply_jobs; version bigint; active boolean;
begin
  perform public.require_service_role();
  -- One conversation per transaction keeps the lock order independent of tenant
  -- quota buckets. Parallel workers can select other conversations with SKIP LOCKED.
  select c.* into conversation from public.bot_reply_jobs candidate
    join public.conversations c on c.id = candidate.conversation_id and c.tenant_id = candidate.tenant_id
  where ((candidate.state = 'queued' and candidate.available_at <= now())
    or (candidate.state = 'leased' and candidate.leased_until <= now())) and not exists (
    select 1 from public.bot_reply_jobs busy where busy.conversation_id = c.id
      and busy.state = 'leased' and busy.leased_until > now()
  ) order by candidate.created_at, candidate.id limit 1 for update of c skip locked;
  if not found then return; end if;
  for job in select * from public.bot_reply_jobs where conversation_id = conversation.id and tenant_id = conversation.tenant_id
    and state = 'leased' and leased_until <= now() for update loop
    if job.generation_started_at is not null then
      perform public.settle_bot_usage(job.id, job.lease_token);
      perform public.complete_bot_reply(job.id, job.lease_token,
        jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'ai_generation_unknown', 'knowledge_ids', '[]'::jsonb));
    elsif job.attempts >= 3 then
      update public.bot_reply_jobs set prepared_at = now() where id = job.id;
      perform public.complete_bot_reply(job.id, job.lease_token,
        jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'ai_worker_retry_exhausted', 'knowledge_ids', '[]'::jsonb));
    else
      update public.bot_reply_jobs set state = 'queued', lease_token = null, leased_until = null,
        prepared_at = null, available_at = now(), updated_at = now() where id = job.id;
    end if;
  end loop;
  select * into conversation from public.conversations where id = conversation.id;
  select coalesce(is_active, false) into active
    from public.effective_bot_settings(conversation.tenant_id, conversation.connection_id);
  update public.bot_reply_jobs set state = 'cancelled', error_code = 'input_superseded', updated_at = now()
    where conversation_id = conversation.id and tenant_id = conversation.tenant_id and state = 'queued'
      and (input_message_id is distinct from conversation.last_customer_message_id or conversation.status <> 'open' or not coalesce(active, false)
        or not exists (select 1 from public.messages m where m.id = bot_reply_jobs.input_message_id
          and m.tenant_id = conversation.tenant_id and m.conversation_id = conversation.id
          and m.connection_id = conversation.connection_id and m.is_from_customer));
  if conversation.status <> 'open' or not coalesce(active, false) or exists (
    select 1 from public.bot_reply_jobs where conversation_id = conversation.id and state = 'leased'
  ) then return; end if;
  select revision into version from public.bot_context_versions where tenant_id = conversation.tenant_id;
  return query
  update public.bot_reply_jobs j set state = 'leased', lease_token = gen_random_uuid(),
    leased_until = now() + interval '120 seconds', attempts = attempts + 1,
    prepared_at = null, generation_started_at = null,
    automation_revision = conversation.automation_revision, context_revision = version,
    expires_at = least(m.sent_at, m.received_at) + interval '24 hours', updated_at = now()
    from public.messages m where j.conversation_id = conversation.id and j.tenant_id = conversation.tenant_id
      and j.input_message_id = conversation.last_customer_message_id and j.state = 'queued' and j.available_at <= now()
      and j.attempts < 3 and m.id = j.input_message_id and m.tenant_id = j.tenant_id
      and m.conversation_id = j.conversation_id and m.connection_id = conversation.connection_id and m.is_from_customer
    returning j.*;
end;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_bot_reply(p_job_id uuid, p_lease_token uuid, p_automation_revision bigint, p_context_revision bigint, p_model text, p_reserve_tokens integer, p_default_limit bigint)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  job public.bot_reply_jobs;
  conversation public.conversations;
  version bigint;
  period date := date_trunc('month', now() at time zone 'UTC')::date;
  token_limit bigint;
  usage public.tenant_ai_usage;
begin
  perform public.require_service_role();
  if p_reserve_tokens is null or p_reserve_tokens not between 0 and 200000
    or p_default_limit is null or p_default_limit not between 0 and 1000000000000
    or (p_reserve_tokens > 0 and (p_model is null or length(p_model) not between 1 and 100)) then
    raise exception 'Invalid AI reservation' using errcode = '22023';
  end if;
  select * into job from public.bot_reply_jobs where id = p_job_id;
  if not found then return 'stale'; end if;
  select * into conversation from public.conversations where id = job.conversation_id and tenant_id = job.tenant_id for update;
  select * into job from public.bot_reply_jobs where id = p_job_id for update;
  if not found or job.state <> 'leased' or job.lease_token is distinct from p_lease_token or job.leased_until <= clock_timestamp() then
    return 'stale';
  end if;
  if job.prepared_at is not null then return 'already_prepared'; end if;
  select revision into version from public.bot_context_versions where tenant_id = job.tenant_id for share;
  if conversation.status <> 'open' or conversation.last_customer_message_id is distinct from job.input_message_id
    or conversation.automation_revision is distinct from p_automation_revision
    or version is distinct from p_context_revision
    or not exists(select 1 from public.effective_bot_settings(job.tenant_id, conversation.connection_id) where is_active) then
    return 'stale';
  end if;
  update public.bot_reply_jobs set prepared_at = now(), automation_revision = p_automation_revision,
    context_revision = p_context_revision, updated_at = now() where id = job.id;
  if p_reserve_tokens = 0 then return 'prepared'; end if;
  if job.expires_at <= clock_timestamp() then return 'window_closed'; end if;
  select monthly_token_limit into token_limit from public.tenant_ai_limits where tenant_id = job.tenant_id;
  token_limit := coalesce(token_limit, p_default_limit);
  insert into public.tenant_ai_usage(tenant_id, period_start) values(job.tenant_id, period)
    on conflict do nothing;
  select * into usage from public.tenant_ai_usage where tenant_id = job.tenant_id and period_start = period for update;
  if usage.reserved_tokens + usage.consumed_tokens + p_reserve_tokens > token_limit then
    if usage.consumed_tokens + p_reserve_tokens <= token_limit and exists (
      select 1 from public.ai_usage_reservations where tenant_id = job.tenant_id and period_start = period and status = 'reserved'
    ) then return 'quota_pending'; end if;
    return 'quota_exhausted';
  end if;
  insert into public.ai_usage_reservations(tenant_id, job_id, lease_token, period_start, model, reserved_tokens)
    values(job.tenant_id, job.id, p_lease_token, period, p_model, p_reserve_tokens);
  update public.tenant_ai_usage set reserved_tokens = reserved_tokens + p_reserve_tokens, request_count = request_count + 1
    where tenant_id = job.tenant_id and period_start = period;
  update public.bot_reply_jobs set generation_started_at = now(), leased_until = clock_timestamp() + interval '120 seconds',
    updated_at = now() where id = job.id;
  return 'prepared';
end;
$function$;

CREATE OR REPLACE FUNCTION public.bot_reply_context(p_job_id uuid, p_lease_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
  select * into settings from public.effective_bot_settings(job.tenant_id, conversation.connection_id) where is_active;
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
$function$;

CREATE OR REPLACE FUNCTION public.complete_bot_reply(p_job_id uuid, p_lease_token uuid, p_decision jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  job public.bot_reply_jobs;
  conversation public.conversations;
  settings public.bot_settings;
  version bigint;
  decision jsonb := p_decision;
  message_text text;
  source_kind text;
  reason text;
  source_id text;
  buttons jsonb;
  button jsonb;
  profile_id uuid;
begin
  perform public.require_service_role();
  if decision is null or jsonb_typeof(decision) <> 'object'
    or coalesce(decision->>'action', '') not in ('reply', 'handoff')
    or jsonb_typeof(decision->'text') is distinct from 'string'
    or coalesce(decision->>'reason', '') !~ '^[a-z_]{1,100}$'
    or jsonb_typeof(decision->'knowledge_ids') is distinct from 'array'
    or jsonb_array_length(decision->'knowledge_ids') > 5 then
    raise exception 'Invalid bot decision' using errcode = '22023';
  end if;
  select * into job from public.bot_reply_jobs where id = p_job_id;
  if not found then return false; end if;
  select * into conversation from public.conversations where id = job.conversation_id and tenant_id = job.tenant_id for update;
  select * into job from public.bot_reply_jobs where id = p_job_id for update;
  if not found or job.lease_token is distinct from p_lease_token then return false; end if;
  if job.state in ('completed', 'handoff') then return true; end if;
  if job.state <> 'leased' or job.prepared_at is null then return false; end if;
  select * into settings from public.effective_bot_settings(job.tenant_id, conversation.connection_id) where is_active;
  select c.bot_profile_id into profile_id from public.whatsapp_connections c
    where c.tenant_id = job.tenant_id and c.id = conversation.connection_id;
  if not found or conversation.status <> 'open' or conversation.last_customer_message_id is distinct from job.input_message_id
    or conversation.automation_revision is distinct from job.automation_revision then
    update public.bot_reply_jobs set state = 'cancelled', error_code = 'conversation_changed',
      leased_until = null, updated_at = now() where id = job.id;
    return false;
  end if;
  select revision into version from public.bot_context_versions where tenant_id = job.tenant_id for share;
  if version is distinct from job.context_revision then
    decision := jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'bot_configuration_changed', 'knowledge_ids', '[]'::jsonb);
  elsif job.expires_at <= clock_timestamp() then
    decision := jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'customer_service_window_closed', 'knowledge_ids', '[]'::jsonb);
  end if;
  if job.generation_started_at is not null and not exists (
    select 1 from public.ai_usage_reservations where job_id = job.id and lease_token = p_lease_token
      and (status = 'settled' or (status = 'unknown' and decision->>'action' = 'handoff'))
  ) then return false; end if;
  reason := decision->>'reason';
  if decision->>'action' = 'reply' then
    if job.generation_started_at is null or length(btrim(decision->>'text')) not between 1 and 4096
      or reason not in ('knowledge_answer', 'greeting_or_clarification', 'tool_answer')
      or (reason = 'knowledge_answer' and jsonb_array_length(decision->'knowledge_ids') = 0) then
      raise exception 'Invalid bot reply' using errcode = '22023';
    end if;
    for source_id in select jsonb_array_elements_text(decision->'knowledge_ids') loop
      -- Sources are manual entries or passages of the business's documents.
      if source_id !~ '^[0-9a-f-]{36}$' or not (exists (
        select 1 from public.knowledge_base where tenant_id = job.tenant_id and id::text = source_id
      ) or exists (
        select 1 from public.knowledge_chunks where tenant_id = job.tenant_id and document_id is not null
          and id::text = source_id
      )) then raise exception 'Invalid knowledge source' using errcode = '22023'; end if;
    end loop;
    message_text := decision->>'text';
    source_kind := 'bot';
    -- Optional reply buttons (added by the worker for a fresh hold, never by the model):
    -- 1-3 of {id: booking:confirm|cancel:<booking uuid of this conversation>, title}.
    if decision ? 'buttons' then
      buttons := decision->'buttons';
      if jsonb_typeof(buttons) <> 'array' or jsonb_array_length(buttons) not between 1 and 3
        or length(message_text) > 1024 then
        raise exception 'Invalid reply buttons' using errcode = '22023';
      end if;
      for button in select value from jsonb_array_elements(buttons) loop
        if jsonb_typeof(button) <> 'object' or length(coalesce(button->>'title', '')) not between 1 and 20
          or coalesce(button->>'id', '') !~ '^booking:(confirm|cancel):[0-9a-f-]{36}$'
          or not exists (select 1 from public.bookings b where b.tenant_id = job.tenant_id
            and b.conversation_id = conversation.id and b.id::text = split_part(button->>'id', ':', 3)) then
          raise exception 'Invalid reply buttons' using errcode = '22023';
        end if;
      end loop;
    end if;
  else
    if decision->>'text' <> '' or jsonb_array_length(decision->'knowledge_ids') <> 0 then
      raise exception 'Invalid handoff decision' using errcode = '22023';
    end if;
    insert into public.handoff_requests(tenant_id, conversation_id, bot_job_id, note, status)
      values(job.tenant_id, conversation.id, job.id, 'Bot yönlendirmesi (' || reason || ')', 'open');
    update public.conversations set status = 'handoff', updated_at = clock_timestamp()
      where id = conversation.id returning * into conversation;
    message_text := case when lower(settings.language) in ('turkce', 'türkçe', 'tr', 'tr-tr', 'tr_tr')
      then 'Konuşmanızı bir müşteri temsilcisine yönlendirdim.'
      else 'I have passed this conversation to our support team.' end;
    source_kind := 'bot_handoff';
    insert into public.tenant_audit_events(tenant_id, action, resource_id, details)
      values(job.tenant_id, 'conversation.bot_handoff', conversation.id,
        jsonb_build_object('job_id', job.id, 'reason', reason));
  end if;
  -- A handoff remains visible to staff after window expiry, with no out-of-window notice.
  if job.expires_at > clock_timestamp() and conversation.connection_id is not null then
    insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer,
        message_type, provider_content)
      values(job.id, job.tenant_id, conversation.id, conversation.connection_id, settings.name, message_text, false,
        case when buttons is null then 'text' else 'interactive' end,
        case when buttons is null then null else jsonb_build_object('interactive', jsonb_build_object('buttons', buttons)) end);
    insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, source, bot_job_id, expires_at)
      values(job.id, job.tenant_id, conversation.id, conversation.connection_id, conversation.customer_phone,
        source_kind, job.id, job.expires_at);
    update public.conversations set last_message = message_text, last_message_at = clock_timestamp(), updated_at = clock_timestamp()
      where id = conversation.id;
  end if;
  update public.bot_reply_jobs set state = case when source_kind = 'bot' then 'completed' else 'handoff' end,
    output = decision, automation_revision = conversation.automation_revision, context_revision = version,
    bot_profile_id = profile_id,
    leased_until = null, error_code = case when source_kind = 'bot_handoff' then reason else null end,
    updated_at = now() where id = job.id;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.bot_dispatch_allowed(p_job_id uuid, p_tenant_id uuid, p_conversation_id uuid, p_source text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.bot_reply_jobs j
    join public.conversations c on c.id = j.conversation_id and c.tenant_id = j.tenant_id
    join lateral public.effective_bot_settings(j.tenant_id, c.connection_id) s on s.is_active
    join public.bot_context_versions v on v.tenant_id = j.tenant_id
    where j.id = p_job_id and j.tenant_id = p_tenant_id and c.id = p_conversation_id
      and c.automation_revision = j.automation_revision
      and ((p_source = 'bot' and j.state = 'completed' and c.status = 'open'
        and c.last_customer_message_id = j.input_message_id and v.revision = j.context_revision)
        or (p_source = 'bot_handoff' and j.state = 'handoff' and c.status = 'handoff'))
  );
$function$;
