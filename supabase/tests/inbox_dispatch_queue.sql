-- Authored only. Isolated migrated database, deferred verification, no provider calls.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare
  tenant uuid := gen_random_uuid();
  other_tenant uuid := gen_random_uuid();
  actor uuid := gen_random_uuid();
  connection uuid := gen_random_uuid();
  other_connection uuid := gen_random_uuid();
  conversation uuid := gen_random_uuid();
  legacy uuid := gen_random_uuid();
  expired uuid := gen_random_uuid();
  input_id uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values(actor, actor::text || '@example.invalid');
  insert into public.tenants(id, name) values(tenant, 'Outbox A'), (other_tenant, 'Outbox B');
  insert into public.tenant_memberships(tenant_id, user_id, role) values(tenant, actor, 'admin');
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values(connection, tenant, '701', '7010', 'fixture', 'active', now()),
      (other_connection, other_tenant, '702', '7020', 'fixture', 'active', now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values(connection, tenant, 'fixture', repeat('A', 24), repeat('A', 16));
  insert into public.conversations(id, tenant_id, connection_id, customer_phone, title, status, last_customer_message_at)
    values(conversation, tenant, connection, '905550000001', 'Scoped', 'open', now()),
      (expired, tenant, connection, '905550000002', 'Expired', 'open', now() - interval '25 hours');
  insert into public.conversations(id, tenant_id, title, status) values(legacy, tenant, 'Unmapped', 'open');
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values(input_id, tenant, conversation, connection, 'Customer', 'Hello', true);
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id)
    values(tenant, conversation, input_id);
  perform set_config('test.outbox_tenant', tenant::text, true);
  perform set_config('test.outbox_other_tenant', other_tenant::text, true);
  perform set_config('test.outbox_actor', actor::text, true);
  perform set_config('test.outbox_connection', connection::text, true);
  perform set_config('test.outbox_conversation', conversation::text, true);
  perform set_config('test.outbox_legacy', legacy::text, true);
  perform set_config('test.outbox_expired', expired::text, true);
  perform set_config('test.outbox_first', gen_random_uuid()::text, true);
  perform set_config('test.outbox_second', gen_random_uuid()::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.outbox_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
declare
  tenant uuid := current_setting('test.outbox_tenant')::uuid;
  conversation uuid := current_setting('test.outbox_conversation')::uuid;
  first_id uuid := current_setting('test.outbox_first')::uuid;
begin
  perform public.enqueue_inbox_message(tenant, conversation, first_id, 'First');
  perform public.enqueue_inbox_message(tenant, conversation, first_id, 'First');
  perform public.enqueue_inbox_message(tenant, conversation, current_setting('test.outbox_second')::uuid, 'Second');
  if (select count(*) from public.messages where id = first_id) <> 1
    or not exists(select 1 from public.messages where id = first_id and outbound_state = 'queued' and sent_by = auth.uid())
    or not exists(select 1 from public.conversations where id = conversation and status = 'pending') then
    raise exception 'Queue identity, author or human ownership mismatch';
  end if;
  begin
    perform public.enqueue_inbox_message(tenant, conversation, first_id, 'Changed');
    raise exception 'Changed message reused an identity';
  exception when serialization_failure then null; end;
  begin
    perform public.enqueue_inbox_message(tenant, current_setting('test.outbox_legacy')::uuid, gen_random_uuid(), 'Legacy');
    raise exception 'Legacy thread guessed a sending number';
  exception when sqlstate 'P0003' then null; end;
  begin
    perform public.enqueue_inbox_message(tenant, current_setting('test.outbox_expired')::uuid, gen_random_uuid(), 'Expired');
    raise exception 'Closed customer window allowed a reply';
  exception when sqlstate 'P0004' then null; end;
  begin
    perform public.enqueue_inbox_message(current_setting('test.outbox_other_tenant')::uuid, conversation, gen_random_uuid(), 'Cross tenant');
    raise exception 'Cross-tenant enqueue accepted';
  exception when insufficient_privilege then null; end;
  begin
    perform public.enqueue_inbox_message(tenant, conversation, gen_random_uuid(), repeat('A', 4097));
    raise exception 'Oversized text accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform 1 from public.inbox_dispatches;
    raise exception 'Client read private dispatch tokens';
  exception when insufficient_privilege then null; end;
  begin
    update public.messages set outbound_state = 'accepted' where id = first_id;
    raise exception 'Client forged delivery state';
  exception when insufficient_privilege then null; end;
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare
  job public.inbox_dispatches;
  next_job public.inbox_dispatches;
  old_token uuid;
  event jsonb;
  claimed integer;
begin
  if not exists(select 1 from public.bot_reply_jobs where conversation_id = current_setting('test.outbox_conversation')::uuid
    and state = 'cancelled' and error_code = 'human_reply') then
    raise exception 'Human reply did not stop pending bot work';
  end if;
  select * into job from public.claim_inbox_dispatches(10);
  if job.id is distinct from current_setting('test.outbox_first')::uuid then raise exception 'Conversation order was lost'; end if;
  select count(*) into claimed from public.claim_inbox_dispatches(10);
  if claimed <> 0 then raise exception 'Concurrent claim skipped ahead of an active reply'; end if;
  if public.start_inbox_dispatch(job.id, gen_random_uuid()) then raise exception 'Wrong lease started a reply'; end if;
  if not public.start_inbox_dispatch(job.id, job.lease_token) then raise exception 'Valid lease could not start'; end if;
  perform public.finish_inbox_dispatch(job.id, job.lease_token, 'unknown', null, 'transport_outcome_unknown');
  if not exists(select 1 from public.messages where id = job.id and outbound_state = 'unknown' and wa_message_id is null) then
    raise exception 'Unknown result did not reach the inbox';
  end if;
  select * into next_job from public.claim_inbox_dispatches(1);
  if next_job.id is distinct from current_setting('test.outbox_second')::uuid then
    raise exception 'Unknown attempt was resent instead of claiming the next explicit reply';
  end if;
  event := jsonb_build_object('event_key', repeat('7', 64), 'waba_id', '702', 'phone_number_id', '7020',
    'kind', 'status', 'message_id', 'wamid.inbox-fixture', 'occurred_at', now(),
    'payload', jsonb_build_object('status', 'read', 'recipient_phone', '905550000001', 'callback', job.id::text || ':' || job.lease_token::text));
  perform public.ingest_whatsapp_events(jsonb_build_array(event));
  perform public.process_whatsapp_receipts(50);
  if (select state from public.inbox_dispatches where id = job.id) <> 'unknown' then raise exception 'Other tenant receipt matched'; end if;
  event := event || jsonb_build_object('event_key', repeat('8', 64), 'waba_id', '701', 'phone_number_id', '7010');
  perform public.ingest_whatsapp_events(jsonb_build_array(event));
  perform public.process_whatsapp_receipts(50);
  if not exists(select 1 from public.messages where id = job.id and outbound_state = 'accepted' and wa_status = 'read'
    and delivered_at is not null and read_at is not null) then raise exception 'Receipt failed to reconcile the unknown reply'; end if;
  if not public.finish_inbox_dispatch(job.id, job.lease_token, 'accepted', 'wamid.inbox-fixture') then
    raise exception 'Late database acknowledgement was not idempotent';
  end if;
  event := event || jsonb_build_object('event_key', repeat('9', 64), 'payload',
    jsonb_build_object('status', 'failed', 'recipient_phone', '905550000001', 'error_code', 'meta_100'));
  perform public.ingest_whatsapp_events(jsonb_build_array(event));
  perform public.process_whatsapp_receipts(50);
  if (select wa_status from public.messages where id = job.id) <> 'read' then raise exception 'Delayed failure downgraded read'; end if;

  old_token := next_job.lease_token;
  update public.inbox_dispatches set leased_until = now() - interval '1 minute' where id = next_job.id;
  select * into next_job from public.claim_inbox_dispatches(1);
  if next_job.lease_token = old_token or public.start_inbox_dispatch(next_job.id, old_token) then
    raise exception 'Expired lease retained dispatch authority';
  end if;
  perform public.start_inbox_dispatch(next_job.id, next_job.lease_token);
  perform public.finish_inbox_dispatch(next_job.id, next_job.lease_token, 'retry', null, 'meta_130429', 60);
  if not exists(select 1 from public.inbox_dispatches where id = next_job.id and state = 'retry_wait' and attempts = 1
    and available_at >= now() + interval '60 seconds') then raise exception 'Explicit rejection did not back off'; end if;
  update public.inbox_dispatches set available_at = now() - interval '1 second' where id = next_job.id;
  select * into next_job from public.claim_inbox_dispatches(1);
  update public.tenant_memberships set role = 'user', permissions = '{}' where user_id = current_setting('test.outbox_actor')::uuid;
  if public.start_inbox_dispatch(next_job.id, next_job.lease_token) then raise exception 'Revoked employee sent a queued message'; end if;
  if not exists(select 1 from public.messages where id = next_job.id and outbound_state = 'failed'
    and outbound_error_code = 'sender_permission_revoked') then raise exception 'Revocation failure was not surfaced'; end if;
  update public.tenant_memberships set role = 'admin' where user_id = current_setting('test.outbox_actor')::uuid;
  -- Replaying a persisted message remains idempotent even after its window closes.
  update public.conversations set last_customer_message_at = now() - interval '25 hours'
    where id = current_setting('test.outbox_conversation')::uuid;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.outbox_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  perform public.enqueue_inbox_message(current_setting('test.outbox_tenant')::uuid,
    current_setting('test.outbox_conversation')::uuid, current_setting('test.outbox_first')::uuid, 'First');
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
update public.conversations set last_customer_message_at = now()
  where id = current_setting('test.outbox_conversation')::uuid;
select set_config('test.outbox_third', gen_random_uuid()::text, true);
select set_config('test.outbox_fourth', gen_random_uuid()::text, true);
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.outbox_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.enqueue_inbox_message(current_setting('test.outbox_tenant')::uuid,
  current_setting('test.outbox_conversation')::uuid, current_setting('test.outbox_third')::uuid, 'Third');
select public.enqueue_inbox_message(current_setting('test.outbox_tenant')::uuid,
  current_setting('test.outbox_conversation')::uuid, current_setting('test.outbox_fourth')::uuid, 'Fourth');
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare job public.inbox_dispatches; claimed integer;
begin
  -- Credential preparation can fail before start. The claim sweep must still
  -- expire stale replies even if a newer customer message opened a fresh window.
  update public.inbox_dispatches set state = 'blocked', expires_at = now() - interval '1 second'
    where id = current_setting('test.outbox_third')::uuid;
  select * into job from public.claim_inbox_dispatches(1);
  if job.id is distinct from current_setting('test.outbox_fourth')::uuid
    or not exists(select 1 from public.messages where id = current_setting('test.outbox_third')::uuid
      and outbound_state = 'failed' and outbound_error_code = 'customer_service_window_closed') then
    raise exception 'Expired blocked reply held the queue or acquired a new window';
  end if;
  perform public.start_inbox_dispatch(job.id, job.lease_token);
  update public.inbox_dispatches set leased_until = now() - interval '1 minute' where id = job.id;
  select count(*) into claimed from public.claim_inbox_dispatches(10);
  if claimed <> 0 or not exists(select 1 from public.messages where id = job.id and outbound_state = 'unknown') then
    raise exception 'Expired sending attempt was replayed';
  end if;
  if not public.finish_inbox_dispatch(job.id, job.lease_token, 'accepted', 'wamid.inbox-late') then
    raise exception 'Original attempt could not confirm a late acknowledgement';
  end if;
end;
$$;
rollback;
