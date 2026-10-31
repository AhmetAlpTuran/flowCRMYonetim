-- Preserve legacy unscoped conversations. New provider conversations have an
-- immutable business-number/customer identity, independent of CRM phone edits.
alter table public.contacts add constraint contacts_tenant_id_id_key unique (tenant_id, id);
alter table public.conversations add constraint conversations_tenant_id_id_key unique (tenant_id, id);
alter table public.messages add constraint messages_tenant_id_id_key unique (tenant_id, id);

alter table public.conversations
  add column connection_id uuid,
  add column customer_phone text,
  add column last_customer_message_at timestamptz,
  add column last_message_at timestamptz,
  add constraint conversations_connection_tenant_fk foreign key (tenant_id, connection_id)
    references public.whatsapp_connections(tenant_id, id),
  add constraint conversations_contact_tenant_fk foreign key (tenant_id, contact_id)
    references public.contacts(tenant_id, id) not valid,
  add constraint conversations_channel_identity check (
    (connection_id is null and customer_phone is null) or
    (connection_id is not null and customer_phone is not null and customer_phone ~ '^[1-9][0-9]{7,14}$')
  );
create unique index conversations_channel_customer
  on public.conversations(connection_id, customer_phone) where connection_id is not null;
create index contacts_normalized_phone
  on public.contacts(tenant_id, public.normalize_campaign_phone(phone));

alter table public.messages
  add column connection_id uuid,
  add column message_type text not null default 'text',
  add column provider_content jsonb,
  add column received_at timestamptz not null default now(),
  add constraint messages_conversation_tenant_fk foreign key (tenant_id, conversation_id)
    references public.conversations(tenant_id, id) on delete cascade not valid,
  add constraint messages_connection_tenant_fk foreign key (tenant_id, connection_id)
    references public.whatsapp_connections(tenant_id, id);
create unique index messages_connection_provider_id
  on public.messages(connection_id, wa_message_id)
  where connection_id is not null and wa_message_id is not null;

create table public.bot_reply_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  conversation_id uuid not null,
  input_message_id uuid not null unique,
  state text not null default 'queued'
    check (state in ('queued', 'leased', 'ready', 'completed', 'handoff', 'failed', 'cancelled')),
  attempts integer not null default 0 check (attempts between 0 and 3),
  lease_token uuid,
  leased_until timestamptz,
  available_at timestamptz not null default now(),
  output jsonb,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, conversation_id) references public.conversations(tenant_id, id) on delete cascade,
  foreign key (tenant_id, input_message_id) references public.messages(tenant_id, id) on delete cascade,
  check (state <> 'leased' or (lease_token is not null and leased_until is not null))
);
create index bot_reply_jobs_pending on public.bot_reply_jobs(available_at, id) where state = 'queued';
alter table public.bot_reply_jobs enable row level security;
revoke all on public.bot_reply_jobs from public, anon, authenticated;
grant all on public.bot_reply_jobs to service_role;

-- Client inbox edits must never establish a provider identity or customer service
-- window. Legacy human sending remains a separate migration dependency.
create function public.protect_conversation_provider_fields()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.role() = 'service_role' or current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.connection_id is not null or new.customer_phone is not null
      or new.last_customer_message_at is not null or new.last_message_at is not null then
      raise exception 'Provider fields are server managed' using errcode = '42501';
    end if;
  elsif new.tenant_id is distinct from old.tenant_id
    or new.connection_id is distinct from old.connection_id
    or new.customer_phone is distinct from old.customer_phone
    or new.last_customer_message_at is distinct from old.last_customer_message_at
    or new.last_message_at is distinct from old.last_message_at then
    raise exception 'Provider fields are server managed' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger protect_conversation_provider_fields
  before insert or update on public.conversations
  for each row execute function public.protect_conversation_provider_fields();

create function public.protect_inbound_message_fields()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.role() = 'service_role' or current_user not in ('anon', 'authenticated') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op in ('UPDATE', 'DELETE') and
    (old.is_from_customer or old.connection_id is not null or old.provider_content is not null) then
    raise exception 'Provider messages are server managed' using errcode = '42501';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and
    (new.is_from_customer or new.connection_id is not null or new.provider_content is not null) then
    raise exception 'Provider messages are server managed' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger protect_inbound_message_fields
  before insert or update or delete on public.messages
  for each row execute function public.protect_inbound_message_fields();

