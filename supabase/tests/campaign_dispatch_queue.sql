-- AUTHORED, NOT EXECUTED. Use an isolated migrated database during verification.
-- No external messages are sent. Fixtures, including auth users, are rolled back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare
  tenant_a uuid := gen_random_uuid(); tenant_b uuid := gen_random_uuid(); actor uuid := gen_random_uuid();
  template_id uuid := gen_random_uuid(); fixture_campaign uuid := gen_random_uuid(); other_campaign uuid := gen_random_uuid();
  expected jsonb; count_before bigint; count_after bigint; first_job public.campaign_dispatches;
  second_job public.campaign_dispatches; third_job public.campaign_dispatches; fourth_job public.campaign_dispatches;
  claimed_ids uuid[]; result jsonb; connection_id uuid := gen_random_uuid(); blocked_job public.campaign_dispatches;
begin
  insert into auth.users(id, email) values (actor, actor::text || '@example.invalid');
  insert into public.tenants(id, name) values (tenant_a, 'Queue test A'), (tenant_b, 'Queue test B');
  insert into public.tenant_memberships(tenant_id, user_id, role) values (tenant_a, actor, 'admin');
  perform public.save_whatsapp_connection(tenant_a, actor, connection_id, '777', '7777',
    '{"display_phone_number":"+90 555 000 0000","verified_name":"Queue fixture","token_expires_at":null}',
    jsonb_build_object('key_id', 'fixture', 'ciphertext', repeat('A', 24), 'iv', repeat('A', 16)), true);
  insert into public.templates(id, tenant_id, name, category, language, status, components, waba_id)
    values (template_id, tenant_a, 'queue_test', 'UTILITY', 'tr', 'APPROVED', '[{"type":"BODY","text":"Hello"}]', '777');
  insert into public.consented_contacts(tenant_id, phone, full_name)
    select tenant_a, (905550000000 + n)::text, 'Queue contact' from generate_series(1, 120) n;
  insert into public.consented_contacts(tenant_id, phone) values
    (tenant_a, '+90 (555) 000-0001'), (tenant_a, 'not-a-phone'), (tenant_b, '905550009999');
  insert into public.campaigns(id, tenant_id, name, status, template_id) values
    (fixture_campaign, tenant_a, 'Queue test', 'draft', template_id),
    (other_campaign, tenant_a, 'Legacy test', 'draft', template_id);
  begin
    insert into public.campaigns(tenant_id, name, status, template_id)
      values (tenant_b, 'Cross-tenant reference', 'draft', template_id);
    raise exception 'Cross-tenant template reference accepted';
  exception when foreign_key_violation then null; end;
  select jsonb_build_object('audience_filter', c.audience_filter, 'template_id', c.template_id,
    'template_bindings', c.template_bindings, 'connection_id', connection_id,
    'connection', jsonb_build_object('id', connection_id, 'waba_id', '777', 'phone_number_id', '7777'),
    'template', jsonb_build_object('name', t.name, 'language', t.language, 'components', t.components))
    into expected from public.campaigns c join public.templates t on t.id = c.template_id where c.id = fixture_campaign;

  count_before := public.count_campaign_audience(tenant_a, '{}');
  if count_before <> 121 then raise exception 'Canonical recipient count mismatch: %', count_before; end if;
  begin
    perform public.enqueue_campaign(fixture_campaign, actor, expected || '{"template_bindings":{"unexpected":{}}}');
    raise exception 'Stale configuration accepted';
  exception when serialization_failure then null; end;
  begin
    perform public.enqueue_campaign(fixture_campaign, gen_random_uuid(), expected);
    raise exception 'Nonmember actor accepted';
  exception when insufficient_privilege then null; end;
  update public.templates set waba_id = '888' where id = template_id;
  begin
    perform public.enqueue_campaign(fixture_campaign, actor, expected);
    raise exception 'Template from another WhatsApp account accepted';
  exception when invalid_parameter_value then null; end;
  update public.templates set waba_id = '777' where id = template_id;
  count_after := public.enqueue_campaign(fixture_campaign, actor, expected);
  if count_after <> count_before then raise exception 'Preview/snapshot mismatch'; end if;
  if public.enqueue_campaign(fixture_campaign, actor, expected) <> count_before then
    raise exception 'Repeated enqueue changed snapshot';
  end if;
  if (select count(*) from public.campaign_dispatches d where d.campaign_id = fixture_campaign) <> 121 then
    raise exception 'Queue cap or duplicate enqueue';
  end if;
  if (select count(*) from public.campaign_dispatches d where d.campaign_id = fixture_campaign and d.state = 'failed') <> 1 then
    raise exception 'Invalid phone did not become a visible failure';
  end if;
  begin
    update public.campaigns set audience_filter = '{"segment":"VIP"}' where id = fixture_campaign;
    raise exception 'Queued campaign configuration changed';
  exception when object_not_in_prerequisite_state then null; end;

  select array_agg(id) into claimed_ids from public.claim_campaign_dispatches(25, fixture_campaign);
  if cardinality(claimed_ids) <> 25 then raise exception 'Bounded claim size mismatch'; end if;
  if exists (select 1 from public.claim_campaign_dispatches(25, fixture_campaign) d where d.id = any(claimed_ids)) then
    raise exception 'Same recipient claimed twice';
  end if;
  select * into first_job from public.campaign_dispatches where id = claimed_ids[1];
  select * into second_job from public.campaign_dispatches where id = claimed_ids[2];
  select * into third_job from public.campaign_dispatches where id = claimed_ids[3];
  select * into fourth_job from public.campaign_dispatches where id = claimed_ids[4];
  select * into blocked_job from public.campaign_dispatches where id = claimed_ids[5];
  update public.whatsapp_connections set status = 'inactive' where id = connection_id;
  begin
    perform public.start_campaign_dispatch(blocked_job.id, blocked_job.lease_token);
    raise exception 'Disconnected connection dispatched';
  exception when object_not_in_prerequisite_state then null; end;
  if not public.defer_campaign_dispatch(blocked_job.id, blocked_job.lease_token, 'connection_inactive') then
    raise exception 'Pre-send configuration failure not deferred';
  end if;
  if not exists (select 1 from public.campaign_dispatches d where d.id = blocked_job.id and d.state = 'blocked' and d.attempts = 0) then
    raise exception 'Blocked configuration consumed provider attempt';
  end if;
  if public.start_campaign_dispatch(blocked_job.id, blocked_job.lease_token) then
    raise exception 'Blocked job reused previous lease';
  end if;
  update public.whatsapp_connections set status = 'active' where id = connection_id;
  if public.start_campaign_dispatch(first_job.id, gen_random_uuid()) then raise exception 'Wrong lease accepted'; end if;
  if not public.start_campaign_dispatch(first_job.id, first_job.lease_token) then raise exception 'Start failed'; end if;
  if not public.finish_campaign_dispatch(first_job.id, first_job.lease_token, 'accepted', 'wamid.queue-test-1') then
    raise exception 'Acknowledgement failed';
  end if;
  if not public.finish_campaign_dispatch(first_job.id, first_job.lease_token, 'accepted', 'wamid.queue-test-1') then
    raise exception 'Acknowledgement is not idempotent';
  end if;

  -- A lost pre-send lease can be retried; its previous fencing token cannot send.
  update public.campaign_dispatches set leased_until = now() - interval '1 second',
    available_at = now() - interval '1 minute' where id = second_job.id;
  perform public.claim_campaign_dispatches(1, fixture_campaign);
  if public.start_campaign_dispatch(second_job.id, second_job.lease_token) then
    raise exception 'Expired token could still dispatch';
  end if;
  select * into second_job from public.campaign_dispatches where id = second_job.id;
  if second_job.state <> 'leased' then raise exception 'Pre-send lease was not reclaimed'; end if;
  if not public.start_campaign_dispatch(second_job.id, second_job.lease_token) then raise exception 'Reclaimed lease failed'; end if;
  perform public.finish_campaign_dispatch(second_job.id, second_job.lease_token, 'retry', null, 'rate_limited');
  if (select d.state from public.campaign_dispatches d where d.id = second_job.id) <> 'retry_wait' then
    raise exception 'Retry was not scheduled';
  end if;

  -- Once dispatch might have happened, a lost worker becomes unknown, never queued.
  perform public.start_campaign_dispatch(third_job.id, third_job.lease_token);
  update public.campaign_dispatches set leased_until = now() - interval '1 second' where id = third_job.id;
  if exists (select 1 from public.claim_campaign_dispatches(1, fixture_campaign) d where d.id = third_job.id) then
    raise exception 'Unknown send was replayed';
  end if;
  if (select d.state from public.campaign_dispatches d where d.id = third_job.id) <> 'unknown' then
    raise exception 'Lost send not marked unknown';
  end if;
  -- A delayed definitive acceptance can reconcile the original attempt.
  perform public.finish_campaign_dispatch(third_job.id, third_job.lease_token, 'accepted', 'wamid.queue-test-3');
  result := public.campaign_progress(fixture_campaign);
  if (result->>'accepted')::int <> 2 or (result->>'failed')::int <> 1 then
    raise exception 'Progress lost partial outcomes: %', result;
  end if;

  for retry_number in 2..5 loop
    update public.campaign_dispatches set available_at = now() - interval '1 minute' where id = second_job.id;
    select * into second_job from public.claim_campaign_dispatches(1, fixture_campaign) d where d.id = second_job.id;
    if second_job.id is null then raise exception 'Retry recipient was not claimed'; end if;
    if not public.start_campaign_dispatch(second_job.id, second_job.lease_token) then
      raise exception 'Retry dispatch could not start';
    end if;
    perform public.finish_campaign_dispatch(second_job.id, second_job.lease_token, 'retry', null, 'rate_limited');
  end loop;
  if not exists (select 1 from public.campaign_dispatches d
    where d.id = second_job.id and d.state = 'failed' and d.attempts = 5) then
    raise exception 'Retries exceeded the bounded attempt count';
  end if;
  delete from public.consented_contacts where id = fourth_job.consented_contact_id;
  if public.start_campaign_dispatch(fourth_job.id, fourth_job.lease_token) then
    raise exception 'Deleted consent was dispatched';
  end if;
  if (select d.state from public.campaign_dispatches d where d.id = fourth_job.id) <> 'cancelled' then
    raise exception 'Missing consent not recorded';
  end if;

  insert into public.message_jobs(tenant_id, campaign_id, template_id, status)
    values (tenant_a, other_campaign, template_id, 'failed');
  begin
    perform public.enqueue_campaign(other_campaign, actor, expected);
    raise exception 'Legacy campaign was replayed';
  exception when object_not_in_prerequisite_state then null; end;
  perform set_config('test.queue_campaign', fixture_campaign::text, true);
  perform set_config('test.queue_actor', actor::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.queue_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.claim_campaign_dispatches(1, current_setting('test.queue_campaign')::uuid);
    raise exception 'Authenticated caller claimed worker jobs';
  exception when insufficient_privilege then null; end;
  begin
    update public.campaign_dispatches set state = 'queued';
    raise exception 'Authenticated caller rewrote dispatch state';
  exception when insufficient_privilege then null; end;
end;
$$;
rollback;
