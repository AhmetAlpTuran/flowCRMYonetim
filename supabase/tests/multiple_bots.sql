-- Multiple bots: extra bot profiles, per-number routing and the bot job flow. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.as_user(p_user text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', p_user)::text, true);
$$;
create function pg_temp.inbound(p_key text, p_phone_number_id text, p_sender text, p_body text) returns void
language plpgsql as $$
begin
  perform public.ingest_whatsapp_events(jsonb_build_array(jsonb_build_object(
    'event_key', lpad(p_key, 64, '0'), 'waba_id', '96001', 'phone_number_id', p_phone_number_id,
    'kind', 'message', 'message_id', 'wamid.bots-' || p_key, 'occurred_at', now(),
    'payload', jsonb_build_object('sender_phone', p_sender, 'contact_name', 'Customer', 'type', 'text',
      'content', jsonb_build_object('type', 'text', 'text', jsonb_build_object('body', p_body))))));
  perform public.process_whatsapp_messages(50);
end;
$$;

do $$
declare t uuid := gen_random_uuid(); t2 uuid := gen_random_uuid(); sales uuid := gen_random_uuid();
  service_line uuid := gen_random_uuid(); agent uuid := gen_random_uuid(); viewer uuid := gen_random_uuid();
  other_admin uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values (agent, 'a-' || agent || '@example.invalid'),
    (viewer, 'v-' || viewer || '@example.invalid'), (other_admin, 'o-' || other_admin || '@example.invalid');
  insert into public.tenants(id, name) values (t, 'Galeri'), (t2, 'Baska');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, agent, 'user', array['bot']), (t, viewer, 'user', array['inbox']),
    (t2, other_admin, 'admin', public.tenant_module_keys());
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, is_default, verified_at)
    values (sales, t, '96001', '960011', '+90 555 000 0001', 'active', true, now()),
           (service_line, t, '96001', '960012', '+90 555 000 0002', 'active', false, now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values (sales, t, 'fixture', repeat('A', 24), repeat('A', 16)), (service_line, t, 'fixture', repeat('A', 24), repeat('A', 16));
  -- The main bot is off: an extra bot must work on its own.
  insert into public.bot_settings(tenant_id, name, is_active) values (t, 'Ava', false);
  insert into public.bot_profiles(id, tenant_id, name) values ('99999999-9999-4999-8999-999999999999', t2, 'Yabanci');
  perform set_config('test.t', t::text, true);
  perform set_config('test.t2', t2::text, true);
  perform set_config('test.sales', sales::text, true);
  perform set_config('test.service', service_line::text, true);
  perform set_config('test.agent', agent::text, true);
  perform set_config('test.viewer', viewer::text, true);
  perform set_config('test.other', other_admin::text, true);
  perform set_config('test.version', (select revision from public.bot_context_versions where tenant_id = t)::text, true);
end;
$$;

set local role authenticated;
select pg_temp.as_user(current_setting('test.viewer'));
do $$
begin
  perform public.save_bot_profile(current_setting('test.t')::uuid, gen_random_uuid(), 'Servis', 'Net', 'Türkçe',
    'Servis randevusu ver.', 'gpt-4o-mini', 0.3, 6, 12, true);
  raise exception 'Member without bot permission created a bot';
exception when insufficient_privilege then null;
end;
$$;

select pg_temp.as_user(current_setting('test.agent'));
do $$
declare t uuid := current_setting('test.t')::uuid; saved public.bot_profiles;
  service_line uuid := current_setting('test.service')::uuid;
begin
  saved := public.save_bot_profile(t, '11111111-1111-4111-8111-111111111111', ' Servis ', 'Sakin', 'English',
    'Book service appointments.', 'gpt-4o-mini', 0.2, 12, 20, true);
  if saved.name <> 'Servis' or saved.tenant_id <> t or not saved.is_active then
    raise exception 'Saved bot wrong: %', row_to_json(saved);
  end if;
  saved := public.save_bot_profile(t, '11111111-1111-4111-8111-111111111111', 'Servis Botu', 'Sakin', 'English',
    'Book service appointments.', 'gpt-4o-mini', 0.2, 12, 20, true);
  if saved.name <> 'Servis Botu' or (select count(*) from public.bot_profiles where tenant_id = t) <> 1 then
    raise exception 'Re-saving did not update the same bot';
  end if;
  begin
    perform public.save_bot_profile(t, gen_random_uuid(), '  ', 'Net', 'Türkçe', 'x', 'gpt-4o-mini', 0.3, 6, 12, true);
    raise exception 'Empty bot name accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.save_bot_profile(t, gen_random_uuid(), 'Kötü', 'Net', 'Türkçe', 'x', 'gpt 4o; drop', 0.3, 6, 12, true);
    raise exception 'Invalid model accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.save_bot_profile(t, '99999999-9999-4999-8999-999999999999', 'Ele geçir', 'Net', 'Türkçe', 'x',
      'gpt-4o-mini', 0.3, 6, 12, true);
    raise exception 'Another tenant''s bot was overwritten';
  exception when insufficient_privilege then null;
  end;
  for i in 2..10 loop
    perform public.save_bot_profile(t, gen_random_uuid(), 'Bot ' || i, 'Net', 'Türkçe', 'x', 'gpt-4o-mini', 0.3, 6, 12, false);
  end loop;
  begin
    perform public.save_bot_profile(t, gen_random_uuid(), 'Fazla', 'Net', 'Türkçe', 'x', 'gpt-4o-mini', 0.3, 6, 12, false);
    raise exception 'Eleventh bot accepted';
  exception when raise_exception then
    if sqlerrm <> 'Bot limit reached' then raise; end if;
  end;
  begin
    insert into public.bot_profiles(id, tenant_id, name) values (gen_random_uuid(), t, 'Doğrudan');
    raise exception 'Client inserted a bot directly';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.whatsapp_connections set bot_enabled = false where id = service_line;
    raise exception 'Client changed a number''s bot directly';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_connection_bot(t, service_line, true, '99999999-9999-4999-8999-999999999999');
    raise exception 'Another tenant''s bot assigned to a number';
  exception when sqlstate '22023' then null;
  end;
  if not public.set_connection_bot(t, service_line, true, '11111111-1111-4111-8111-111111111111') then
    raise exception 'Bot assignment failed';
  end if;
  if public.set_connection_bot(t, gen_random_uuid(), true, null) then
    raise exception 'Unknown number assigned';
  end if;
