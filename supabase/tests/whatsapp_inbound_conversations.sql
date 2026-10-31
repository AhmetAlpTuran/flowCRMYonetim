-- Authored regression fixtures. Execute only in the agreed verification phase,
-- against an isolated migrated database. No external calls. All changes roll back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.inbound_event(
  p_key integer, p_waba text, p_number text, p_message text,
  p_time timestamptz, p_type text default 'text', p_body text default 'Hello'
) returns jsonb language sql as $$
  select jsonb_build_object(
    'event_key', lpad(to_hex(p_key), 64, '0'),
    'waba_id', p_waba, 'phone_number_id', p_number,
    'kind', 'message', 'message_id', p_message, 'occurred_at', p_time,
    'payload', jsonb_build_object('sender_phone', '905550000001',
      'contact_name', 'Provider name', 'type', p_type,
      'content', jsonb_build_object('id', p_message, 'type', p_type,
        'text', jsonb_build_object('body', p_body))))
$$;

do $$
declare
  tenant_a uuid := gen_random_uuid();
  tenant_b uuid := gen_random_uuid();
  actor_a uuid := gen_random_uuid();
  actor_b uuid := gen_random_uuid();
  number_a uuid := gen_random_uuid();
  number_a2 uuid := gen_random_uuid();
  number_b uuid := gen_random_uuid();
  legacy_id uuid := gen_random_uuid();
  conversation public.conversations;
  event jsonb;
  result jsonb;
  metadata jsonb := '{"display_phone_number":"fixture","token_expires_at":null}';
  credential jsonb := jsonb_build_object('key_id', 'fixture', 'ciphertext', repeat('A', 24), 'iv', repeat('A', 16));
