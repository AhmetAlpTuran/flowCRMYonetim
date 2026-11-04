-- Bot replies grounded on tool results (reason tool_answer). Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.bot_input(p_tenant uuid, p_connection uuid, p_phone text)
returns uuid language plpgsql as $$
declare conversation uuid; input_id uuid := gen_random_uuid(); job_id uuid := gen_random_uuid();
begin
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (p_tenant, p_connection, p_phone, 'Tools', 'open') returning id into conversation;
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (input_id, p_tenant, conversation, p_connection, 'Customer', 'Cumartesi boş oda var mı?', true);
  update public.conversations set last_customer_message_at = now() where id = conversation;
  insert into public.bot_reply_jobs(id, tenant_id, conversation_id, input_message_id)
    values (job_id, p_tenant, conversation, input_id);
  return job_id;
end;
$$;

do $$
declare t uuid := gen_random_uuid(); conn uuid := gen_random_uuid(); job public.bot_reply_jobs; ctx jsonb;
  tool_reply jsonb := '{"action":"reply","text":"Cumartesi için Deniz Odası müsait.","reason":"tool_answer","knowledge_ids":[]}';
begin
  insert into public.tenants(id, name) values (t, 'Tools A');
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '980000000001', '980000000002', 'fixture', 'active', now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values (conn, t, 'fixture', repeat('A', 24), repeat('A', 16));
  insert into public.bot_settings(tenant_id, is_active) values (t, true);

  perform pg_temp.bot_input(t, conn, '905558880001');
  select * into job from public.claim_bot_reply();
  ctx := public.bot_reply_context(job.id, job.lease_token);
  if ctx is null then raise exception 'Context unavailable for a catalog-only business'; end if;
  if public.prepare_bot_reply(job.id, job.lease_token, (ctx->>'automation_revision')::bigint,
      (ctx->>'context_revision')::bigint, 'gpt-4o-mini', 3000, 100000) <> 'prepared' then
    raise exception 'Preparation failed';
  end if;
  -- Two model rounds (tool call + final answer) are settled as one total.
  if not public.settle_bot_usage(job.id, job.lease_token, '{"input_tokens":2400,"output_tokens":180,"total_tokens":2580}') then
    raise exception 'Usage not settled';
  end if;
  begin
    perform public.complete_bot_reply(job.id, job.lease_token,
      '{"action":"reply","text":"x","reason":"knowledge_answer","knowledge_ids":[]}');
    raise exception 'Knowledge answer without sources accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.complete_bot_reply(job.id, job.lease_token,
      '{"action":"reply","text":"x","reason":"made_up","knowledge_ids":[]}');
    raise exception 'Unknown reason accepted';
  exception when sqlstate '22023' then null;
  end;
  if not public.complete_bot_reply(job.id, job.lease_token, tool_reply) then
    raise exception 'Tool answer rejected';
  end if;
  if not exists (select 1 from public.messages where id = job.id and body = 'Cumartesi için Deniz Odası müsait.'
      and not is_from_customer) then raise exception 'Tool answer was not queued as a reply'; end if;
  if not exists (select 1 from public.inbox_dispatches where id = job.id and source = 'bot') then
    raise exception 'Tool answer has no dispatch';
  end if;
end;
$$;
rollback;
