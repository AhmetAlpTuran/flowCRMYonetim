-- Authored only. No AI/provider calls. Execute on an isolated migrated database
-- in the verification phase, with separate concurrent-session cases afterward.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.bot_input(p_tenant uuid, p_connection uuid, p_phone text, p_body text default 'Hours?')
returns uuid language plpgsql as $$
declare conversation uuid; input_id uuid := gen_random_uuid(); job_id uuid := gen_random_uuid();
begin
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values(p_tenant, p_connection, p_phone, 'Fixture', 'open') returning id into conversation;
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values(input_id, p_tenant, conversation, p_connection, 'Customer', p_body, true);
  update public.conversations set last_customer_message_at = now() where id = conversation;
  insert into public.bot_reply_jobs(id, tenant_id, conversation_id, input_message_id)
    values(job_id, p_tenant, conversation, input_id);
  return job_id;
end;
$$;

create function pg_temp.prepare_fixture(p_job uuid, p_token uuid, p_reserve integer, p_limit bigint)
returns text language plpgsql as $$
declare context jsonb;
begin
  context := public.bot_reply_context(p_job, p_token);
  return public.prepare_bot_reply(p_job, p_token, (context->>'automation_revision')::bigint,
    (context->>'context_revision')::bigint, 'gpt-4o-mini', p_reserve, p_limit);
end;
$$;

do $$
declare
  tenant_a uuid := gen_random_uuid();
  tenant_b uuid := gen_random_uuid();
  actor uuid := gen_random_uuid();
  connection_a uuid := gen_random_uuid();
  connection_b uuid := gen_random_uuid();
  knowledge_id uuid := gen_random_uuid();
  expected_job uuid;
  first_job public.bot_reply_jobs;
  job public.bot_reply_jobs;
  dispatch public.inbox_dispatches;
  usage public.tenant_ai_usage;
  reply jsonb;
  handoff jsonb := '{"action":"handoff","text":"","reason":"ai_budget_exhausted","knowledge_ids":[]}';
  original_token uuid;
  actual_count integer;
  context_version bigint;