begin
  insert into auth.users(id, email) values
    (actor_a, actor_a::text || '@example.invalid'), (actor_b, actor_b::text || '@example.invalid');
  insert into public.tenants(id, name) values(tenant_a, 'Inbound A'), (tenant_b, 'Inbound B');
  insert into public.tenant_memberships(tenant_id, user_id, role) values
    (tenant_a, actor_a, 'admin'), (tenant_b, actor_b, 'admin');
  perform public.save_whatsapp_connection(tenant_a, actor_a, number_a, '601', '6010', metadata, credential, true);
  perform public.save_whatsapp_connection(tenant_a, actor_a, number_a2, '601', '6011', metadata, credential, false);
  perform public.save_whatsapp_connection(tenant_b, actor_b, number_b, '602', '6020', metadata, credential, true);
  insert into public.bot_settings(tenant_id, is_active) values(tenant_a, true), (tenant_b, false);
  insert into public.contacts(tenant_id, full_name, phone) values(tenant_a, 'CRM name', '+90 (555) 000 00 01');
  insert into public.conversations(id, tenant_id, title, status) values(legacy_id, tenant_a, 'Legacy thread', 'open');

  event := pg_temp.inbound_event(1, '601', '6010', 'wamid.inbound-first', now() - interval '1 hour');
  perform public.ingest_whatsapp_events(jsonb_build_array(event));
  result := public.process_whatsapp_messages(50);
  select * into conversation from public.conversations where connection_id = number_a;
  if conversation.id is null or conversation.unread_count <> 1 or conversation.last_message <> 'Hello'
    or conversation.title <> 'CRM name' then
    raise exception 'Inbound message did not create the expected scoped conversation';
  end if;
  if (select count(*) from public.contacts where tenant_id = tenant_a) <> 1 then
    raise exception 'Formatted existing phone created a duplicate contact';
  end if;
  if (select count(*) from public.bot_reply_jobs where conversation_id = conversation.id) <> 1 then
    raise exception 'Active bot did not receive exactly one input job';
  end if;
  -- Retry ingestion and application separately, including a second event key for
  -- the same provider identity. Message-level dedup must still prevent side effects.
  perform public.ingest_whatsapp_events(jsonb_build_array(event));
  perform public.materialize_whatsapp_message(event->>'event_key');
  event := event || jsonb_build_object('event_key', lpad(to_hex(2), 64, '0'));
  perform public.ingest_whatsapp_events(jsonb_build_array(event));
  perform public.process_whatsapp_messages(50);
  if (select unread_count from public.conversations where id = conversation.id) <> 1
    or (select count(*) from public.messages where conversation_id = conversation.id) <> 1
    or (select count(*) from public.bot_reply_jobs where conversation_id = conversation.id) <> 1 then
    raise exception 'Duplicate event changed message, unread or bot counts';
  end if;

  -- Same customer and provider ID on another business number must stay separate.
  perform public.ingest_whatsapp_events(jsonb_build_array(
    pg_temp.inbound_event(3, '601', '6011', 'wamid.inbound-first', now() - interval '1 hour'),
    pg_temp.inbound_event(4, '602', '6020', 'wamid.inbound-first', now() - interval '1 hour')));
  perform public.process_whatsapp_messages(50);
  if (select count(*) from public.conversations where tenant_id = tenant_a and connection_id is not null) <> 2
    or (select count(*) from public.conversations where tenant_id = tenant_b) <> 1
    or (select count(*) from public.contacts where tenant_id = tenant_a) <> 1 then
    raise exception 'Business numbers or tenants were merged';
  end if;
  if exists(select 1 from public.bot_reply_jobs where tenant_id = tenant_b) then
    raise exception 'Inactive bot received an input job';
  end if;
  if exists(select 1 from public.consented_contacts where tenant_id in (tenant_a, tenant_b)) then
    raise exception 'Support message implicitly granted marketing consent';
  end if;
  if not exists(select 1 from public.conversations where id = legacy_id and connection_id is null and unread_count = 0) then
    raise exception 'Legacy thread was silently reassigned';
  end if;

  update public.conversations set status = 'handoff' where id = conversation.id;
  perform public.ingest_whatsapp_events(jsonb_build_array(
    pg_temp.inbound_event(5, '601', '6010', 'wamid.inbound-handoff', now() - interval '20 minutes', 'text', 'Human please')));
  perform public.process_whatsapp_messages(50);
  if not exists(select 1 from public.conversations where id = conversation.id and status = 'handoff' and unread_count = 2)
    or (select count(*) from public.bot_reply_jobs where conversation_id = conversation.id) <> 1 then
    raise exception 'Incoming message resumed the bot during handoff';
  end if;
  update public.conversations set status = 'pending' where id = conversation.id;
  perform public.ingest_whatsapp_events(jsonb_build_array(
    pg_temp.inbound_event(6, '601', '6010', 'wamid.inbound-pending', now() - interval '10 minutes', 'text', 'Latest')));
  perform public.process_whatsapp_messages(50);
  if not exists(select 1 from public.conversations where id = conversation.id and status = 'pending') then
    raise exception 'Incoming message reset pending status';
  end if;
  update public.conversations set status = 'open' where id = conversation.id;
  perform public.ingest_whatsapp_events(jsonb_build_array(
    pg_temp.inbound_event(7, '601', '6010', 'wamid.inbound-delayed', now() - interval '30 minutes', 'text', 'Older')));
  perform public.process_whatsapp_messages(50);
  if (select last_message from public.conversations where id = conversation.id) <> 'Latest'
    or (select count(*) from public.bot_reply_jobs where conversation_id = conversation.id) <> 1 then
    raise exception 'Older input replaced the preview or created a stale bot job';
  end if;
  update public.conversations set status = 'closed' where id = conversation.id;
  perform public.ingest_whatsapp_events(jsonb_build_array(
    pg_temp.inbound_event(8, '601', '6010', 'wamid.inbound-future', now() + interval '2 hours')));
  perform public.process_whatsapp_messages(50);
  if not exists(select 1 from public.conversations where id = conversation.id and status = 'open' and last_customer_message_at <= now()) then
    raise exception 'New input did not reopen or extended the service window using a future provider timestamp';
  end if;

  perform public.ingest_whatsapp_events(jsonb_build_array(
    pg_temp.inbound_event(9, '999', '9990', 'wamid.inbound-unmatched', now())));
  perform public.process_whatsapp_messages(50);
  if not exists(select 1 from public.whatsapp_webhook_events where event_key = lpad(to_hex(9), 64, '0')
    and tenant_id is null and state = 'pending' and error_code = 'message_unmatched') then
    raise exception 'Unknown account was not deferred';
  end if;
  perform public.disconnect_whatsapp_connection(tenant_b, actor_b, number_b);
  perform public.ingest_whatsapp_events(jsonb_build_array(
    pg_temp.inbound_event(10, '602', '6020', 'wamid.inbound-disconnected', now())));
  perform public.process_whatsapp_messages(50);
  if not exists(select 1 from public.whatsapp_webhook_events where event_key = lpad(to_hex(10), 64, '0') and state = 'ignored')
    or exists(select 1 from public.messages where wa_message_id = 'wamid.inbound-disconnected') then
    raise exception 'Disconnected account materialized another message';
  end if;
  if public.whatsapp_message_preview('{"type":"image","content":{"image":{"caption":"Photo"}}}') <> 'Photo'
    or public.whatsapp_message_preview('{"type":"audio","content":{}}') <> '[audio]'
    or public.whatsapp_message_preview('{"type":"interactive","content":{"interactive":{"button_reply":{"title":"Yes"}}}}') <> 'Yes' then
    raise exception 'Structured message preview mismatch';
  end if;
  begin
    insert into public.conversations(tenant_id, title, status, connection_id)
      values(tenant_a, 'Invalid null phone', 'open', number_a);
    raise exception 'Partial channel identity accepted';
  exception when check_violation then null; end;
  begin
    insert into public.messages(tenant_id, conversation_id, sender, body)
      values(tenant_b, conversation.id, 'Invalid', 'Cross-tenant');
    raise exception 'Cross-tenant message reference accepted';
  exception when foreign_key_violation then null; end;

  perform set_config('test.inbound_actor', actor_a::text, true);
  perform set_config('test.inbound_tenant', tenant_a::text, true);
  perform set_config('test.inbound_other_tenant', tenant_b::text, true);
  perform set_config('test.inbound_conversation', conversation.id::text, true);