end;
$$;

select pg_temp.as_user(current_setting('test.other'));
do $$
begin
  if exists (select 1 from public.bot_profiles where tenant_id = current_setting('test.t')::uuid) then
    raise exception 'Bots leaked across tenants';
  end if;
  if public.set_connection_bot(current_setting('test.t2')::uuid, current_setting('test.service')::uuid, false, null) then
    raise exception 'Another tenant re-routed a number';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare t uuid := current_setting('test.t')::uuid; sales uuid := current_setting('test.sales')::uuid;
  service_line uuid := current_setting('test.service')::uuid; job public.bot_reply_jobs; ctx jsonb;
  version bigint;
begin
  if (select revision from public.bot_context_versions where tenant_id = t) <= current_setting('test.version')::bigint then
    raise exception 'Bot changes did not change the bot context version';
  end if;
  -- Routing: the main bot (off) on the sales number, the service bot on the other.
  if exists (select 1 from public.effective_bot_settings(t, sales) where is_active)
    or (select name from public.effective_bot_settings(t, sales)) <> 'Ava' then
    raise exception 'Sales number should use the inactive main bot';
  end if;
  if (select name || '/' || language from public.effective_bot_settings(t, service_line) where is_active) <> 'Servis Botu/English' then
    raise exception 'Service number should use the service bot';
  end if;
  if (select name from public.effective_bot_settings(t, null)) <> 'Ava' then
    raise exception 'Conversations without a number should use the main bot';
  end if;

  -- Inbound on the sales number queues nothing; on the service number it queues a job.
  perform pg_temp.inbound('1', '960011', '905550009001', 'Merhaba');
  if exists (select 1 from public.bot_reply_jobs where tenant_id = t) then
    raise exception 'A number with an inactive bot queued a bot job';
  end if;
  perform pg_temp.inbound('2', '960012', '905550009002', 'Servis randevusu istiyorum');
  select * into job from public.claim_bot_reply();
  if job.tenant_id is distinct from t then raise exception 'Service bot job not claimed'; end if;
  ctx := public.bot_reply_context(job.id, job.lease_token);
  if ctx->'settings'->>'name' <> 'Servis Botu' or ctx->'settings'->>'language' <> 'English'
    or ctx->'settings'->>'system_prompt' <> 'Book service appointments.' then
    raise exception 'Context did not use the service bot: %', ctx->'settings';
  end if;
  if public.prepare_bot_reply(job.id, job.lease_token, (ctx->>'automation_revision')::bigint,
      (ctx->>'context_revision')::bigint, 'gpt-4o-mini', 3000, 100000) <> 'prepared' then
    raise exception 'Service bot job not prepared';
  end if;
  perform public.settle_bot_usage(job.id, job.lease_token, '{"input_tokens":500,"output_tokens":30,"total_tokens":530}');
  if not public.complete_bot_reply(job.id, job.lease_token,
      '{"action":"reply","text":"Which day suits you?","reason":"greeting_or_clarification","knowledge_ids":[]}') then
    raise exception 'Service bot reply rejected';
  end if;
  if not exists (select 1 from public.messages where id = job.id and sender = 'Servis Botu')
    or (select bot_profile_id from public.bot_reply_jobs where id = job.id) <> '11111111-1111-4111-8111-111111111111' then
    raise exception 'Reply not attributed to the service bot';
  end if;
  if not public.bot_dispatch_allowed(job.id, t, job.conversation_id, 'bot') then
    raise exception 'Service bot reply not allowed to send';
  end if;
  update public.inbox_dispatches set state = 'cancelled' where id = job.id;

  -- Switching the bot off for the number stops new jobs and invalidates in-flight ones.
  select revision into version from public.bot_context_versions where tenant_id = t;
  update public.whatsapp_connections set bot_enabled = false where id = service_line;
  if (select revision from public.bot_context_versions where tenant_id = t) <> version + 1 then
    raise exception 'Number routing change did not change the bot context version';
  end if;
  if exists (select 1 from public.effective_bot_settings(t, service_line)) then
    raise exception 'A number with the bot switched off still has a bot';
  end if;
  perform pg_temp.inbound('3', '960012', '905550009002', 'Hala orada misiniz?');
  if exists (select 1 from public.bot_reply_jobs where tenant_id = t and state = 'queued') then
    raise exception 'A number with the bot switched off queued a job';
  end if;
  update public.whatsapp_connections set bot_enabled = true where id = service_line;

  -- Deleting the bot moves the number back to the main bot and keeps the job history.
  perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.agent'))::text, true);
  set local role authenticated;
  if not public.delete_bot_profile(t, '11111111-1111-4111-8111-111111111111') then
    raise exception 'Bot delete failed';
  end if;
  reset role;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  if (select bot_profile_id from public.whatsapp_connections where id = service_line) is not null
    or (select name from public.effective_bot_settings(t, service_line)) <> 'Ava' then
    raise exception 'Number did not return to the main bot';
  end if;
  if not exists (select 1 from public.bot_reply_jobs where id = job.id and bot_profile_id is null and state = 'completed') then
    raise exception 'Job history lost after bot delete';
  end if;
  if not exists (select 1 from public.tenant_audit_events where tenant_id = t and action = 'bot.profile_deleted')
    or not exists (select 1 from public.tenant_audit_events where tenant_id = t and action = 'connection.bot_assigned') then
    raise exception 'Bot changes not audited';
  end if;

  -- Deleting the tenant cascades through bots and numbers.
  delete from public.tenants where id = t;
end;
$$;
rollback;
