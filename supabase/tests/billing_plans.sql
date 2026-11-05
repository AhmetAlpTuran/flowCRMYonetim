-- Plans, trials, lapsed subscriptions and every plan limit. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.as_user(p_user text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', p_user,
    'email', 'u-' || p_user || '@example.invalid')::text, true);
$$;
create function pg_temp.prepare_job(p_tenant uuid, p_connection uuid, p_phone text) returns text
language plpgsql as $$
declare conversation uuid; input_id uuid := gen_random_uuid(); job public.bot_reply_jobs; ctx jsonb; outcome text;
begin
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (p_tenant, p_connection, p_phone, 'Plan', 'open') returning id into conversation;
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (input_id, p_tenant, conversation, p_connection, 'Customer', 'Merhaba', true);
  update public.conversations set last_customer_message_at = now() where id = conversation;
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id) values (p_tenant, conversation, input_id);
  select * into job from public.claim_bot_reply();
  ctx := public.bot_reply_context(job.id, job.lease_token);
  outcome := public.prepare_bot_reply(job.id, job.lease_token, (ctx->>'automation_revision')::bigint,
    (ctx->>'context_revision')::bigint, 'gpt-4o-mini', 3000, 999999999);
  update public.bot_reply_jobs set state = 'cancelled', lease_token = null, leased_until = null where id = job.id;
  return outcome;
end;
$$;

do $$
declare owner_id uuid := gen_random_uuid(); member uuid := gen_random_uuid(); extra uuid := gen_random_uuid();
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (owner_id, 'u-' || owner_id || '@example.invalid', now()),
    (member, 'u-' || member || '@example.invalid', now()),
    (extra, 'u-' || extra || '@example.invalid', now());
  insert into public.billing_plans(key, name, seats, whatsapp_numbers, bots, ai_monthly_tokens, campaign_messages_monthly, is_public)
    values ('fixture_small', 'Küçük', 2, 1, 2, 5000, 3, false);
  perform set_config('test.owner', owner_id::text, true);
  perform set_config('test.member', member::text, true);
  perform set_config('test.extra', extra::text, true);
end;
$$;

-- A new business starts a 14-day Profesyonel trial.
set local role authenticated;
select pg_temp.as_user(current_setting('test.owner'));
select set_config('test.t', public.create_business('Plan Galeri', null)::text, true);
do $$
declare t uuid := current_setting('test.t')::uuid; overview jsonb;
begin
  overview := public.tenant_billing_overview(t);
  if overview->>'status' <> 'trialing' or overview->'plan'->>'key' <> 'pro'
    or (overview->>'trial_ends_at')::timestamptz not between now() + interval '13 days' and now() + interval '15 days' then
    raise exception 'New business is not on a Profesyonel trial: %', overview;
  end if;
  if (overview->'limits'->>'seats')::int <> 5 or (overview->'usage'->>'seats')::int <> 1
    or (overview->'usage'->>'bots')::int <> 1 or jsonb_array_length(overview->'plans') <> 3 then
    raise exception 'Overview limits or usage wrong: %', overview;
  end if;
  if not exists (select 1 from public.billing_plans where key = 'business') then
    raise exception 'Plan catalog not readable';
  end if;
  begin
    update public.tenant_subscriptions set status = 'active' where tenant_id = t;
    raise exception 'Client changed its own subscription';
  exception when insufficient_privilege then null;
  end;
end;
$$;
select pg_temp.as_user(current_setting('test.member'));
do $$
begin
  perform public.tenant_billing_overview(current_setting('test.t')::uuid);
  raise exception 'A non-member read the billing overview';
exception when insufficient_privilege then null;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
update public.tenant_subscriptions set plan_key = 'fixture_small', status = 'active'
  where tenant_id = current_setting('test.t')::uuid;

