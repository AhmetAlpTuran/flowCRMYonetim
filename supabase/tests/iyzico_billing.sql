-- iyzico billing: billing details, checkouts, activation, webhooks, cancel and plan change. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.as_user(p_user text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', p_user)::text, true);
$$;

do $$
declare owner_id uuid := gen_random_uuid(); member uuid := gen_random_uuid(); t uuid := gen_random_uuid();
  t2 uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values (owner_id, 'o-' || owner_id || '@example.invalid'),
    (member, 'm-' || member || '@example.invalid');
  insert into public.tenants(id, name) values (t, 'Ödeme'), (t2, 'Detaysız');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, owner_id, 'admin', public.tenant_module_keys()), (t, member, 'user', array['inbox']),
    (t2, owner_id, 'admin', public.tenant_module_keys());
  insert into public.tenant_subscriptions(tenant_id, plan_key, status, trial_ends_at)
    values (t, 'pro', 'trialing', now() + interval '10 days');
  update public.billing_plans set iyzico_monthly_plan_code = 'PRO-M', iyzico_yearly_plan_code = 'PRO-Y' where key = 'pro';
  update public.billing_plans set iyzico_monthly_plan_code = 'STARTER-M' where key = 'starter';
  perform set_config('test.owner', owner_id::text, true);
  perform set_config('test.member', member::text, true);
  perform set_config('test.t', t::text, true);
  perform set_config('test.t2', t2::text, true);
end;
$$;

set local role authenticated;
select pg_temp.as_user(current_setting('test.member'));
do $$
begin
  perform public.save_billing_profile(current_setting('test.t')::uuid, 'Ayşe', 'Yılmaz', 'a@example.com',
    '05551112233', '12345678901', null, null, 'Bağdat Cd. 1', 'İstanbul');
  raise exception 'A non-admin saved billing details';
exception when insufficient_privilege then null;
end;
$$;
select pg_temp.as_user(current_setting('test.owner'));
do $$
declare t uuid := current_setting('test.t')::uuid; saved public.tenant_billing_profiles;
begin
  begin
    perform public.save_billing_profile(t, 'Ayşe', 'Yılmaz', 'a@example.com', '123', '12345678901', null, null,
      'Bağdat Cd. 1', 'İstanbul');
    raise exception 'Invalid phone accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.save_billing_profile(t, 'Ayşe', 'Yılmaz', 'a@example.com', '05551112233', '123', null, null,
      'Bağdat Cd. 1', 'İstanbul');
    raise exception 'Invalid identity number accepted';
  exception when sqlstate '22023' then null;
  end;
  saved := public.save_billing_profile(t, ' Ayşe ', 'Yılmaz', 'A@Example.com', '0555 111 22 33', '12345678901',
    'Ödeme Ltd.', 'Kadıköy', 'Bağdat Cd. 1', 'İstanbul', '34710');
  if saved.phone <> '+905551112233' or saved.email <> 'a@example.com' or saved.contact_name <> 'Ayşe' then
    raise exception 'Billing details not normalized: %', row_to_json(saved);
  end if;
  if not (public.tenant_billing_overview(t)->>'has_billing_profile')::boolean then
    raise exception 'Overview does not see the billing details';
  end if;
  begin
    perform 1 from public.billing_checkouts;
    raise exception 'Client read checkouts';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare t uuid := current_setting('test.t')::uuid; t2 uuid := current_setting('test.t2')::uuid;
  owner_id uuid := current_setting('test.owner')::uuid; started jsonb; checkout uuid; sub public.tenant_subscriptions;
  result text; second jsonb; first_end timestamptz;
