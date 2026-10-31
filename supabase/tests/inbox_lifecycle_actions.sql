-- Authored only. Run in an isolated migrated database during verification.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare
  tenant_a uuid := gen_random_uuid();
  tenant_b uuid := gen_random_uuid();
  actor uuid := gen_random_uuid();
  reader uuid := gen_random_uuid();
  conversation_a uuid := gen_random_uuid();
  conversation_b uuid := gen_random_uuid();
  input_id uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values
    (actor, actor::text || '@example.invalid'), (reader, reader::text || '@example.invalid');
  insert into public.tenants(id, name) values(tenant_a, 'Lifecycle A'), (tenant_b, 'Lifecycle B');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (tenant_a, actor, 'user', array['inbox', 'handoff']), (tenant_a, reader, 'user', array['inbox']);
  insert into public.conversations(id, tenant_id, title, status, unread_count) values
    (conversation_a, tenant_a, 'Lifecycle A', 'open', 3), (conversation_b, tenant_b, 'Lifecycle B', 'open', 1);
  insert into public.messages(id, tenant_id, conversation_id, sender, body, is_from_customer)
    values(input_id, tenant_a, conversation_a, 'Customer', 'Help', true);
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id, state, lease_token, leased_until)
    values(tenant_a, conversation_a, input_id, 'leased', gen_random_uuid(), now() + interval '1 minute');
  perform set_config('test.lifecycle_tenant', tenant_a::text, true);
  perform set_config('test.lifecycle_other_tenant', tenant_b::text, true);
  perform set_config('test.lifecycle_actor', actor::text, true);
  perform set_config('test.lifecycle_reader', reader::text, true);
  perform set_config('test.lifecycle_conversation', conversation_a::text, true);
  perform set_config('test.lifecycle_other_conversation', conversation_b::text, true);
  perform set_config('test.lifecycle_request', gen_random_uuid()::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.lifecycle_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
declare
  tenant uuid := current_setting('test.lifecycle_tenant')::uuid;
  conversation uuid := current_setting('test.lifecycle_conversation')::uuid;
  request uuid := current_setting('test.lifecycle_request')::uuid;
begin
  perform public.mark_conversation_opened(tenant, conversation);
  if not exists(select 1 from public.conversations where id = conversation and unread_count = 0
    and last_opened_by = auth.uid() and last_opened_role = 'user' and last_opened_at is not null) then
    raise exception 'Open marker did not use the authenticated employee';
  end if;
  perform public.request_conversation_handoff(tenant, conversation, request, '  Follow up  ');
  perform public.request_conversation_handoff(tenant, conversation, request, 'Follow up');
  if (select count(*) from public.handoff_requests where conversation_id = conversation) <> 1
    or not exists(select 1 from public.conversations where id = conversation and status = 'handoff') then
    raise exception 'Handoff retry duplicated the request or failed to change status';
  end if;
  begin
    perform public.request_conversation_handoff(tenant, conversation, request, 'Changed note');
    raise exception 'Same request identity accepted changed content';
  exception when serialization_failure then null; end;
  begin
    perform public.request_conversation_handoff(tenant, conversation, gen_random_uuid(), 'Second handoff');
    raise exception 'Active handoff was duplicated with a new identity';
  exception when object_not_in_prerequisite_state then null; end;
  begin
    perform public.mark_conversation_opened(tenant, current_setting('test.lifecycle_other_conversation')::uuid);
    raise exception 'Read marker crossed tenants';
  exception when no_data_found then null; end;
  begin
    perform public.request_conversation_handoff(current_setting('test.lifecycle_other_tenant')::uuid,
      current_setting('test.lifecycle_other_conversation')::uuid, gen_random_uuid(), 'Forbidden');
    raise exception 'Handoff crossed tenants';
  exception when insufficient_privilege then null; end;
  begin
    update public.conversations set status = 'open' where id = conversation;
    raise exception 'Client bypassed lifecycle RPC';
  exception when insufficient_privilege then null; end;
  begin
    update public.conversations set last_opened_role = 'admin' where id = conversation;
    raise exception 'Client forged opener role';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.handoff_requests(tenant_id, conversation_id, status) values(tenant, conversation, 'open');
    raise exception 'Client bypassed handoff RPC';
  exception when insufficient_privilege then null; end;
end;
$$;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.lifecycle_reader'))::text, true);
do $$
begin
  perform public.mark_conversation_opened(current_setting('test.lifecycle_tenant')::uuid,
    current_setting('test.lifecycle_conversation')::uuid);
  begin
    perform public.request_conversation_handoff(current_setting('test.lifecycle_tenant')::uuid,
      current_setting('test.lifecycle_conversation')::uuid, gen_random_uuid(), 'Unauthorized');
    raise exception 'Inbox-only employee created a handoff';
  exception when insufficient_privilege then null; end;
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
begin
  if not exists(select 1 from public.bot_reply_jobs
    where conversation_id = current_setting('test.lifecycle_conversation')::uuid and state = 'cancelled'
      and lease_token is null and leased_until is null and error_code = 'human_handoff') then
    raise exception 'Handoff left an active bot lease';
  end if;
  if (select count(*) from public.tenant_audit_events where tenant_id = current_setting('test.lifecycle_tenant')::uuid
    and action = 'conversation.handoff_requested') <> 1 then
    raise exception 'Idempotent handoff produced duplicate audit events';
  end if;
  -- A late retry of a completed request must not create or reopen a handoff.
  update public.handoff_requests set status = 'done' where id = current_setting('test.lifecycle_request')::uuid;
  update public.conversations set status = 'closed' where id = current_setting('test.lifecycle_conversation')::uuid;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.lifecycle_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  perform public.request_conversation_handoff(current_setting('test.lifecycle_tenant')::uuid,
    current_setting('test.lifecycle_conversation')::uuid, current_setting('test.lifecycle_request')::uuid, 'Follow up');
  if not exists(select 1 from public.conversations where id = current_setting('test.lifecycle_conversation')::uuid and status = 'closed') then
    raise exception 'Late handoff retry reopened a closed conversation';
  end if;
end;
$$;
rollback;