-- Seats: 2. One more member fits; the third is refused on every path.
set local role authenticated;
select pg_temp.as_user(current_setting('test.owner'));
do $$
declare t uuid := current_setting('test.t')::uuid;
begin
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions)
    values (t, current_setting('test.member')::uuid, 'user', array['inbox']);
  -- Changing an existing member is not a new seat.
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions)
    values (t, current_setting('test.member')::uuid, 'user', array['inbox', 'bot'])
    on conflict (tenant_id, user_id) do update set permissions = excluded.permissions;
  begin
    insert into public.tenant_memberships(tenant_id, user_id, role, permissions)
      values (t, current_setting('test.extra')::uuid, 'user', array['inbox']);
    raise exception 'Third seat accepted';
  exception when sqlstate 'P0020' then
    if sqlerrm not like '%seats%' then raise; end if;
  end;
  begin
    perform public.create_tenant_invite(t, 'yeni@example.invalid', 'user', array['inbox']);
    raise exception 'Invite beyond the seat limit accepted';
  exception when sqlstate 'P0020' then null;
  end;
  -- Bots: 2 = the main bot and one extra.
  perform public.save_bot_profile(t, gen_random_uuid(), 'Servis', 'Net', 'Türkçe', 'x', 'gpt-4o-mini', 0.3, 6, 12, true);
  begin
    perform public.save_bot_profile(t, gen_random_uuid(), 'Fazla', 'Net', 'Türkçe', 'x', 'gpt-4o-mini', 0.3, 6, 12, true);
    raise exception 'Bot beyond the plan accepted';
  exception when sqlstate 'P0020' then null;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare t uuid := current_setting('test.t')::uuid; owner_id uuid := current_setting('test.owner')::uuid;
  first_conn uuid := gen_random_uuid(); template_id uuid := gen_random_uuid(); campaign uuid := gen_random_uuid();
  small_campaign uuid := gen_random_uuid(); expected jsonb; overview jsonb;
begin
  -- Numbers: 1. Reconnecting the same number is fine; a second number is refused.
  perform public.save_whatsapp_connection(t, owner_id, first_conn, '95501', '955011',
    '{"display_phone_number":"+90 555 000 1111","verified_name":"Plan","token_expires_at":null}',
    jsonb_build_object('key_id', 'fixture', 'ciphertext', repeat('A', 24), 'iv', repeat('A', 16)), true);
  perform public.save_whatsapp_connection(t, owner_id, first_conn, '95501', '955011',
    '{"display_phone_number":"+90 555 000 1111","verified_name":"Plan 2","token_expires_at":null}',
    jsonb_build_object('key_id', 'fixture', 'ciphertext', repeat('A', 24), 'iv', repeat('A', 16)), true);
  begin
    perform public.save_whatsapp_connection(t, owner_id, gen_random_uuid(), '95501', '955012',
      '{"display_phone_number":"+90 555 000 2222","verified_name":"Ikinci","token_expires_at":null}',
      jsonb_build_object('key_id', 'fixture', 'ciphertext', repeat('A', 24), 'iv', repeat('A', 16)), false);
    raise exception 'Second number accepted';
  exception when sqlstate 'P0020' then null;
  end;

  -- Campaign messages: 3 per month. A 4-recipient campaign is refused whole; 3 fit.
  insert into public.templates(id, tenant_id, name, category, language, status, components, waba_id)
    values (template_id, t, 'plan_test', 'UTILITY', 'tr', 'APPROVED', '[{"type":"BODY","text":"Merhaba"}]', '95501');
  insert into public.consented_contacts(tenant_id, phone, full_name)
    select t, (905551110000 + n)::text, 'Kişi' from generate_series(1, 4) n;
  insert into public.campaigns(id, tenant_id, name, status, template_id) values
    (campaign, t, 'Büyük', 'draft', template_id);
  select jsonb_build_object('audience_filter', c.audience_filter, 'template_id', c.template_id,
    'template_bindings', c.template_bindings, 'connection_id', first_conn,
    'connection', jsonb_build_object('id', first_conn, 'waba_id', '95501', 'phone_number_id', '955011'),
    'template', jsonb_build_object('name', tp.name, 'language', tp.language, 'components', tp.components))
    into expected from public.campaigns c join public.templates tp on tp.id = c.template_id where c.id = campaign;
  begin
    perform public.enqueue_campaign(campaign, owner_id, expected);
    raise exception 'Campaign beyond the monthly allowance accepted';
  exception when sqlstate 'P0020' then
    if sqlerrm not like '%campaign_messages%' then raise; end if;
  end;
  if exists (select 1 from public.campaign_dispatches where tenant_id = t)
    or coalesce((select campaign_messages from public.tenant_message_usage where tenant_id = t), 0) <> 0 then
    raise exception 'A refused campaign left dispatches or usage behind';
  end if;
  delete from public.consented_contacts where tenant_id = t and phone = '905551110004';
  if public.enqueue_campaign(campaign, owner_id, expected) <> 3 then raise exception 'Campaign within the allowance refused'; end if;
  perform pg_temp.as_user(owner_id::text);
  overview := public.tenant_billing_overview(t);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  if (overview->'usage'->>'campaign_messages')::int <> 3 or (overview->'usage'->>'whatsapp_numbers')::int <> 1
    or (overview->'usage'->>'seats')::int <> 2 or (overview->'usage'->>'bots')::int <> 2 then
    raise exception 'Usage wrong: %', overview->'usage';
  end if;
  update public.campaign_dispatches set state = 'cancelled' where tenant_id = t;

  -- AI allowance: the plan's 5000 tokens apply, not the worker default.
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values (first_conn, t, 'fixture', repeat('A', 24), repeat('A', 16)) on conflict do nothing;
  insert into public.bot_settings(tenant_id, is_active) values (t, true)
    on conflict (tenant_id) do update set is_active = true;
  if pg_temp.prepare_job(t, first_conn, '905552220001') <> 'prepared' then
    raise exception 'Reservation within the plan allowance refused';
  end if;
  update public.tenant_ai_usage set consumed_tokens = 4000, reserved_tokens = 0 where tenant_id = t;
  if pg_temp.prepare_job(t, first_conn, '905552220002') <> 'quota_exhausted' then
    raise exception 'Plan AI allowance not applied';
  end if;
  update public.tenant_ai_usage set consumed_tokens = 0, reserved_tokens = 0 where tenant_id = t;
  perform set_config('test.conn', first_conn::text, true);