begin
  begin
    perform public.begin_billing_checkout(t, current_setting('test.member')::uuid, 'pro', 'monthly');
    raise exception 'A non-admin started a checkout';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.begin_billing_checkout(t, owner_id, 'business', 'monthly');
    raise exception 'Plan without an iyzico code accepted';
  exception when sqlstate 'P0021' then
    if sqlerrm <> 'Plan not available for online payment' then raise; end if;
  end;
  begin
    perform public.begin_billing_checkout(t2, owner_id, 'pro', 'monthly');
    raise exception 'Checkout without billing details accepted';
  exception when sqlstate 'P0021' then
    if sqlerrm <> 'Billing details required' then raise; end if;
  end;

  started := public.begin_billing_checkout(t, owner_id, 'pro', 'monthly');
  checkout := (started->>'checkout_id')::uuid;
  if started->>'pricing_plan_code' <> 'PRO-M' or started->'customer'->>'gsm_number' <> '+905551112233'
    or started->'customer'->>'contact_name' <> 'Ayşe Yılmaz' then
    raise exception 'Checkout details wrong: %', started;
  end if;
  if (public.billing_checkout_content(checkout))->>'status' <> 'expired' then
    raise exception 'A checkout without a form was served';
  end if;
  if not public.ready_billing_checkout(checkout, 'tok-1', '<script>form()</script>', 1800) then
    raise exception 'Checkout not made ready';
  end if;
  if (public.billing_checkout_content(checkout))->>'content' <> '<script>form()</script>' then
    raise exception 'Payment page cannot load the form';
  end if;

  -- The callback must present this checkout's token.
  if public.complete_billing_checkout(checkout, 'other-token', true, 'SUB-1', 'CUS-1') <> 'unknown' then
    raise exception 'A foreign token completed the checkout';
  end if;
  result := public.complete_billing_checkout(checkout, 'tok-1', true, 'SUB-1', 'CUS-1');
  select * into sub from public.tenant_subscriptions where tenant_id = t;
  if result <> 'completed' or sub.status <> 'active' or sub.provider <> 'iyzico' or sub.plan_key <> 'pro'
    or sub.provider_subscription_ref <> 'SUB-1' or sub.trial_ends_at is not null
    or sub.current_period_end not between now() + interval '1 month' and now() + interval '1 month 4 days' then
    raise exception 'Activation wrong: % %', result, row_to_json(sub);
  end if;
  if (public.billing_checkout_content(checkout))->>'status' <> 'completed'
    or (select checkout_content from public.billing_checkouts where id = checkout) is not null then
    raise exception 'Completed checkout still serves its form';
  end if;
  result := public.complete_billing_checkout(checkout, 'tok-1', true, 'SUB-1', 'CUS-1');
  if result <> 'completed'
    or (select count(*) from public.billing_events where tenant_id = t and kind = 'activated') <> 1 then
    raise exception 'Repeated callback was not idempotent';
  end if;
  begin
    perform public.begin_billing_checkout(t, owner_id, 'pro', 'yearly');
    raise exception 'Second subscription started';
  exception when sqlstate 'P0021' then
    if sqlerrm not like 'Already subscribed%' then raise; end if;
  end;

  -- Webhooks: renewals extend, failures start a 7-day grace, each event applies once.
  first_end := sub.current_period_end;
  if public.apply_billing_webhook('subscription.order.failure:ORD-1', 'payment_failed', 'SUB-1', '{}') <> 'applied' then
    raise exception 'Failure webhook not applied';
  end if;
  select * into sub from public.tenant_subscriptions where tenant_id = t;
  if sub.status <> 'past_due' or sub.grace_ends_at not between now() + interval '6 days' and now() + interval '8 days'
    or (public.tenant_plan(t)).key <> 'pro' then
    raise exception 'Failed payment did not start the grace period: %', row_to_json(sub);
  end if;
  if public.apply_billing_webhook('subscription.order.failure:ORD-1', 'payment_failed', 'SUB-1', '{}') <> 'duplicate' then
    raise exception 'Duplicate webhook applied twice';
  end if;
  if public.apply_billing_webhook('subscription.order.success:ORD-2', 'renewed', 'SUB-1', '{}') <> 'applied' then
    raise exception 'Renewal webhook not applied';
  end if;
  select * into sub from public.tenant_subscriptions where tenant_id = t;
  if sub.status <> 'active' or sub.grace_ends_at is not null or sub.current_period_end < first_end then
    raise exception 'Renewal did not restore the subscription: %', row_to_json(sub);
  end if;
  -- Separate statements: one expression would check with a snapshot taken before the insert.
  result := public.apply_billing_webhook('subscription.order.success:ORD-9', 'renewed', 'SUB-UNKNOWN', '{}');
  if result <> 'unmatched'
    or not exists (select 1 from public.billing_events where event_key = 'subscription.order.success:ORD-9' and not applied) then
    raise exception 'Unmatched webhook not kept';
  end if;
  begin
    perform public.apply_billing_webhook('x', 'activated', 'SUB-1', '{}');
    raise exception 'Webhook activated a subscription';
  exception when sqlstate '22023' then null;
  end;

  -- Plan change and cancellation (after iyzico confirmed them).
  if (public.billing_subscription_for_actor(t, owner_id))->>'subscription_ref' <> 'SUB-1'
    or public.billing_plan_code('starter', 'monthly') <> 'STARTER-M' then
    raise exception 'Subscription lookup for changes wrong';
  end if;
  perform public.apply_subscription_change(t, 'plan_changed', 'starter');
  perform public.apply_subscription_change(t, 'canceled');
  select * into sub from public.tenant_subscriptions where tenant_id = t;
  if sub.plan_key <> 'starter' or sub.status <> 'canceled' or sub.canceled_at is null
    or (public.tenant_plan(t)).key <> 'starter' then
    raise exception 'Cancel should keep the plan until the period ends: %', row_to_json(sub);
  end if;
  perform public.apply_billing_webhook('subscription.order.success:ORD-3', 'renewed', 'SUB-1', '{}');
  if (select status from public.tenant_subscriptions where tenant_id = t) <> 'canceled' then
    raise exception 'A renewal webhook revived a cancelled subscription';
  end if;
  begin
    perform public.billing_subscription_for_actor(t, owner_id);
    raise exception 'Cancelled subscription offered for changes';
  exception when sqlstate 'P0021' then null;
  end;

  -- A declined payment fails the checkout and leaves the subscription alone.
  update public.tenant_subscriptions set status = 'trialing', provider = null, trial_ends_at = now() + interval '1 day'
    where tenant_id = t;
  second := public.begin_billing_checkout(t, owner_id, 'pro', 'yearly');
  perform public.ready_billing_checkout((second->>'checkout_id')::uuid, 'tok-2', '<script></script>', 600);
  result := public.complete_billing_checkout((second->>'checkout_id')::uuid, 'tok-2', false, null, null, 'card_declined');
  if result <> 'failed'
    or (select status from public.tenant_subscriptions where tenant_id = t) <> 'trialing'
    or (select failure_code from public.billing_checkouts where id = (second->>'checkout_id')::uuid) <> 'card_declined' then
    raise exception 'Declined checkout handled wrongly';
  end if;
end;
$$;
rollback;
