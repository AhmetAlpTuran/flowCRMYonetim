-- Booking confirmation buttons on bot replies. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.prepared_job(p_tenant uuid, p_connection uuid, p_phone text)
returns public.bot_reply_jobs language plpgsql as $$
declare conversation uuid; input_id uuid := gen_random_uuid(); v_job public.bot_reply_jobs; ctx jsonb;
begin
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (p_tenant, p_connection, p_phone, 'Buttons', 'open') returning id into conversation;
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (input_id, p_tenant, conversation, p_connection, 'Customer', 'Oda ayırır mısınız?', true);
  update public.conversations set last_customer_message_at = now() where id = conversation;
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id)
    values (p_tenant, conversation, input_id);
  select * into v_job from public.claim_bot_reply();
  ctx := public.bot_reply_context(v_job.id, v_job.lease_token);
  perform public.prepare_bot_reply(v_job.id, v_job.lease_token, (ctx->>'automation_revision')::bigint,
    (ctx->>'context_revision')::bigint, 'gpt-4o-mini', 3000, 100000);
  perform public.settle_bot_usage(v_job.id, v_job.lease_token, '{"input_tokens":1000,"output_tokens":50,"total_tokens":1050}');
  select * into v_job from public.bot_reply_jobs where id = v_job.id;
  return v_job;
end;
$$;

do $$
declare t uuid := gen_random_uuid(); conn uuid := gen_random_uuid(); job public.bot_reply_jobs; job2 public.bot_reply_jobs;
  room_type uuid; room uuid; hold jsonb; other_hold jsonb; good jsonb; base jsonb;
begin
  insert into public.tenants(id, name) values (t, 'Buttons A');
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '985000000001', '985000000002', 'fixture', 'active', now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values (conn, t, 'fixture', repeat('A', 24), repeat('A', 16));
  insert into public.bot_settings(tenant_id, is_active) values (t, true);
  insert into public.resource_types(tenant_id, key, name, kind, booking_unit) values (t, 'room', 'Oda', 'bookable', 'night')
    returning id into room_type;
  insert into public.resources(tenant_id, type_id, name) values (t, room_type, 'Deniz Odası') returning id into room;

  job := pg_temp.prepared_job(t, conn, '905558890001');
  hold := public.bot_create_booking_hold(t, job.conversation_id, room, now() + interval '3 days', now() + interval '5 days', 'Ayşe', 'jobA:hold');
  job2 := pg_temp.prepared_job(t, conn, '905558890002');
  other_hold := public.bot_create_booking_hold(t, job2.conversation_id, room, now() + interval '10 days', now() + interval '11 days', 'Ali', 'jobB:hold');

  base := '{"action":"reply","text":"Deniz Odası ayrıldı. Onaylıyor musunuz?","reason":"tool_answer","knowledge_ids":[]}';
  begin
    perform public.complete_bot_reply(job.id, job.lease_token, base || jsonb_build_object('buttons',
      jsonb_build_array(jsonb_build_object('id', 'booking:confirm:' || (other_hold->>'booking_id'), 'title', 'Onayla'))));
    raise exception 'Button for another conversation''s booking accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.complete_bot_reply(job.id, job.lease_token, jsonb_set(base, '{text}', to_jsonb(repeat('x', 1025)))
      || jsonb_build_object('buttons', jsonb_build_array(jsonb_build_object('id', 'booking:confirm:' || (hold->>'booking_id'), 'title', 'Onayla'))));
    raise exception 'Buttons on an over-long reply accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.complete_bot_reply(job.id, job.lease_token, base || jsonb_build_object('buttons',
      jsonb_build_array(jsonb_build_object('id', 'https://evil.example', 'title', 'Tıkla'))));
    raise exception 'Arbitrary button id accepted';
  exception when sqlstate '22023' then null;
  end;

  good := base || jsonb_build_object('buttons', jsonb_build_array(
    jsonb_build_object('id', 'booking:confirm:' || (hold->>'booking_id'), 'title', 'Onayla'),
    jsonb_build_object('id', 'booking:cancel:' || (hold->>'booking_id'), 'title', 'İptal')));
  if not public.complete_bot_reply(job.id, job.lease_token, good) then raise exception 'Valid buttons rejected'; end if;
  if not exists (select 1 from public.messages where id = job.id and message_type = 'interactive'
      and provider_content->'interactive'->'buttons' = good->'buttons') then
    raise exception 'Buttons not stored with the reply';
  end if;

  -- A reply without buttons stays a plain text message.
  if not public.complete_bot_reply(job2.id, job2.lease_token, base) then raise exception 'Plain reply rejected'; end if;
  if not exists (select 1 from public.messages where id = job2.id and message_type = 'text' and provider_content is null) then
    raise exception 'Plain reply changed shape';
  end if;
end;
$$;
rollback;
