-- Dashboard aggregates, permission, period bounds and tenant isolation. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare t uuid := gen_random_uuid(); other uuid := gen_random_uuid();
  viewer uuid := gen_random_uuid(); agent uuid := gen_random_uuid();
  conn uuid := gen_random_uuid(); c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid();
  c3 uuid := gen_random_uuid(); c_other uuid := gen_random_uuid(); m uuid;
  today_noon timestamptz := ((now() at time zone 'Europe/Istanbul')::date + time '12:00') at time zone 'Europe/Istanbul';
begin
  insert into public.tenants(id, name) values (t, 'Dashboard A'), (other, 'Dashboard B');
  insert into auth.users(id, email, email_confirmed_at) values
    (viewer, 'viewer-' || viewer || '@example.invalid', now()), (agent, 'agent-' || agent || '@example.invalid', now());
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, viewer, 'user', array['dashboard']), (t, agent, 'user', array['inbox']);
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '910000000001', '910000000002', '+90 555 000 0001', 'active', now());
  insert into public.conversations(id, tenant_id, title, status, assigned_to, created_at, connection_id, customer_phone) values
    (c1, t, 'Bir', 'open', null, now() - interval '1 hour', conn, '905551000001'),
    (c2, t, 'Iki', 'handoff', agent, now() - interval '3 days', conn, '905551000002'),
    (c3, t, 'Uc', 'closed', null, now() - interval '40 days', conn, '905551000003');
  insert into public.conversations(id, tenant_id, title, status) values (c_other, other, 'Baska', 'open');

  -- Inbound: two today, one five days ago, one outside a 7-day period, one for another tenant.
  insert into public.messages(tenant_id, conversation_id, sender, body, is_from_customer, sent_at, message_type) values
    (t, c1, 'customer', 'a', true, today_noon - interval '1 minute', 'text'),
    (t, c1, 'customer', 'b', true, today_noon - interval '2 minutes', 'text'),
    (t, c2, 'customer', 'c', true, today_noon - interval '5 days', 'text'),
    (t, c3, 'customer', 'd', true, now() - interval '20 days', 'text'),
    (other, c_other, 'customer', 'x', true, now(), 'text');

  -- Accepted replies: one human, one bot.
  insert into public.messages(id, tenant_id, conversation_id, sender, body, is_from_customer, sent_at, message_type, connection_id)
    values (gen_random_uuid(), t, c1, 'agent', 'h', false, now(), 'text', conn) returning id into m;
  insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, actor_id, state,
      provider_message_id, accepted_at, expires_at, source)
    values (m, t, c1, conn, '905551000001', agent, 'accepted', 'wamid.h', today_noon, now() + interval '1 day', 'human');
  insert into public.messages(id, tenant_id, conversation_id, sender, body, is_from_customer, sent_at, message_type, connection_id)
    values (gen_random_uuid(), t, c2, 'bot', 'b', false, now(), 'text', conn) returning id into m;
  insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, state,
      provider_message_id, accepted_at, expires_at, source)
    values (m, t, c2, conn, '905551000002', 'accepted', 'wamid.b', today_noon - interval '1 day', now() + interval '1 day', 'bot');

  -- Episodes with known response/resolution times (60s/120s first response, 600s resolution);
  -- a legacy episode must not skew medians.
  delete from public.support_episodes where tenant_id = t;
  insert into public.support_episodes(tenant_id, conversation_id, opened_at, opened_source, first_bot_response_at,
      first_human_response_at, resolved_at, resolution_kind) values
    (t, c1, now() - interval '2 hours', 'customer', now() - interval '2 hours' + interval '60 seconds', null, null, null),
    (t, c2, now() - interval '3 hours', 'customer', null, now() - interval '3 hours' + interval '120 seconds',
      now() - interval '3 hours' + interval '600 seconds', 'human'),
    (t, c3, now() - interval '1 hour', 'legacy', null, now(), now(), 'automation');
  insert into public.handoff_requests(tenant_id, conversation_id, note, status, created_at)
    values (t, c2, 'x', 'open', now() - interval '2 days');

  perform set_config('test.tenant', t::text, true);
  perform set_config('test.other', other::text, true);
  perform set_config('test.viewer', viewer::text, true);
  perform set_config('test.agent', agent::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);

-- A member without the dashboard permission is refused.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.agent'))::text, true);
do $$
begin
  perform public.dashboard_metrics(current_setting('test.tenant')::uuid);
  raise exception 'Dashboard shown without permission';
exception when insufficient_privilege then null;
end;
$$;

-- A dashboard-only member sees aggregates for their tenant only.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.viewer'))::text, true);
do $$
declare t uuid := current_setting('test.tenant')::uuid; d jsonb; last_day jsonb;
begin
  begin
    perform public.dashboard_metrics(t, 0);
    raise exception 'Zero-day period accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.dashboard_metrics(t, 7, 'Mars/Olympus');
    raise exception 'Unknown time zone accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.dashboard_metrics(current_setting('test.other')::uuid);
    raise exception 'Cross-tenant dashboard allowed';
  exception when insufficient_privilege then null;
  end;

  d := public.dashboard_metrics(t, 7);
  if d->'conversations' <> '{"open":1,"pending":0,"handoff":1,"unassigned_waiting":1,"started":2}'::jsonb then
    raise exception 'Conversation counts wrong: %', d->'conversations';
  end if;
  if (d#>>'{messages,inbound}')::int <> 3 or (d#>>'{messages,human_replies}')::int <> 1
    or (d#>>'{messages,bot_replies}')::int <> 1 then raise exception 'Message counts wrong: %', d->'messages'; end if;
  if (d->>'handoffs')::int <> 1 then raise exception 'Handoff count wrong'; end if;
  if (d#>>'{support,opened}')::int <> 3 or (d#>>'{support,resolved}')::int <> 2
    or (d#>>'{support,median_first_response_seconds}')::numeric <> 90
    or (d#>>'{support,median_first_human_response_seconds}')::numeric <> 120
    or (d#>>'{support,median_resolution_seconds}')::numeric <> 600 then
    raise exception 'Support timing wrong: %', d->'support';
  end if;
  if d->'campaigns' <> '{"accepted":0,"delivered":0,"read":0,"failed":0}'::jsonb then
    raise exception 'Campaign zero state wrong: %', d->'campaigns';
  end if;
  if jsonb_array_length(d->'daily') <> 7 then raise exception 'Daily series length wrong'; end if;
  last_day := d->'daily'->6;
  if (last_day->>'day')::date <> (now() at time zone 'Europe/Istanbul')::date
    or (last_day->>'inbound')::int <> 2 or (last_day->>'replies')::int <> 1 then
    raise exception 'Today bucket wrong: %', last_day;
  end if;
  if (select sum((x->>'inbound')::int) from jsonb_array_elements(d->'daily') x) <> 3 then
    raise exception 'Daily inbound does not add up';
  end if;

  d := public.dashboard_metrics(t, 30);
  if (d#>>'{messages,inbound}')::int <> 4 then raise exception '30-day period missed older messages'; end if;
  if d::text like '%905551%' or d::text like '%"a"%' then raise exception 'Dashboard leaked identities or content'; end if;
end;
$$;
rollback;
