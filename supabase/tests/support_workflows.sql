-- Authored only. Execute on an isolated migrated database during verification.
-- Concurrent-session coverage is specified in docs/SUPPORT_WORKFLOWS.md.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare
  tenant uuid := gen_random_uuid();
  other_tenant uuid := gen_random_uuid();
  actor uuid := gen_random_uuid();
  colleague uuid := gen_random_uuid();
  administrator uuid := gen_random_uuid();
  connection uuid := gen_random_uuid();
  conversation uuid := gen_random_uuid();
  input_id uuid := gen_random_uuid();
  bot_message uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values(actor, actor::text || '@example.invalid'),
    (colleague, colleague::text || '@example.invalid'), (administrator, administrator::text || '@example.invalid');
  insert into public.tenants(id, name) values(tenant, 'Support A'), (other_tenant, 'Support B');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (tenant, actor, 'user', array['inbox', 'handoff']), (tenant, colleague, 'user', array['inbox']),
    (tenant, administrator, 'admin', array[]::text[]);
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values(connection, tenant, '801', '8010', 'fixture', 'active', now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values(connection, tenant, 'fixture', repeat('A', 24), repeat('A', 16));
  insert into public.conversations(id, tenant_id, connection_id, customer_phone, title, status, last_customer_message_at)
    values(conversation, tenant, connection, '905550000081', 'Support', 'open', now());
  -- A reaction arriving first must not manufacture a case with an unknown start.
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer, message_type)
    values(tenant, conversation, connection, 'Customer', 'Reaction', true, 'reaction');
  if exists(select 1 from public.support_episodes where conversation_id = conversation) then
    raise exception 'Reaction created a support episode';
  end if;
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values(input_id, tenant, conversation, connection, 'Customer', 'Help', true);
  if not exists(select 1 from public.support_episodes where conversation_id = conversation
    and opened_source = 'customer' and opened_at is not null and resolved_at is null) then
    raise exception 'Actionable message did not create a timed case';
  end if;
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id) values(tenant, conversation, input_id);
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values(bot_message, tenant, conversation, connection, 'Bot', 'Prepared reply', false);
  insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone,
    source, state, lease_token, leased_until, expires_at)
    values(bot_message, tenant, conversation, connection, '905550000081', 'bot', 'leased', gen_random_uuid(),
      now() + interval '2 minutes', now() + interval '24 hours');
  perform set_config('test.support_tenant', tenant::text, true);
  perform set_config('test.support_other_tenant', other_tenant::text, true);
  perform set_config('test.support_actor', actor::text, true);
  perform set_config('test.support_colleague', colleague::text, true);
  perform set_config('test.support_admin', administrator::text, true);
  perform set_config('test.support_conversation', conversation::text, true);
  perform set_config('test.support_connection', connection::text, true);
  perform set_config('test.support_message', gen_random_uuid()::text, true);
  perform set_config('test.support_late_message', gen_random_uuid()::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.support_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  tenant uuid := current_setting('test.support_tenant')::uuid;
  conversation uuid := current_setting('test.support_conversation')::uuid;
  request uuid := gen_random_uuid();
  revision bigint;
  result jsonb;
  message_id uuid := current_setting('test.support_message')::uuid;
begin
  if (select count(*) from public.conversation_team(tenant)) <> 3 then raise exception 'Team lookup omitted eligible members'; end if;
  begin
    perform public.conversation_team(current_setting('test.support_other_tenant')::uuid);
    raise exception 'Team lookup crossed tenants';
  exception when insufficient_privilege then null; end;
  select workflow_revision into revision from public.conversations where id = conversation;
  result := public.apply_conversation_action(tenant, conversation, request, revision, 'claim');
  if result->>'assigned_to' <> auth.uid()::text or result->>'status' <> 'pending' then raise exception 'Claim failed'; end if;
  if public.apply_conversation_action(tenant, conversation, request, revision, 'claim') <> result then
    raise exception 'Action retry did not preserve its result';
  end if;
  begin
    perform public.apply_conversation_action(tenant, conversation, request, revision, 'release');
    raise exception 'Changed action reused the request identity';
  exception when serialization_failure then null; end;
  begin
    perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'resolve');
    raise exception 'Stale revision resolved a conversation';
  exception when serialization_failure then null; end;
  select workflow_revision into revision from public.conversations where id = conversation;
  begin
    perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'assign', current_setting('test.support_colleague')::uuid);
    raise exception 'Regular agent assigned another employee';
  exception when insufficient_privilege then null; end;
  perform public.enqueue_inbox_message(tenant, conversation, message_id, 'Reply');
  select workflow_revision into revision from public.conversations where id = conversation;
  begin
    perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'resolve');
    raise exception 'Pending human reply allowed resolution';
  exception when sqlstate 'P0006' then null; end;
  begin
    perform public.request_conversation_handoff(tenant, conversation, gen_random_uuid(), 'Transfer');
    raise exception 'Pending human reply allowed handoff';
  exception when sqlstate 'P0006' then null; end;
  perform public.cancel_inbox_message(tenant, conversation, message_id);
  perform public.cancel_inbox_message(tenant, conversation, message_id);
  if not exists(select 1 from public.messages where id = message_id and outbound_state = 'cancelled') then
    raise exception 'Cancellation was not published';
  end if;
  perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'release');
  if not exists(select 1 from public.handoff_requests where conversation_id = conversation and status = 'open') then
    raise exception 'Released conversation is missing from handoff queue';
  end if;
  -- The normal send entry point claims an unassigned thread.
  perform public.enqueue_inbox_message(tenant, conversation, current_setting('test.support_late_message')::uuid, 'Later receipt');
  if not exists(select 1 from public.conversations where id = conversation and assigned_to = auth.uid() and status = 'pending') then
    raise exception 'Human send failed to claim conversation';
  end if;
  begin
    update public.conversations set assigned_to = null where id = conversation;
    raise exception 'Direct client assignment succeeded';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from public.conversation_actions;
    raise exception 'Client read private action ledger';
  exception when insufficient_privilege then null; end;
  begin
    update public.support_episodes set resolved_at = now(), resolution_kind = 'human' where conversation_id = conversation;
    raise exception 'Client forged support timing';
  exception when insufficient_privilege then null; end;