end;
$$;

-- Lapsed subscriptions fall to the expired limits; grace and cancelled periods keep the plan.
do $$
declare t uuid := current_setting('test.t')::uuid; conn uuid := current_setting('test.conn')::uuid;
  sub public.tenant_subscriptions;
begin
  update public.tenant_subscriptions set status = 'past_due', grace_ends_at = now() + interval '3 days' where tenant_id = t;
  if (public.tenant_plan(t)).key <> 'fixture_small' then raise exception 'Grace period lost the plan'; end if;
  update public.tenant_subscriptions set grace_ends_at = now() - interval '1 minute' where tenant_id = t;
  if (public.tenant_plan(t)).key <> 'expired' then raise exception 'Ended grace kept the plan'; end if;
  update public.tenant_subscriptions set status = 'canceled', current_period_end = now() + interval '5 days',
    grace_ends_at = null where tenant_id = t;
  if (public.tenant_plan(t)).key <> 'fixture_small' then raise exception 'Cancelled period ended early'; end if;
  update public.tenant_subscriptions set status = 'trialing', trial_ends_at = now() - interval '1 day' where tenant_id = t;
  select * into sub from public.tenant_subscriptions where tenant_id = t;
  if public.subscription_effective_status(sub) <> 'expired' or (public.tenant_plan(t)).key <> 'expired' then
    raise exception 'Ended trial kept its plan';
  end if;
  -- Expired: bots hand off (no AI tokens) and nothing new can be added, but members stay.
  if pg_temp.prepare_job(t, conn, '905552220003') <> 'quota_exhausted' then
    raise exception 'Expired business still reserved AI tokens';
  end if;
  begin
    insert into public.bot_profiles(id, tenant_id, name) values (gen_random_uuid(), t, 'Yeni');
    raise exception 'Expired business added a bot';
  exception when sqlstate 'P0020' then null;
  end;
  if (select count(*) from public.tenant_memberships where tenant_id = t) <> 2 then
    raise exception 'Expiry removed members';
  end if;
end;
$$;

-- Tenants without a subscription row (created directly, e.g. by the owner) are Pilot.
do $$
declare legacy uuid := gen_random_uuid();
begin
  insert into public.tenants(id, name) values (legacy, 'Eski');
  if (public.tenant_plan(legacy)).key <> 'pilot' then raise exception 'Tenant without subscription is not Pilot'; end if;
end;
$$;
rollback;