begin
  insert into auth.users(id, email) values(actor, actor::text || '@example.invalid');
  insert into public.tenants(id, name) values(tenant_a, 'Bot A'), (tenant_b, 'Bot B');
  insert into public.tenant_memberships(tenant_id, user_id, role) values(tenant_a, actor, 'admin');
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values(connection_a, tenant_a, '901', '9010', 'fixture', 'active', now()),
      (connection_b, tenant_b, '902', '9020', 'fixture', 'active', now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values(connection_a, tenant_a, 'fixture', repeat('A', 24), repeat('A', 16)),
      (connection_b, tenant_b, 'fixture', repeat('A', 24), repeat('A', 16));
  insert into public.bot_settings(tenant_id, is_active) values(tenant_a, true), (tenant_b, true);
  insert into public.knowledge_base(id, tenant_id, title, content) values(knowledge_id, tenant_a, 'Hours', 'We open at nine.');
  reply := jsonb_build_object('action', 'reply', 'text', 'We open at nine.', 'reason', 'knowledge_answer',
    'knowledge_ids', jsonb_build_array(knowledge_id));
  select revision into context_version from public.bot_context_versions where tenant_id = tenant_a;
  update public.bot_settings set updated_at = now() + interval '1 second' where tenant_id = tenant_a;
  if (select revision from public.bot_context_versions where tenant_id = tenant_a) <> context_version then
    raise exception 'Identical settings invalidated active conversations';
  end if;

  expected_job := pg_temp.bot_input(tenant_a, connection_a, '905550001001');
  select * into first_job from public.claim_bot_reply();
  if first_job.id is distinct from expected_job then raise exception 'Initial bot job not claimed'; end if;
  if pg_temp.prepare_fixture(first_job.id, first_job.lease_token, 1000, 5000) <> 'prepared' then
    raise exception 'Valid AI reservation denied';
  end if;
  if pg_temp.prepare_fixture(first_job.id, first_job.lease_token, 1000, 5000) <> 'already_prepared' then
    raise exception 'Duplicate preparation permitted a second generation';
  end if;
  select * into usage from public.tenant_ai_usage where tenant_id = tenant_a;
  if usage.reserved_tokens <> 1000 or usage.request_count <> 1 then raise exception 'Reservation double counted'; end if;

  -- A separate conversation shares the same atomic tenant budget.
  expected_job := pg_temp.bot_input(tenant_a, connection_a, '905550001002');
  select * into job from public.claim_bot_reply();
  if job.id is distinct from expected_job then raise exception 'Busy conversation blocked another conversation'; end if;
  if pg_temp.prepare_fixture(job.id, job.lease_token, 4500, 5000) <> 'quota_pending' then
    raise exception 'Concurrent reservation exceeded the tenant cap';
  end if;
  -- Simulate exhausting the bounded capacity-wait attempts before handoff.
  update public.bot_reply_jobs set attempts = 3 where id = job.id;
  if not public.complete_bot_reply(job.id, job.lease_token, handoff) then raise exception 'Budget exhaustion did not create handoff'; end if;
  if not exists(select 1 from public.handoff_requests where bot_job_id = job.id and tenant_id = tenant_a and created_by is null)
    or not exists(select 1 from public.inbox_dispatches where id = job.id and source = 'bot_handoff' and actor_id is null) then
    raise exception 'Handoff request and notice were not committed together';
  end if;
  if not public.bot_dispatch_allowed(job.id, tenant_a, job.conversation_id, 'bot_handoff') then
    raise exception 'Valid handoff notice failed ownership check';
  end if;
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, sent_by)
    values(tenant_a, job.conversation_id, connection_a, 'Employee', 'I can help', actor);
  select * into dispatch from public.claim_inbox_dispatches(1);
  if public.start_inbox_dispatch(dispatch.id, dispatch.lease_token) then raise exception 'Bot notice sent after a human reply'; end if;

  -- Actual usage is settled once, and result persistence is independently idempotent.
  perform public.settle_bot_usage(first_job.id, first_job.lease_token, '{"input_tokens":100,"output_tokens":50,"total_tokens":150}', false, 'resp_first');
  perform public.settle_bot_usage(first_job.id, first_job.lease_token, '{"input_tokens":100,"output_tokens":50,"total_tokens":150}', false, 'resp_first');
  if not public.complete_bot_reply(first_job.id, first_job.lease_token, reply)
    or not public.complete_bot_reply(first_job.id, first_job.lease_token, reply) then raise exception 'Reply persistence was not idempotent'; end if;
  if (select count(*) from public.messages where id = first_job.id) <> 1
    or not exists(select 1 from public.tenant_ai_usage where tenant_id = tenant_a and consumed_tokens = 150 and reserved_tokens = 0) then
    raise exception 'Reply or usage was duplicated';
  end if;
  select * into dispatch from public.claim_inbox_dispatches(1);
  if dispatch.id is distinct from first_job.id or not public.start_inbox_dispatch(dispatch.id, dispatch.lease_token) then
    raise exception 'Completed bot reply could not use the scoped transport';
  end if;
  perform public.finish_inbox_dispatch(dispatch.id, dispatch.lease_token, 'accepted', 'wamid.bot-first');

  -- One tenant cannot consume another tenant's remaining budget.
  expected_job := pg_temp.bot_input(tenant_b, connection_b, '905550002001');
  select * into job from public.claim_bot_reply();
  if job.id is distinct from expected_job or pg_temp.prepare_fixture(job.id, job.lease_token, 5000, 5000) <> 'prepared' then
    raise exception 'Tenant budgets were mixed';
  end if;
  perform public.settle_bot_usage(job.id, job.lease_token, null, true);
  perform public.complete_bot_reply(job.id, job.lease_token, handoff || '{"reason":"ai_provider_rejected"}');
  update public.inbox_dispatches set state = 'cancelled' where id = job.id;

  -- Human takeover clears the job token, while late provider usage remains payable.
  expected_job := pg_temp.bot_input(tenant_a, connection_a, '905550001003');
  select * into job from public.claim_bot_reply();
  perform pg_temp.prepare_fixture(job.id, job.lease_token, 1000, 5000);
  original_token := job.lease_token;
  update public.conversations set status = 'pending' where id = job.conversation_id;
  update public.bot_reply_jobs set state = 'cancelled', lease_token = null, leased_until = null where id = job.id;
  if not public.settle_bot_usage(job.id, original_token, '{"input_tokens":200,"output_tokens":100,"total_tokens":300}') then
    raise exception 'Human takeover lost actual AI usage';
  end if;
  if public.complete_bot_reply(job.id, original_token, reply) or exists(select 1 from public.messages where id = job.id) then
    raise exception 'Cancelled generation queued a reply';
  end if;

  -- Expired started generations become handoffs and retain uncertain reservations.
  expected_job := pg_temp.bot_input(tenant_a, connection_a, '905550001004');
  select * into job from public.claim_bot_reply();
  perform pg_temp.prepare_fixture(job.id, job.lease_token, 1000, 5000);
  original_token := job.lease_token;
  update public.bot_reply_jobs set leased_until = now() - interval '1 second' where id = job.id;
  select count(*) into actual_count from public.claim_bot_reply();
  if actual_count <> 0 or not exists(select 1 from public.bot_reply_jobs where id = job.id and state = 'handoff' and attempts = 1)
    or not exists(select 1 from public.ai_usage_reservations where job_id = job.id and status = 'unknown') then
    raise exception 'Expired generation was repeated or lost its reservation';
  end if;
  perform public.settle_bot_usage(job.id, original_token, '{"input_tokens":150,"output_tokens":50,"total_tokens":200}');
  perform public.complete_bot_reply(job.id, original_token, reply);
  if (select output->>'action' from public.bot_reply_jobs where id = job.id) <> 'handoff'
    or (select count(*) from public.messages where id = job.id) <> 1 then
    raise exception 'Late model result replaced the established handoff';
  end if;
  update public.inbox_dispatches set state = 'cancelled' where id = job.id;

  -- A definitive rejection releases budget before a new fenced attempt.
  expected_job := pg_temp.bot_input(tenant_a, connection_a, '905550001005');
  select * into job from public.claim_bot_reply();
  perform pg_temp.prepare_fixture(job.id, job.lease_token, 1000, 5000);
  original_token := job.lease_token;
  perform public.settle_bot_usage(job.id, original_token, null, true);
  if not public.retry_bot_reply(job.id, original_token, 90) then raise exception 'Definitive rejection could not retry'; end if;
  if not exists(select 1 from public.bot_reply_jobs where id = job.id and available_at >= now() + interval '90 seconds') then
    raise exception 'Provider retry minimum was ignored';
  end if;
  update public.bot_reply_jobs set available_at = now() where id = job.id;
  select * into job from public.claim_bot_reply();
  if job.lease_token = original_token or job.attempts <> 2 then raise exception 'Retry reused a generation lease'; end if;
  perform pg_temp.prepare_fixture(job.id, job.lease_token, 1000, 5000);
  perform public.settle_bot_usage(job.id, job.lease_token, '{"input_tokens":75,"output_tokens":25,"total_tokens":100}');
  -- Changed knowledge invalidates business facts and creates an application-owned handoff.
  update public.knowledge_base set content = 'Hours changed.' where id = knowledge_id;
  perform public.complete_bot_reply(job.id, job.lease_token, reply);
  if not exists(select 1 from public.bot_reply_jobs where id = job.id and state = 'handoff' and error_code = 'bot_configuration_changed') then
    raise exception 'Stale business knowledge reached the outbound reply';
  end if;
  update public.inbox_dispatches set state = 'cancelled' where id = job.id;

  -- Unsupported incoming media enters the same job flow and needs no generation budget.
  perform public.ingest_whatsapp_events(jsonb_build_array(jsonb_build_object(
    'event_key', repeat('0', 63) || 'a', 'waba_id', '901', 'phone_number_id', '9010',
    'kind', 'message', 'message_id', 'wamid.bot-audio', 'occurred_at', now(),
    'payload', jsonb_build_object('sender_phone', '905550001006', 'contact_name', 'Customer', 'type', 'audio',
      'content', jsonb_build_object('type', 'audio', 'audio', jsonb_build_object('id', '123'))))));
  perform public.process_whatsapp_messages(50);
  select * into job from public.claim_bot_reply();
  if public.bot_reply_context(job.id, job.lease_token)->'input'->>'type' <> 'audio' then
    raise exception 'Unsupported inbound media never reached human routing';
  end if;
  perform pg_temp.prepare_fixture(job.id, job.lease_token, 0, 5000);
  perform public.complete_bot_reply(job.id, job.lease_token, handoff || '{"reason":"unsupported_request"}');
  if exists(select 1 from public.ai_usage_reservations where job_id = job.id) then
    raise exception 'Local media handoff reserved AI tokens';
  end if;
  update public.inbox_dispatches set state = 'cancelled' where id = job.id;

  -- A change after finalization must create a human task when dispatch suppresses
  -- stale facts. New customer input and actual human takeover have separate paths.
  expected_job := pg_temp.bot_input(tenant_a, connection_a, '905550001007');
  select * into job from public.claim_bot_reply();
  perform pg_temp.prepare_fixture(job.id, job.lease_token, 1000, 5000);
  perform public.settle_bot_usage(job.id, job.lease_token, '{"input_tokens":40,"output_tokens":10,"total_tokens":50}');
  perform public.complete_bot_reply(job.id, job.lease_token, reply || '{"text":"Hours changed."}');
  update public.knowledge_base set content = 'New opening hours.' where id = knowledge_id;
  select * into dispatch from public.claim_inbox_dispatches(1);
  if dispatch.id is distinct from job.id or public.start_inbox_dispatch(dispatch.id, dispatch.lease_token) then
    raise exception 'Configuration changed after generation but stale reply was sent';
  end if;
  perform public.reconcile_bot_delivery_failures(20);
  perform public.reconcile_bot_delivery_failures(20);
  if not exists(select 1 from public.handoff_requests where bot_job_id = job.id and tenant_id = tenant_a)
    or not exists(select 1 from public.bot_reply_jobs where id = job.id and state = 'handoff'
      and error_code = 'bot_delivery_unconfirmed') then
    raise exception 'Suppressed reply did not reach the human queue';
  end if;

  -- A cancelled job may outlive its worker without ever receiving settlement.
  -- Preserve its budget hold, label uncertainty, and accept later measured usage.
  expected_job := pg_temp.bot_input(tenant_a, connection_a, '905550001008');
  select * into job from public.claim_bot_reply();
  perform pg_temp.prepare_fixture(job.id, job.lease_token, 1000, 5000);
  original_token := job.lease_token;
  update public.bot_reply_jobs set state = 'cancelled', lease_token = null, leased_until = null where id = job.id;
  update public.conversations set status = 'pending' where id = job.conversation_id;
  update public.ai_usage_reservations set created_at = now() - interval '10 minutes' where job_id = job.id;
  perform public.mark_stale_ai_reservations(100);
  if not exists(select 1 from public.ai_usage_reservations where job_id = job.id and status = 'unknown') then
    raise exception 'Abandoned reservation remained incorrectly active';
  end if;
  perform public.settle_bot_usage(job.id, original_token, '{"input_tokens":60,"output_tokens":20,"total_tokens":80}');
  perform set_config('test.bot_worker_actor', actor::text, true);
  perform set_config('test.bot_worker_tenant', tenant_a::text, true);
  perform set_config('test.bot_worker_other_tenant', tenant_b::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.bot_worker_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if exists(select 1 from public.tenant_ai_usage where tenant_id = current_setting('test.bot_worker_other_tenant')::uuid) then
    raise exception 'Usage totals leaked across tenants';
  end if;
  begin
    insert into public.tenant_ai_limits(tenant_id, monthly_token_limit) values(current_setting('test.bot_worker_tenant')::uuid, 999999);
    raise exception 'Tenant administrator raised their own budget';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from public.ai_usage_reservations;
    raise exception 'Client read private generation leases';
  exception when insufficient_privilege then null; end;
  begin
    perform public.claim_bot_reply();
    raise exception 'Client claimed paid generation';
  exception when insufficient_privilege then null; end;
end;
$$;
rollback;
