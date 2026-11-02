-- Authored only. Isolated migrated database, no AI/provider calls, rolled back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare
  tenant_a uuid := gen_random_uuid();
  tenant_b uuid := gen_random_uuid();
  actor uuid := gen_random_uuid();
  connection_a uuid := gen_random_uuid();
  conversation_a uuid := gen_random_uuid();
  conversation_other uuid := gen_random_uuid();
  input_id uuid := gen_random_uuid();
  next_input uuid := gen_random_uuid();
  knowledge_id uuid := gen_random_uuid();
  job_id uuid := gen_random_uuid();
  lease uuid := gen_random_uuid();
  context jsonb;
  changed jsonb;
begin
  insert into auth.users(id, email) values(actor, actor::text || '@example.invalid');
  insert into public.tenants(id, name) values(tenant_a, 'Context A'), (tenant_b, 'Context B');
  insert into public.tenant_memberships(tenant_id, user_id, role) values(tenant_a, actor, 'admin');
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values(connection_a, tenant_a, '801', '8010', 'fixture', 'active', now());
  insert into public.conversations(id, tenant_id, connection_id, customer_phone, title, status, last_customer_message_at)
    values(conversation_a, tenant_a, connection_a, '905550000001', 'First', 'open', now() - interval '1 hour'),
      (conversation_other, tenant_a, connection_a, '905550000002', 'Other', 'open', now() - interval '1 hour');
  insert into public.bot_settings(tenant_id, is_active) values(tenant_a, true);
  insert into public.bot_settings(tenant_id) values(tenant_b);
  if (select is_active from public.bot_settings where tenant_id = tenant_b) then
    raise exception 'New bot settings activated automatically';
  end if;
  insert into public.knowledge_base(id, tenant_id, title, content) values
    (knowledge_id, tenant_a, 'Hours', 'We open at 9am.'),
    (gen_random_uuid(), tenant_b, 'Hours', 'OTHER_TENANT_SECRET');
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer, sent_at)
    values(tenant_a, conversation_other, connection_a, 'Other', 'OTHER_CUSTOMER_SECRET', true, now());
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer, sent_at)
    values(input_id, tenant_a, conversation_a, connection_a, 'Customer', 'What are your hours?', true, now());
  update public.conversations set last_customer_message_at = now() where id = conversation_a;
  insert into public.bot_reply_jobs(id, tenant_id, conversation_id, input_message_id, state, lease_token, leased_until)
    values(job_id, tenant_a, conversation_a, input_id, 'leased', lease, now() + interval '2 minutes');
  context := public.bot_reply_context(job_id, lease);
  if context is null or context->>'input_message_id' <> input_id::text
    or context->'knowledge'->0->>'id' <> knowledge_id::text
    or context::text like '%OTHER_TENANT_SECRET%' or context::text like '%OTHER_CUSTOMER_SECRET%' then
    raise exception 'Context scope or retrieval mismatch';
  end if;
  if public.bot_reply_context(job_id, gen_random_uuid()) is not null then
    raise exception 'Wrong lease read generation context';
  end if;
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer, message_type, sent_at)
    values(tenant_a, conversation_a, connection_a, 'Customer', '👍', true, 'reaction', now());
  if public.bot_reply_context(job_id, lease) is null then
    raise exception 'An emoji reaction suppressed the pending question';
  end if;

  update public.knowledge_base set content = repeat('Background ', 700) || 'Hours LATE_ANSWER_FIXTURE are nine to five.'
    where id = knowledge_id;
  changed := public.bot_reply_context(job_id, lease);
  if changed->'knowledge'->0->>'content' not like '%LATE_ANSWER_FIXTURE%' then
    raise exception 'Relevant knowledge beyond the initial prefix was omitted';
  end if;

  update public.knowledge_base set content = 'We open at 10am.' where id = knowledge_id;
  changed := public.bot_reply_context(job_id, lease);
  if (changed->>'context_revision')::bigint <= (context->>'context_revision')::bigint
    or changed->'knowledge'->0->>'content' <> 'We open at 10am.' then
    raise exception 'Knowledge edits did not change the context version';
  end if;
  begin
    update public.knowledge_base set tenant_id = tenant_b where id = knowledge_id;
    raise exception 'Knowledge silently moved between tenants';
  exception when insufficient_privilege then null; end;

  -- Delayed older input leaves the exact current pointer intact.
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer, sent_at)
    values(tenant_a, conversation_a, connection_a, 'Customer', 'Older', true, now() - interval '2 hours');
  if (select last_customer_message_id from public.conversations where id = conversation_a) <> input_id then
    raise exception 'Delayed input replaced the current input pointer';
  end if;
  -- A second input with the same provider timestamp still has a distinct identity.
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer, sent_at)
    values(next_input, tenant_a, conversation_a, connection_a, 'Customer', 'And closing time?', true, now());
  if public.bot_reply_context(job_id, lease) is not null then raise exception 'Stale job read current context'; end if;
  update public.bot_reply_jobs set input_message_id = next_input where id = job_id;
  context := public.bot_reply_context(job_id, lease);
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, sent_by)
    values(tenant_a, conversation_a, connection_a, 'Employee', 'I can help', actor);
  changed := public.bot_reply_context(job_id, lease);
  if (changed->>'automation_revision')::bigint <= (context->>'automation_revision')::bigint then
    raise exception 'Human reply did not invalidate the prior automation revision';
  end if;
  update public.conversations set status = 'handoff' where id = conversation_a;
  if public.bot_reply_context(job_id, lease) is not null then raise exception 'Human-owned conversation returned bot context'; end if;
  update public.conversations set status = 'open' where id = conversation_a;
  update public.bot_settings set is_active = false where tenant_id = tenant_a;
  if public.bot_reply_context(job_id, lease) is not null then raise exception 'Inactive bot returned generation context'; end if;
  delete from public.messages where id = next_input;
  if (select last_customer_message_id from public.conversations where id = conversation_a) is not null
    or (select tenant_id from public.conversations where id = conversation_a) <> tenant_a then
    raise exception 'Deleting current input did not clear only its pointer';
  end if;
  delete from public.tenants where id = tenant_b;
  perform set_config('test.bot_context_actor', actor::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.bot_context_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.bot_reply_context(gen_random_uuid(), gen_random_uuid());
    raise exception 'Client invoked private context retrieval';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from public.bot_context_versions;
    raise exception 'Client read private context versions';
  exception when insufficient_privilege then null; end;
end;
$$;
rollback;
