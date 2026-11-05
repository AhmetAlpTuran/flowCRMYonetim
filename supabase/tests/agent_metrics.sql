-- Per-agent dashboard metrics. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare t uuid := gen_random_uuid(); conn uuid := gen_random_uuid(); admin_id uuid := gen_random_uuid();
  ayse uuid := gen_random_uuid(); can uuid := gen_random_uuid(); conversation uuid; msg uuid;
begin
  insert into auth.users(id, email) values (admin_id, 'admin-' || admin_id || '@example.invalid'),
    (ayse, 'ayse-' || ayse || '@example.invalid'), (can, 'can-' || can || '@example.invalid');
  insert into public.tenants(id, name) values (t, 'Ekip');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, admin_id, 'admin', public.tenant_module_keys()), (t, ayse, 'user', array['inbox', 'dashboard']),
    (t, can, 'user', array['inbox']);
  update public.user_profiles set display_name = 'Ayşe Yılmaz' where id = ayse;
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '973001', '9730011', 'x', 'active', now());
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status, assigned_to)
    values (t, conn, '905556660001', 'Müşteri', 'open', ayse) returning id into conversation;
  -- Two accepted replies by Ayşe, one by Can; one failed reply that does not count.
  for i in 1..4 loop
    insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
      values (t, conversation, conn, 'Agent', 'Yanıt ' || i, false) returning id into msg;
    insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, source, actor_id,
        expires_at, state, accepted_at)
      values (msg, t, conversation, conn, '905556660001', 'human', case when i = 3 then can else ayse end,
        now() + interval '1 day', case when i = 4 then 'failed' else 'accepted' end,
        case when i = 4 then null else now() end);
  end loop;
  insert into public.support_episodes(tenant_id, conversation_id, opened_at, opened_source, first_human_response_at,
      first_human_responder_id, resolved_at, resolved_by, resolution_kind)
    values (t, conversation, now() - interval '10 minutes', 'customer', now() - interval '8 minutes', ayse,
      now() - interval '1 minute', ayse, 'human');
  perform set_config('test.t', t::text, true);
  perform set_config('test.admin', admin_id::text, true);
  perform set_config('test.ayse', ayse::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.ayse'))::text, true);
do $$
begin
  perform public.dashboard_agent_metrics(current_setting('test.t')::uuid, 7);
  raise exception 'A non-admin read per-agent metrics';
exception when insufficient_privilege then null;
end;
$$;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.admin'))::text, true);
do $$
declare result jsonb; first jsonb;
begin
  result := public.dashboard_agent_metrics(current_setting('test.t')::uuid, 7);
  if jsonb_array_length(result->'agents') <> 3 then raise exception 'Every member should be listed: %', result; end if;
  first := result->'agents'->0;
  if first->>'name' <> 'Ayşe Yılmaz' or (first->>'replies')::int <> 2 or (first->>'first_responses')::int <> 1
    or (first->>'median_first_response_seconds')::numeric not between 110 and 130
    or (first->>'resolved')::int <> 1 or (first->>'open_assigned')::int <> 1 then
    raise exception 'Ayşe''s metrics wrong: %', first;
  end if;
  if (result->'agents'->1->>'replies')::int <> 1 then raise exception 'Agents not ordered by replies: %', result; end if;
  begin
    perform public.dashboard_agent_metrics(current_setting('test.t')::uuid, 0);
    raise exception 'Invalid period accepted';
  exception when sqlstate '22023' then null;
  end;
end;
$$;
rollback;