end;
$$;

-- Force a failure after the message/unread writes. The event's subtransaction
-- must roll back every effect and remain retryable with a sanitized error code.
create function pg_temp.reject_bot_job() returns trigger language plpgsql as $$
begin
  if new.tenant_id = current_setting('test.inbound_tenant')::uuid then
    raise exception 'Fixture failure with private content';
  end if;
  return new;
end;
$$;
create trigger inbound_fixture_failure before insert on public.bot_reply_jobs
  for each row execute function pg_temp.reject_bot_job();
do $$
declare previous_unread integer;
begin
  select unread_count into previous_unread from public.conversations where id = current_setting('test.inbound_conversation')::uuid;
  perform public.ingest_whatsapp_events(jsonb_build_array(
    pg_temp.inbound_event(11, '601', '6010', 'wamid.inbound-rollback', now())));
  perform public.process_whatsapp_messages(50);
  if exists(select 1 from public.messages where wa_message_id = 'wamid.inbound-rollback')
    or (select unread_count from public.conversations where id = current_setting('test.inbound_conversation')::uuid) <> previous_unread
    or not exists(select 1 from public.whatsapp_webhook_events where event_key = lpad(to_hex(11), 64, '0')
      and state = 'pending' and error_code = 'message_processing_failed' and attempts = 1) then
    raise exception 'Partial event effects survived a bot-job failure';
  end if;
end;
$$;
drop trigger inbound_fixture_failure on public.bot_reply_jobs;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.inbound_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if exists(select 1 from public.conversations where tenant_id = current_setting('test.inbound_other_tenant')::uuid)
    or exists(select 1 from public.messages where tenant_id = current_setting('test.inbound_other_tenant')::uuid) then
    raise exception 'Inbox RLS exposed another tenant';
  end if;
  begin
    perform public.process_whatsapp_messages(50);
    raise exception 'Client invoked inbound processor';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from public.bot_reply_jobs;
    raise exception 'Client read private bot jobs';
  exception when insufficient_privilege then null; end;
  begin
    update public.conversations set last_customer_message_at = now() + interval '1 day'
      where id = current_setting('test.inbound_conversation')::uuid;
    raise exception 'Client forged the customer service window';
  exception when insufficient_privilege then null; end;
  begin
    update public.messages set body = 'Rewritten customer input' where wa_message_id = 'wamid.inbound-first';
    raise exception 'Client rewrote verified customer input';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.messages(tenant_id, conversation_id, sender, body, is_from_customer)
      values(current_setting('test.inbound_tenant')::uuid, current_setting('test.inbound_conversation')::uuid, 'Forged', 'Input', true);
    raise exception 'Client forged a customer message';
  exception when insufficient_privilege then null; end;
end;
$$;
rollback;