end;
$$;

select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.support_colleague'))::text, true);
do $$
declare tenant uuid := current_setting('test.support_tenant')::uuid;
  conversation uuid := current_setting('test.support_conversation')::uuid;
  revision bigint;
begin
  select workflow_revision into revision from public.conversations where id = conversation;
  begin
    perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'claim');
    raise exception 'Agent stole an assigned conversation';
  exception when insufficient_privilege then null; end;
  begin
    perform public.enqueue_inbox_message(tenant, conversation, gen_random_uuid(), 'Competing reply');
    raise exception 'Another agent interleaved a reply';
  exception when sqlstate 'P0008' then null; end;
  begin
    perform public.cancel_inbox_message(tenant, conversation, current_setting('test.support_late_message')::uuid);
    raise exception 'Agent cancelled another employee message';
  exception when insufficient_privilege then null; end;
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
-- Simulate an uncertain transport outcome without invoking an external service.
update public.inbox_dispatches set state = 'unknown', lease_token = gen_random_uuid(), dispatch_started_at = clock_timestamp()
  where id = current_setting('test.support_late_message')::uuid;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.support_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
declare tenant uuid := current_setting('test.support_tenant')::uuid;
  conversation uuid := current_setting('test.support_conversation')::uuid;
  revision bigint;
begin
  begin
    perform public.cancel_inbox_message(tenant, conversation, current_setting('test.support_late_message')::uuid);
    raise exception 'Uncertain external send was recalled';
  exception when object_not_in_prerequisite_state then null; end;
  select workflow_revision into revision from public.conversations where id = conversation;
  perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'resolve');
  if not exists(select 1 from public.support_episodes where conversation_id = conversation and resolved_by = auth.uid()
    and resolution_kind = 'human' and resolved_at is not null) then raise exception 'Resolution attribution missing'; end if;
  begin
    perform public.enqueue_inbox_message(tenant, conversation, gen_random_uuid(), 'Closed');
    raise exception 'Closed conversation reopened implicitly on human reply';
  exception when sqlstate 'P0007' then null; end;
  select workflow_revision into revision from public.conversations where id = conversation;
  perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'reopen');
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare tenant uuid := current_setting('test.support_tenant')::uuid;
  conversation uuid := current_setting('test.support_conversation')::uuid;
  message_id uuid := current_setting('test.support_late_message')::uuid;
  original_episode uuid;
begin
  select support_episode_id into original_episode from public.messages where id = message_id;
  update public.inbox_dispatches set state = 'accepted', accepted_at = clock_timestamp() where id = message_id;
  if not exists(select 1 from public.support_episodes where id = original_episode and resolved_at is not null
    and first_human_response_at is not null and first_human_responder_id = current_setting('test.support_actor')::uuid) then
    raise exception 'Late acceptance lost its original case';
  end if;
  if (select count(*) from public.support_episodes where conversation_id = conversation) <> 2
    or exists(select 1 from public.support_episodes where conversation_id = conversation
      and resolved_at is null and first_human_response_at is not null) then
    raise exception 'Reopen overwrote history or late response polluted new case';
  end if;
  if not exists(select 1 from public.bot_reply_jobs where conversation_id = conversation and state = 'cancelled') then
    raise exception 'Claim left bot generation active';
  end if;
  if not exists(select 1 from public.inbox_dispatches where conversation_id = conversation and source = 'bot'
    and state = 'cancelled' and lease_token is null and leased_until is null) then
    raise exception 'Claim left prepared bot transport active';
  end if;
  update public.conversations set status = 'closed' where id = conversation;
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values(tenant, conversation, current_setting('test.support_connection')::uuid, 'Customer', 'New issue', true);
  if not exists(select 1 from public.conversations where id = conversation and status = 'open' and assigned_to is null)
    or not exists(select 1 from public.support_episodes where conversation_id = conversation
      and resolved_at is null and opened_source = 'customer') then
    raise exception 'New customer case retained a closed case owner';
  end if;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.support_admin'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
declare tenant uuid := current_setting('test.support_tenant')::uuid;
  conversation uuid := current_setting('test.support_conversation')::uuid;
  revision bigint;
begin
  select workflow_revision into revision from public.conversations where id = conversation;
  perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'assign', current_setting('test.support_colleague')::uuid);
  if not exists(select 1 from public.conversations where id = conversation
    and assigned_to = current_setting('test.support_colleague')::uuid and status = 'pending') then
    raise exception 'Administrator could not assign an eligible employee';
  end if;
  begin
    perform public.enqueue_inbox_message(tenant, conversation, gen_random_uuid(), 'Admin without takeover');
    raise exception 'Admin silently interleaved an assigned conversation';
  exception when sqlstate 'P0008' then null; end;
  select workflow_revision into revision from public.conversations where id = conversation;
  begin
    perform public.apply_conversation_action(tenant, conversation, gen_random_uuid(), revision, 'assign', gen_random_uuid());
    raise exception 'Assigned an ineligible user';
  exception when invalid_parameter_value then null; end;
end;
$$;
reset role;
rollback;
