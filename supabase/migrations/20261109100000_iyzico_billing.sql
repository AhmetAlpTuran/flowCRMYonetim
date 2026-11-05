-- iyzico subscriptions (roadmap Phase 3b).
--
-- An administrator saves the business's billing details, then starts a checkout for a
-- plan: the `billing` Edge Function creates a billing_checkouts row and an iyzico
-- subscription checkout form. The form renders on the static payment page
-- (docs/odeme), iyzico posts the result to `iyzico-gateway`, which confirms it with
-- iyzico and activates the subscription here. Signed iyzico webhooks then record renewals
-- and failed payments; cancellation and plan changes go through the `billing` function.
-- Every state change is applied by these service-only functions, never by clients.

create table public.tenant_billing_profiles (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  contact_name text not null check (length(btrim(contact_name)) between 1 and 80),
  contact_surname text not null check (length(btrim(contact_surname)) between 1 and 80),
  email text not null check (length(email) <= 254 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  phone text not null check (phone ~ '^\+[1-9][0-9]{9,14}$'),
  identity_number text not null check (identity_number ~ '^[0-9]{10,11}$'),
  company_name text check (company_name is null or length(company_name) <= 200),
  tax_office text check (tax_office is null or length(tax_office) <= 100),
  address text not null check (length(btrim(address)) between 5 and 400),
  city text not null check (length(btrim(city)) between 2 and 60),
  country text not null default 'Turkey' check (length(btrim(country)) between 2 and 60),
  zip_code text check (zip_code is null or zip_code ~ '^[0-9A-Za-z -]{3,10}$'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.tenant_billing_profiles enable row level security;
create policy tenant_billing_profiles_read on public.tenant_billing_profiles for select to authenticated
  using (public.is_tenant_admin(tenant_id));
revoke insert, update, delete on public.tenant_billing_profiles from anon, authenticated;
grant all on public.tenant_billing_profiles to service_role;

create table public.billing_checkouts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  plan_key text not null references public.billing_plans(key),
  billing_period text not null check (billing_period in ('monthly', 'yearly')),
  status text not null default 'created' check (status in ('created', 'ready', 'completed', 'failed')),
  provider_token text unique check (provider_token is null or length(provider_token) between 1 and 200),
  checkout_content text check (checkout_content is null or length(checkout_content) <= 200000),
  token_expires_at timestamptz,
  failure_code text check (failure_code is null or failure_code ~ '^[a-z_]{1,60}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index billing_checkouts_tenant on public.billing_checkouts(tenant_id, created_at desc);
alter table public.billing_checkouts enable row level security;
revoke all on public.billing_checkouts from anon, authenticated;
grant all on public.billing_checkouts to service_role;

create table public.billing_events (
  id bigserial primary key,
  provider text not null check (provider in ('iyzico')),
  event_key text not null check (length(event_key) between 1 and 300),
  kind text not null check (kind in ('activated', 'renewed', 'payment_failed', 'canceled', 'plan_changed')),
  tenant_id uuid references public.tenants(id) on delete set null,
  subscription_ref text,
  payload jsonb not null default '{}'::jsonb,
  applied boolean not null default false,
  received_at timestamptz not null default now(),
  unique (provider, event_key)
);
create index billing_events_tenant on public.billing_events(tenant_id, received_at desc);
alter table public.billing_events enable row level security;
revoke all on public.billing_events from anon, authenticated;
grant all on public.billing_events to service_role;

-- Administrators save the billing details iyzico requires (and invoices will need).
create function public.save_billing_profile(
  p_tenant_id uuid, p_contact_name text, p_contact_surname text, p_email text, p_phone text,
  p_identity_number text, p_company_name text, p_tax_office text, p_address text, p_city text,
  p_zip_code text default null
) returns public.tenant_billing_profiles language plpgsql security definer set search_path = '' as $$
declare saved public.tenant_billing_profiles;
  clean_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
begin
  if p_tenant_id is null or not public.is_tenant_admin(p_tenant_id) then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  -- Turkish numbers may be typed as 05xx or 5xx.
  if clean_phone ~ '^0[1-9][0-9]{9}$' then clean_phone := '+9' || clean_phone;
  elsif clean_phone ~ '^[1-9][0-9]{9}$' then clean_phone := '+90' || clean_phone;
  elsif clean_phone ~ '^90[1-9][0-9]{9}$' then clean_phone := '+' || clean_phone;
  end if;
  begin
    insert into public.tenant_billing_profiles(tenant_id, contact_name, contact_surname, email, phone,
        identity_number, company_name, tax_office, address, city, zip_code, updated_by, updated_at)
      values (p_tenant_id, btrim(p_contact_name), btrim(p_contact_surname), lower(btrim(p_email)), clean_phone,
        btrim(p_identity_number), nullif(btrim(p_company_name), ''), nullif(btrim(p_tax_office), ''),
        btrim(p_address), btrim(p_city), nullif(btrim(p_zip_code), ''), auth.uid(), now())
      on conflict (tenant_id) do update set contact_name = excluded.contact_name,
        contact_surname = excluded.contact_surname, email = excluded.email, phone = excluded.phone,
        identity_number = excluded.identity_number, company_name = excluded.company_name,
        tax_office = excluded.tax_office, address = excluded.address, city = excluded.city,
        zip_code = excluded.zip_code, updated_by = excluded.updated_by, updated_at = now()
      returning * into saved;
  exception when check_violation or not_null_violation then
    raise exception 'Invalid billing details' using errcode = '22023';
  end;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (p_tenant_id, auth.uid(), 'billing.profile_saved', p_tenant_id, '{}'::jsonb);
  return saved;
end;
$$;

-- The Edge Function verified the caller's session; this checks the caller is an
-- administrator and the checkout can start, and returns everything iyzico needs.
create function public.begin_billing_checkout(p_tenant_id uuid, p_actor_id uuid, p_plan_key text, p_period text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare plan public.billing_plans; profile public.tenant_billing_profiles; sub public.tenant_subscriptions;
  checkout public.billing_checkouts; code text;
begin
  perform public.require_service_role();
  if not exists (select 1 from public.tenant_memberships where tenant_id = p_tenant_id and user_id = p_actor_id
      and role = 'admin') then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if p_period is null or p_period not in ('monthly', 'yearly') then
    raise exception 'Invalid billing period' using errcode = '22023';
  end if;
  select * into plan from public.billing_plans where key = p_plan_key and is_public;
  code := case p_period when 'monthly' then plan.iyzico_monthly_plan_code else plan.iyzico_yearly_plan_code end;
  if plan.key is null or coalesce(code, '') = '' then
    raise exception 'Plan not available for online payment' using errcode = 'P0021', hint = 'plan_unavailable';
  end if;
  select * into profile from public.tenant_billing_profiles where tenant_id = p_tenant_id;
  if not found then
    raise exception 'Billing details required' using errcode = 'P0021', hint = 'billing_profile_required';
  end if;
  select * into sub from public.tenant_subscriptions where tenant_id = p_tenant_id for update;
  if found and sub.provider = 'iyzico' and public.subscription_effective_status(sub) in ('active', 'past_due') then
    raise exception 'Already subscribed; change the plan instead' using errcode = 'P0021', hint = 'already_subscribed';
  end if;
  if (select count(*) from public.billing_checkouts where tenant_id = p_tenant_id
      and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Too many checkouts' using errcode = 'P0021', hint = 'checkout_rate_limited';
  end if;
  insert into public.billing_checkouts(tenant_id, plan_key, billing_period, created_by)
    values (p_tenant_id, plan.key, p_period, p_actor_id) returning * into checkout;
  return jsonb_build_object('checkout_id', checkout.id, 'pricing_plan_code', code, 'plan_name', plan.name,
    'customer', jsonb_build_object('name', profile.contact_name, 'surname', profile.contact_surname,
      'email', profile.email, 'gsm_number', profile.phone, 'identity_number', profile.identity_number,
      'address', profile.address, 'city', profile.city, 'country', profile.country, 'zip_code', profile.zip_code,
      'contact_name', btrim(profile.contact_name || ' ' || profile.contact_surname)));
end;
$$;

create function public.ready_billing_checkout(p_checkout_id uuid, p_token text, p_content text, p_expires_in integer)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  update public.billing_checkouts set status = 'ready', provider_token = p_token, checkout_content = p_content,
    token_expires_at = now() + make_interval(secs => least(greatest(coalesce(p_expires_in, 1800), 60), 3600)),
    updated_at = now()
    where id = p_checkout_id and status = 'created';
  return found;
end;
$$;

create function public.fail_billing_checkout(p_checkout_id uuid, p_code text)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  update public.billing_checkouts set status = 'failed', checkout_content = null,
    failure_code = case when coalesce(p_code, '') ~ '^[a-z_]{1,60}$' then p_code else 'provider_error' end,
    updated_at = now()
    where id = p_checkout_id and status in ('created', 'ready');
  return found;
end;
$$;

-- The payment page loads the form while the iyzico token is valid.
create function public.billing_checkout_content(p_checkout_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare checkout public.billing_checkouts; plan_name text;
begin
  perform public.require_service_role();
  select * into checkout from public.billing_checkouts where id = p_checkout_id;
  if not found or checkout.status <> 'ready' or checkout.token_expires_at <= now() then
    return jsonb_build_object('status', case when found and checkout.status = 'completed' then 'completed' else 'expired' end);
  end if;
  select name into plan_name from public.billing_plans where key = checkout.plan_key;
  return jsonb_build_object('status', 'ready', 'content', checkout.checkout_content, 'plan_name', plan_name,
    'billing_period', checkout.billing_period);
end;
$$;

-- Applies one state change to a business's subscription.
create function public.apply_subscription_change(
  p_tenant_id uuid, p_kind text, p_plan_key text default null, p_period text default null,
  p_subscription_ref text default null, p_customer_ref text default null
) returns void language plpgsql security invoker set search_path = '' as $$
declare sub public.tenant_subscriptions; period_length interval;
begin
  perform public.require_service_role();
  select * into sub from public.tenant_subscriptions where tenant_id = p_tenant_id for update;
  if not found then
    insert into public.tenant_subscriptions(tenant_id, plan_key, status, provider)
      values (p_tenant_id, coalesce(p_plan_key, 'pilot'), 'pilot', 'manual') returning * into sub;
  end if;
  period_length := case coalesce(p_period, sub.billing_period, 'monthly') when 'yearly' then interval '1 year'
    else interval '1 month' end;
  if p_kind = 'activated' then
    -- Paid through the next period, with a few days of slack for the renewal webhook.
    update public.tenant_subscriptions set plan_key = p_plan_key, status = 'active', billing_period = p_period,
      provider = 'iyzico', provider_subscription_ref = p_subscription_ref, provider_customer_ref = p_customer_ref,
      current_period_end = now() + period_length + interval '3 days', trial_ends_at = null,
      grace_ends_at = null, canceled_at = null, updated_at = now()
      where tenant_id = p_tenant_id;
  elsif p_kind = 'renewed' then
    update public.tenant_subscriptions set status = 'active',
      current_period_end = now() + period_length + interval '3 days', grace_ends_at = null, updated_at = now()
      where tenant_id = p_tenant_id and status <> 'canceled';
  elsif p_kind = 'payment_failed' then
    update public.tenant_subscriptions set status = 'past_due',
      grace_ends_at = coalesce(case when status = 'past_due' then grace_ends_at end, now() + interval '7 days'),
      updated_at = now()
      where tenant_id = p_tenant_id and status in ('active', 'past_due');
  elsif p_kind = 'canceled' then
    update public.tenant_subscriptions set status = 'canceled', canceled_at = now(),
      current_period_end = greatest(coalesce(current_period_end, now()), coalesce(grace_ends_at, now())),
      updated_at = now()
      where tenant_id = p_tenant_id;
  elsif p_kind = 'plan_changed' then
    if not exists (select 1 from public.billing_plans where key = p_plan_key) then
      raise exception 'Unknown plan' using errcode = '22023';
    end if;
    update public.tenant_subscriptions set plan_key = p_plan_key, updated_at = now()
      where tenant_id = p_tenant_id;
  else
    raise exception 'Unknown subscription change' using errcode = '22023';
  end if;
  insert into public.tenant_audit_events(tenant_id, action, resource_id, details)
    values (p_tenant_id, 'billing.subscription_' || p_kind, p_tenant_id,
      jsonb_strip_nulls(jsonb_build_object('plan_key', p_plan_key, 'billing_period', p_period)));
end;
$$;

-- iyzico's checkout result (already confirmed with iyzico by token). Idempotent: a
-- repeated callback for the same token changes nothing.
create function public.complete_billing_checkout(
  p_checkout_id uuid, p_token text, p_success boolean, p_subscription_ref text, p_customer_ref text,
  p_failure_code text default null
) returns text language plpgsql security invoker set search_path = '' as $$
declare checkout public.billing_checkouts;
begin
  perform public.require_service_role();
  select * into checkout from public.billing_checkouts where id = p_checkout_id for update;
  if not found or checkout.provider_token is distinct from p_token then return 'unknown'; end if;
  if checkout.status = 'completed' then return 'completed'; end if;
  if checkout.status <> 'ready' then return checkout.status; end if;
  if not coalesce(p_success, false) or coalesce(p_subscription_ref, '') = '' then
    update public.billing_checkouts set status = 'failed', checkout_content = null,
      failure_code = case when coalesce(p_failure_code, '') ~ '^[a-z_]{1,60}$' then p_failure_code else 'payment_failed' end,
      updated_at = now() where id = checkout.id;
    return 'failed';
  end if;
  update public.billing_checkouts set status = 'completed', checkout_content = null, updated_at = now()
    where id = checkout.id;
  insert into public.billing_events(provider, event_key, kind, tenant_id, subscription_ref, payload, applied)
    values ('iyzico', 'checkout:' || checkout.id, 'activated', checkout.tenant_id, p_subscription_ref,
      jsonb_build_object('plan_key', checkout.plan_key, 'billing_period', checkout.billing_period), true)
    on conflict (provider, event_key) do nothing;
  perform public.apply_subscription_change(checkout.tenant_id, 'activated', checkout.plan_key,
    checkout.billing_period, p_subscription_ref, p_customer_ref);
  return 'completed';
end;
$$;

-- A verified iyzico webhook (renewal or failed payment). Each event applies once;
-- events for an unknown subscription are kept for the owner to review.
create function public.apply_billing_webhook(p_event_key text, p_kind text, p_subscription_ref text, p_payload jsonb)
returns text language plpgsql security invoker set search_path = '' as $$
declare target uuid; event_id bigint;
begin
  perform public.require_service_role();
  if p_kind not in ('renewed', 'payment_failed') or coalesce(p_subscription_ref, '') = '' then
    raise exception 'Invalid billing event' using errcode = '22023';
  end if;
  select tenant_id into target from public.tenant_subscriptions
    where provider = 'iyzico' and provider_subscription_ref = p_subscription_ref;
  insert into public.billing_events(provider, event_key, kind, tenant_id, subscription_ref, payload, applied)
    values ('iyzico', p_event_key, p_kind, target, p_subscription_ref, coalesce(p_payload, '{}'::jsonb), target is not null)
    on conflict (provider, event_key) do nothing
    returning id into event_id;
  if event_id is null then return 'duplicate'; end if;
  if target is null then return 'unmatched'; end if;
  perform public.apply_subscription_change(target, p_kind);
  return 'applied';
end;
$$;

-- For cancel and plan changes: the caller must be an administrator of a business with
-- a live iyzico subscription.
create function public.billing_subscription_for_actor(p_tenant_id uuid, p_actor_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare sub public.tenant_subscriptions;
begin
  perform public.require_service_role();
  if not exists (select 1 from public.tenant_memberships where tenant_id = p_tenant_id and user_id = p_actor_id
      and role = 'admin') then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  select * into sub from public.tenant_subscriptions where tenant_id = p_tenant_id;
  if not found or sub.provider is distinct from 'iyzico' or sub.provider_subscription_ref is null
    or public.subscription_effective_status(sub) not in ('active', 'past_due') then
    raise exception 'No online subscription' using errcode = 'P0021', hint = 'no_online_subscription';
  end if;
  return jsonb_build_object('subscription_ref', sub.provider_subscription_ref, 'plan_key', sub.plan_key,
    'billing_period', sub.billing_period);
end;
$$;

-- The pricing plan code for a plan change within the same billing period.
create function public.billing_plan_code(p_plan_key text, p_period text)
returns text language sql stable security invoker set search_path = '' as $$
  select case p_period when 'yearly' then iyzico_yearly_plan_code else iyzico_monthly_plan_code end
  from public.billing_plans where key = p_plan_key and is_public;
$$;

-- The overview also tells the app how the subscription is paid and whether billing
-- details exist.
create or replace function public.tenant_billing_overview(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare sub public.tenant_subscriptions; plan public.billing_plans; subscribed public.billing_plans;
  period date := date_trunc('month', now() at time zone 'UTC')::date;
begin
  if p_tenant_id is null or not public.is_tenant_admin(p_tenant_id) then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  select * into sub from public.tenant_subscriptions where tenant_id = p_tenant_id;
  plan := public.tenant_plan(p_tenant_id);
  select * into subscribed from public.billing_plans where key = coalesce(sub.plan_key, 'pilot');
  return jsonb_build_object(
    'status', public.subscription_effective_status(sub),
    'plan', jsonb_build_object('key', subscribed.key, 'name', subscribed.name,
      'monthly_price_try', subscribed.monthly_price_try, 'yearly_price_try', subscribed.yearly_price_try),
    'billing_period', sub.billing_period,
    'provider', sub.provider,
    'has_billing_profile', exists (select 1 from public.tenant_billing_profiles where tenant_id = p_tenant_id),
    'trial_ends_at', sub.trial_ends_at,
    'current_period_end', sub.current_period_end,
    'grace_ends_at', sub.grace_ends_at,
    'limits', jsonb_build_object('seats', plan.seats, 'whatsapp_numbers', plan.whatsapp_numbers,
      'bots', plan.bots, 'ai_monthly_tokens', plan.ai_monthly_tokens,
      'campaign_messages_monthly', plan.campaign_messages_monthly),
    'usage', jsonb_build_object(
      'seats', (select count(*) from public.tenant_memberships where tenant_id = p_tenant_id),
      'whatsapp_numbers', (select count(*) from public.whatsapp_connections where tenant_id = p_tenant_id),
      'bots', 1 + (select count(*) from public.bot_profiles where tenant_id = p_tenant_id),
      'ai_tokens', coalesce((select consumed_tokens + reserved_tokens from public.tenant_ai_usage
        where tenant_id = p_tenant_id and period_start = period), 0),
      'campaign_messages', coalesce((select campaign_messages from public.tenant_message_usage
        where tenant_id = p_tenant_id and period_start = period), 0)),
    'plans', (select coalesce(jsonb_agg(jsonb_build_object('key', p.key, 'name', p.name,
        'description', p.description, 'monthly_price_try', p.monthly_price_try,
        'yearly_price_try', p.yearly_price_try, 'seats', p.seats, 'whatsapp_numbers', p.whatsapp_numbers,
        'bots', p.bots, 'ai_monthly_tokens', p.ai_monthly_tokens,
        'campaign_messages_monthly', p.campaign_messages_monthly,
        'online_monthly', coalesce(p.iyzico_monthly_plan_code, '') <> '',
        'online_yearly', coalesce(p.iyzico_yearly_plan_code, '') <> '') order by p.sort_order), '[]'::jsonb)
      from public.billing_plans p where p.is_public)
  );
end;
$$;

revoke all on function public.save_billing_profile(uuid, text, text, text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.save_billing_profile(uuid, text, text, text, text, text, text, text, text, text, text) to authenticated;
revoke all on function public.begin_billing_checkout(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.ready_billing_checkout(uuid, text, text, integer) from public, anon, authenticated;
revoke all on function public.fail_billing_checkout(uuid, text) from public, anon, authenticated;
revoke all on function public.billing_checkout_content(uuid) from public, anon, authenticated;
revoke all on function public.apply_subscription_change(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.complete_billing_checkout(uuid, text, boolean, text, text, text) from public, anon, authenticated;
revoke all on function public.apply_billing_webhook(text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.billing_subscription_for_actor(uuid, uuid) from public, anon, authenticated;
revoke all on function public.billing_plan_code(text, text) from public, anon, authenticated;
grant execute on function public.begin_billing_checkout(uuid, uuid, text, text) to service_role;
grant execute on function public.ready_billing_checkout(uuid, text, text, integer) to service_role;
grant execute on function public.fail_billing_checkout(uuid, text) to service_role;
grant execute on function public.billing_checkout_content(uuid) to service_role;
grant execute on function public.apply_subscription_change(uuid, text, text, text, text, text) to service_role;
grant execute on function public.complete_billing_checkout(uuid, text, boolean, text, text, text) to service_role;
grant execute on function public.apply_billing_webhook(text, text, text, jsonb) to service_role;
grant execute on function public.billing_subscription_for_actor(uuid, uuid) to service_role;
grant execute on function public.billing_plan_code(text, text) to service_role;

-- The latest unfinished checkout of a business, so the app can re-check a payment
-- whose callback never arrived (for example when iyzico was briefly unreachable).
create function public.pending_billing_checkout(p_tenant_id uuid, p_actor_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare checkout public.billing_checkouts;
begin
  perform public.require_service_role();
  if not exists (select 1 from public.tenant_memberships where tenant_id = p_tenant_id and user_id = p_actor_id
      and role = 'admin') then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  select * into checkout from public.billing_checkouts
    where tenant_id = p_tenant_id and status = 'ready' and created_at > now() - interval '1 day'
    order by created_at desc limit 1;
  if not found then return null; end if;
  return jsonb_build_object('checkout_id', checkout.id, 'token', checkout.provider_token);
end;
$$;
revoke all on function public.pending_billing_checkout(uuid, uuid) from public, anon, authenticated;
grant execute on function public.pending_billing_checkout(uuid, uuid) to service_role;