create function public.whatsapp_message_preview(p_payload jsonb)
returns text language sql immutable set search_path = '' as $$
  select left(coalesce(nullif(case p_payload->>'type'
    when 'text' then p_payload #>> '{content,text,body}'
    when 'image' then p_payload #>> '{content,image,caption}'
    when 'video' then p_payload #>> '{content,video,caption}'
    when 'document' then p_payload #>> '{content,document,caption}'
    when 'button' then p_payload #>> '{content,button,text}'
    when 'interactive' then coalesce(
      p_payload #>> '{content,interactive,button_reply,title}',
      p_payload #>> '{content,interactive,list_reply,title}')
    when 'reaction' then p_payload #>> '{content,reaction,emoji}'
    end, ''), '[' || coalesce(p_payload->>'type', 'message') || ']'), 4096);
$$;

create function public.materialize_whatsapp_message(p_event_key text)
returns text language plpgsql security invoker set search_path = '' as $$
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
  latest_input := conversation.last_customer_message_at is null or customer_time >= conversation.last_customer_message_at;
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body,
    is_from_customer, sent_at, received_at, wa_message_id, message_type, provider_content)
    values(connection.tenant_id, conversation.id, connection.id, contact.full_name, message_body,
      true, event.occurred_at, event.received_at, event.provider_message_id, message_type, event.payload->'content')
    returning id into input_id;
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
  if conversation.status = 'open' and latest_input and message_type in ('text', 'button', 'interactive')
    and exists (select 1 from public.bot_settings where tenant_id = connection.tenant_id and is_active) then
    insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id)
      values(connection.tenant_id, conversation.id, input_id)
      on conflict (input_message_id) do nothing;
  end if;
  return 'applied';
end;
$$;

create function public.process_whatsapp_messages(p_limit integer default 50)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  event public.whatsapp_webhook_events;
  outcome text;
  applied integer := 0;
  deferred integer := 0;
  ignored integer := 0;
  failures integer := 0;
begin
  perform public.require_service_role();
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception 'Invalid batch limit' using errcode = '22023';
  end if;
  for event in select * from public.whatsapp_webhook_events
    where kind = 'message' and state = 'pending' and available_at <= now()
    order by available_at, occurred_at, event_key limit p_limit for update skip locked loop
    begin
      outcome := public.materialize_whatsapp_message(event.event_key);
      if outcome = 'unmatched' then
        update public.whatsapp_webhook_events
          set state = case when received_at < now() - interval '7 days' then 'error' else 'pending' end,
            error_code = 'message_unmatched', available_at = now() + interval '5 minutes', attempts = attempts + 1
          where event_key = event.event_key;
        deferred := deferred + 1;
      else
        update public.whatsapp_webhook_events
          set state = case when outcome = 'disconnected' then 'ignored' else 'applied' end,
            processed_at = now(), error_code = null, attempts = attempts + 1
          where event_key = event.event_key;
        if outcome = 'disconnected' then ignored := ignored + 1;
        else applied := applied + 1; end if;
      end if;
    exception when others then
      -- This block rolls back message, unread and bot-job changes together.
      update public.whatsapp_webhook_events
        set state = case when attempts >= 19 then 'error' else 'pending' end,
          error_code = 'message_processing_failed', attempts = attempts + 1,
          available_at = now() + interval '5 minutes'
        where event_key = event.event_key;
      failures := failures + 1;
    end;
  end loop;
  return jsonb_build_object('applied', applied, 'deferred', deferred, 'ignored', ignored, 'failed', failures);
end;
$$;

revoke all on function public.protect_conversation_provider_fields() from public, anon, authenticated;
revoke all on function public.protect_inbound_message_fields() from public, anon, authenticated;
revoke all on function public.whatsapp_message_preview(jsonb) from public, anon, authenticated;
revoke all on function public.materialize_whatsapp_message(text) from public, anon, authenticated;
revoke all on function public.process_whatsapp_messages(integer) from public, anon, authenticated;
grant execute on function public.whatsapp_message_preview(jsonb) to service_role;
grant execute on function public.materialize_whatsapp_message(text) to service_role;
grant execute on function public.process_whatsapp_messages(integer) to service_role;
