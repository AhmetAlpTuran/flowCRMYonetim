-- Operations health report. Rolls back. Fixtures assume empty queues.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare report jsonb; t uuid := gen_random_uuid(); conn uuid := gen_random_uuid(); conversation uuid; msg uuid;
begin
  report := public.ops_health();
  if not (report->>'healthy')::boolean or jsonb_array_length(report->'problems') <> 0 then
    raise exception 'Empty queues should be healthy: %', report;
  end if;

  insert into public.tenants(id, name) values (t, 'Ops');
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '974001', '9740011', 'x', 'active', now());
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (t, conn, '905557770009', 'Ops', 'open') returning id into conversation;
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (t, conversation, conn, 'Agent', 'Merhaba', false) returning id into msg;
  -- A reply waiting 20 minutes is stuck.
  insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, source, expires_at,
      state, available_at)
    values (msg, t, conversation, conn, '905557770009', 'bot', now() + interval '1 day', 'queued', now() - interval '20 minutes');
  insert into public.billing_events(provider, event_key, kind, subscription_ref, applied)
    values ('iyzico', 'subscription.order.success:OPS-1', 'renewed', 'SUB-OPS', false);

  report := public.ops_health();
  if (report->>'healthy')::boolean
    or not report->'problems' ? 'inbox_dispatches_stuck'
    or not report->'problems' ? 'billing_events_unmatched'
    or (report->'inbox_dispatches'->>'stuck')::int <> 1 then
    raise exception 'Stuck reply or unmatched billing event not reported: %', report;
  end if;
end;
$$;

set local role authenticated;
do $$
begin
  perform public.ops_health();
  raise exception 'Clients read the operations report';
exception when insufficient_privilege then null;
end;
$$;
rollback;
