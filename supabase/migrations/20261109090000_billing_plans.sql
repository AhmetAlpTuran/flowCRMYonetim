-- Plans, subscriptions and plan limits (roadmap Phase 3a).
--
-- billing_plans is the price list (TRY, VAT excluded); the owner can change prices and
-- limits with plain updates. tenant_subscriptions holds each business's plan and status.
-- A business without a subscription row (created before billing) is on the
-- owner-managed Pilot plan. New businesses start a 14-day Profesyonel trial.
-- Limits are enforced in the database, whatever the write path:
--   seats (memberships), WhatsApp numbers, bots (main + extra), campaign messages per
--   month, and the AI token allowance (prepare_bot_reply). When a subscription lapses
--   the business falls to the "expired" limits: existing members, numbers and bots stay,
--   nothing new can be added, bots hand off and campaigns stop; agents can still reply
--   in the inbox. Contacts are not limited: inbound chats create them automatically.

create table public.billing_plans (
  key text primary key check (key ~ '^[a-z_]{2,30}$'),
  name text not null check (length(name) between 1 and 60),
  description text not null default '',
  monthly_price_try numeric(10, 2) not null default 0 check (monthly_price_try >= 0),
  yearly_price_try numeric(10, 2) check (yearly_price_try is null or yearly_price_try >= 0),
  seats integer not null check (seats >= 0),
  whatsapp_numbers integer not null check (whatsapp_numbers >= 0),
  bots integer not null check (bots >= 0),
  ai_monthly_tokens bigint not null check (ai_monthly_tokens >= 0),
  campaign_messages_monthly integer not null check (campaign_messages_monthly >= 0),
  is_public boolean not null default true,
  sort_order integer not null default 0,
  iyzico_monthly_plan_code text,
  iyzico_yearly_plan_code text,
  updated_at timestamptz not null default now()
);
-- Starting prices for the pilot; adjust with: update public.billing_plans set ... where key = '...';
insert into public.billing_plans(key, name, description, monthly_price_try, yearly_price_try, seats,
    whatsapp_numbers, bots, ai_monthly_tokens, campaign_messages_monthly, is_public, sort_order) values
  ('starter', 'Başlangıç', 'Tek numara ve küçük ekipler için.', 1490, 14900, 2, 1, 1, 3000000, 1000, true, 1),
  ('pro', 'Profesyonel', 'Birden fazla numara, ek botlar ve düzenli kampanyalar.', 3490, 34900, 5, 2, 3, 15000000, 10000, true, 2),
  ('business', 'İşletme', 'Büyük ekipler, şubeler ve yüksek hacim.', 7990, 79900, 15, 5, 11, 60000000, 50000, true, 3),
  ('pilot', 'Pilot', 'Pilot işletmeler için yönetici tarafından atanır.', 0, null, 50, 10, 11, 15000000, 100000, false, 90),
  ('expired', 'Süresi doldu', 'Abonelik sona erdi.', 0, null, 0, 0, 0, 0, 0, false, 99);
alter table public.billing_plans enable row level security;
create policy billing_plans_read on public.billing_plans for select to authenticated using (true);
revoke insert, update, delete on public.billing_plans from anon, authenticated;
grant all on public.billing_plans to service_role;

create table public.tenant_subscriptions (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  plan_key text not null references public.billing_plans(key),
  status text not null check (status in ('pilot', 'trialing', 'active', 'past_due', 'canceled', 'expired')),
  billing_period text check (billing_period is null or billing_period in ('monthly', 'yearly')),
  trial_ends_at timestamptz,
  current_period_end timestamptz,
  grace_ends_at timestamptz,
  canceled_at timestamptz,
  provider text check (provider is null or provider in ('iyzico', 'manual')),
  provider_customer_ref text,
  provider_subscription_ref text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status <> 'trialing' or trial_ends_at is not null)
);
alter table public.tenant_subscriptions enable row level security;
create policy tenant_subscriptions_read on public.tenant_subscriptions for select to authenticated
  using (public.is_tenant_admin(tenant_id));
revoke insert, update, delete on public.tenant_subscriptions from anon, authenticated;
grant all on public.tenant_subscriptions to service_role;
-- Businesses that predate billing stay on the Pilot plan until the owner moves them.
insert into public.tenant_subscriptions(tenant_id, plan_key, status, provider)
  select id, 'pilot', 'pilot', 'manual' from public.tenants
  on conflict (tenant_id) do nothing;

create table public.tenant_message_usage (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  period_start date not null,
  campaign_messages integer not null default 0 check (campaign_messages >= 0),
  primary key (tenant_id, period_start)
);
alter table public.tenant_message_usage enable row level security;
revoke all on public.tenant_message_usage from anon, authenticated;
grant all on public.tenant_message_usage to service_role;

-- The status that applies now: a trial, grace period or cancelled period ends by
-- time alone, without a write.
create function public.subscription_effective_status(s public.tenant_subscriptions)
returns text language sql stable set search_path = '' as $$
  select case
    when s.tenant_id is null then 'pilot'
    when s.status in ('pilot', 'active') then s.status
    when s.status = 'trialing' and s.trial_ends_at > now() then 'trialing'
    when s.status = 'past_due' and coalesce(s.grace_ends_at, s.current_period_end) > now() then 'past_due'
    when s.status = 'canceled' and s.current_period_end > now() then 'canceled'
    else 'expired'
  end;
$$;

-- The plan whose limits apply to a business right now.
create function public.tenant_plan(p_tenant_id uuid)
returns public.billing_plans language plpgsql stable security definer set search_path = '' as $$
declare sub public.tenant_subscriptions; plan public.billing_plans;
begin
  select * into sub from public.tenant_subscriptions where tenant_id = p_tenant_id;
  if not found then
    select * into plan from public.billing_plans where key = 'pilot';
  elsif public.subscription_effective_status(sub) = 'expired' then
    select * into plan from public.billing_plans where key = 'expired';
  else
    select * into plan from public.billing_plans where key = sub.plan_key;
  end if;
  return plan;
end;
$$;

create function public.raise_plan_limit(p_kind text)
returns void language plpgsql set search_path = '' as $$
begin
  raise exception 'Plan limit reached: %', p_kind using errcode = 'P0020', hint = 'plan_limit:' || p_kind;
end;
$$;

create function public.enforce_seat_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Upserts of an existing member (role or permission changes) are not new seats.
  if exists (select 1 from public.tenant_memberships where tenant_id = new.tenant_id and user_id = new.user_id) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('seats:' || new.tenant_id::text));
  if (select count(*) from public.tenant_memberships where tenant_id = new.tenant_id)
      >= (public.tenant_plan(new.tenant_id)).seats then
    perform public.raise_plan_limit('seats');
  end if;
  return new;
end;
$$;
create trigger tenant_memberships_seat_limit before insert on public.tenant_memberships
  for each row execute function public.enforce_seat_limit();

create function public.enforce_number_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- save_whatsapp_connection upserts by ID; reconnecting a number is not a new one.
  if exists (select 1 from public.whatsapp_connections where id = new.id) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('numbers:' || new.tenant_id::text));
  if (select count(*) from public.whatsapp_connections where tenant_id = new.tenant_id)
      >= (public.tenant_plan(new.tenant_id)).whatsapp_numbers then
    perform public.raise_plan_limit('whatsapp_numbers');
  end if;
  return new;
end;
$$;
create trigger whatsapp_connections_number_limit before insert on public.whatsapp_connections
  for each row execute function public.enforce_number_limit();

-- The main bot counts as one of the plan's bots.
create function public.enforce_bot_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.bot_profiles where tenant_id = new.tenant_id) + 1
      >= (public.tenant_plan(new.tenant_id)).bots then
    perform public.raise_plan_limit('bots');
  end if;
  return new;
end;
$$;
create trigger bot_profiles_bot_limit before insert on public.bot_profiles
  for each row execute function public.enforce_bot_limit();

-- Campaign messages: each enqueued recipient (not those failed for an invalid phone)
-- counts for the month. Over the allowance the whole enqueue is refused.
create function public.count_campaign_messages()
returns trigger language plpgsql security definer set search_path = '' as $$
declare item record; period date := date_trunc('month', now() at time zone 'UTC')::date; used integer;
begin
  for item in select tenant_id, count(*)::integer as queued from new_dispatches
      where state = 'queued' group by tenant_id loop
    insert into public.tenant_message_usage(tenant_id, period_start, campaign_messages)
      values (item.tenant_id, period, item.queued)
      on conflict (tenant_id, period_start) do update
      set campaign_messages = public.tenant_message_usage.campaign_messages + excluded.campaign_messages
      returning campaign_messages into used;
    if used > (public.tenant_plan(item.tenant_id)).campaign_messages_monthly then
      perform public.raise_plan_limit('campaign_messages');
    end if;
  end loop;
  return null;
end;
$$;
create trigger campaign_dispatches_message_usage after insert on public.campaign_dispatches
  referencing new table as new_dispatches for each statement execute function public.count_campaign_messages();

-- Plan, status, limits and this month's usage for the Abonelik screen (admins).
create function public.tenant_billing_overview(p_tenant_id uuid)
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
        'campaign_messages_monthly', p.campaign_messages_monthly) order by p.sort_order), '[]'::jsonb)
      from public.billing_plans p where p.is_public)
  );
end;
$$;

revoke all on function public.tenant_plan(uuid) from public, anon, authenticated;
grant execute on function public.tenant_plan(uuid) to service_role;
revoke all on function public.raise_plan_limit(text) from public, anon, authenticated;
revoke all on function public.enforce_seat_limit() from public, anon, authenticated;
revoke all on function public.enforce_number_limit() from public, anon, authenticated;
revoke all on function public.enforce_bot_limit() from public, anon, authenticated;
revoke all on function public.count_campaign_messages() from public, anon, authenticated;
revoke all on function public.tenant_billing_overview(uuid) from public, anon;
grant execute on function public.tenant_billing_overview(uuid) to authenticated;

-- Previous definitions with only the plan changes added: the AI allowance comes from the
-- plan, new businesses start a trial, and invites respect the seat limit.
CREATE OR REPLACE FUNCTION public.prepare_bot_reply(p_job_id uuid, p_lease_token uuid, p_automation_revision bigint, p_context_revision bigint, p_model text, p_reserve_tokens integer, p_default_limit bigint)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  job public.bot_reply_jobs;
  conversation public.conversations;
  version bigint;
  period date := date_trunc('month', now() at time zone 'UTC')::date;
  token_limit bigint;
  usage public.tenant_ai_usage;
begin
  perform public.require_service_role();
  if p_reserve_tokens is null or p_reserve_tokens not between 0 and 200000
    or p_default_limit is null or p_default_limit not between 0 and 1000000000000
    or (p_reserve_tokens > 0 and (p_model is null or length(p_model) not between 1 and 100)) then
    raise exception 'Invalid AI reservation' using errcode = '22023';
  end if;
  select * into job from public.bot_reply_jobs where id = p_job_id;
  if not found then return 'stale'; end if;
  select * into conversation from public.conversations where id = job.conversation_id and tenant_id = job.tenant_id for update;
  select * into job from public.bot_reply_jobs where id = p_job_id for update;
  if not found or job.state <> 'leased' or job.lease_token is distinct from p_lease_token or job.leased_until <= clock_timestamp() then
    return 'stale';
  end if;
  if job.prepared_at is not null then return 'already_prepared'; end if;
  select revision into version from public.bot_context_versions where tenant_id = job.tenant_id for share;
  if conversation.status <> 'open' or conversation.last_customer_message_id is distinct from job.input_message_id
    or conversation.automation_revision is distinct from p_automation_revision
    or version is distinct from p_context_revision
    or not exists(select 1 from public.effective_bot_settings(job.tenant_id, conversation.connection_id) where is_active) then
    return 'stale';
  end if;
  update public.bot_reply_jobs set prepared_at = now(), automation_revision = p_automation_revision,
    context_revision = p_context_revision, updated_at = now() where id = job.id;
  if p_reserve_tokens = 0 then return 'prepared'; end if;
  if job.expires_at <= clock_timestamp() then return 'window_closed'; end if;
  select monthly_token_limit into token_limit from public.tenant_ai_limits where tenant_id = job.tenant_id;
  -- An explicit per-business limit wins, then the subscribed plan's allowance, then
  -- the worker default (businesses without a subscription row).
  if token_limit is null and exists (select 1 from public.tenant_subscriptions where tenant_id = job.tenant_id) then
    token_limit := (public.tenant_plan(job.tenant_id)).ai_monthly_tokens;
  end if;
  token_limit := coalesce(token_limit, p_default_limit);
  insert into public.tenant_ai_usage(tenant_id, period_start) values(job.tenant_id, period)
    on conflict do nothing;
  select * into usage from public.tenant_ai_usage where tenant_id = job.tenant_id and period_start = period for update;
  if usage.reserved_tokens + usage.consumed_tokens + p_reserve_tokens > token_limit then
    if usage.consumed_tokens + p_reserve_tokens <= token_limit and exists (
      select 1 from public.ai_usage_reservations where tenant_id = job.tenant_id and period_start = period and status = 'reserved'
    ) then return 'quota_pending'; end if;
    return 'quota_exhausted';
  end if;
  insert into public.ai_usage_reservations(tenant_id, job_id, lease_token, period_start, model, reserved_tokens)
    values(job.tenant_id, job.id, p_lease_token, period, p_model, p_reserve_tokens);
  update public.tenant_ai_usage set reserved_tokens = reserved_tokens + p_reserve_tokens, request_count = request_count + 1
    where tenant_id = job.tenant_id and period_start = period;
  update public.bot_reply_jobs set generation_started_at = now(), leased_until = clock_timestamp() + interval '120 seconds',
    updated_at = now() where id = job.id;
  return 'prepared';
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_business(p_name text, p_brand_color text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  clean_name text := btrim(coalesce(p_name, ''));
  color text := coalesce(nullif(btrim(p_brand_color), ''), '#1F4B99');
  new_id uuid;
begin
  if uid is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if public.confirmed_auth_email() is null then
    raise exception 'Confirm your email before creating a business' using errcode = 'P0013';
  end if;
  if length(clean_name) < 2 or length(clean_name) > 80 then
    raise exception 'Business name must be 2-80 characters' using errcode = '22023';
  end if;
  if color !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Brand color must be #RRGGBB' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('create_business:' || uid::text, 0));
  if (select count(*) from public.tenants where created_by = uid) >= 3 then
    raise exception 'Business limit reached' using errcode = 'P0010';
  end if;
  insert into public.tenants(name, brand_color, features, created_by)
    values (clean_name, upper(color), public.tenant_module_keys(), uid)
    returning id into new_id;
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions)
    values (new_id, uid, 'admin', public.tenant_module_keys());
  insert into public.tenant_subscriptions(tenant_id, plan_key, status, trial_ends_at)
    values (new_id, 'pro', 'trialing', now() + interval '14 days');
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (new_id, uid, 'tenant.created', new_id, jsonb_build_object('name', clean_name));
  return new_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_tenant_invite(p_tenant_id uuid, p_email text, p_role text DEFAULT 'user'::text, p_permissions text[] DEFAULT ARRAY['inbox'::text])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid := auth.uid();
  address text := lower(btrim(coalesce(p_email, '')));
  admin boolean;
  granted text[] := coalesce(p_permissions, array[]::text[]);
  own text[];
  invite_id uuid;
begin
  if uid is null or not public.can_manage_tenant(p_tenant_id) then
    raise exception 'User management permission required' using errcode = '42501';
  end if;
  admin := public.is_tenant_admin(p_tenant_id);
  if p_role is null or p_role not in ('admin', 'user') then
    raise exception 'Invalid role' using errcode = '22023';
  end if;
  if p_role = 'admin' and not admin then
    raise exception 'Only administrators can invite administrators' using errcode = '42501';
  end if;
  if length(address) > 320 or address !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Valid email required' using errcode = '22023';
  end if;
  if cardinality(granted) > 20 or not granted <@ public.tenant_module_keys() then
    raise exception 'Unknown module permission' using errcode = '22023';
  end if;
  if p_role = 'admin' then granted := public.tenant_module_keys(); end if;
  -- Tell the inviter now rather than fail when the invite is accepted.
  if (select count(*) from public.tenant_memberships where tenant_id = p_tenant_id)
      >= (public.tenant_plan(p_tenant_id)).seats then
    perform public.raise_plan_limit('seats');
  end if;
  if not admin then
    select m.permissions into own from public.tenant_memberships m
      where m.tenant_id = p_tenant_id and m.user_id = uid;
    if not granted <@ coalesce(own, array[]::text[]) then
      raise exception 'You can only grant modules you have' using errcode = '42501';
    end if;
  end if;
  if exists (
    select 1 from public.tenant_memberships m join auth.users u on u.id = m.user_id
    where m.tenant_id = p_tenant_id and lower(u.email) = address
  ) then
    raise exception 'Already a member' using errcode = 'P0011';
  end if;
  perform 1 from public.tenants where id = p_tenant_id for update;
  if (select count(*) from public.tenant_invites where tenant_id = p_tenant_id and status = 'pending'
      and lower(email) <> address) >= 50 then
    raise exception 'Too many pending invites' using errcode = 'P0010';
  end if;
  -- Expire stale invites for this address so the partial unique index admits a new one.
  update public.tenant_invites set status = 'expired', responded_at = now()
    where tenant_id = p_tenant_id and lower(email) = address and status = 'pending' and expires_at <= now();
  insert into public.tenant_invites(tenant_id, email, role, permissions, invited_by, expires_at)
    values (p_tenant_id, address, p_role, granted, uid, now() + interval '14 days')
  on conflict (tenant_id, lower(email)) where status = 'pending'
    do update set role = excluded.role, permissions = excluded.permissions,
      invited_by = excluded.invited_by, expires_at = excluded.expires_at
  returning id into invite_id;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (p_tenant_id, uid, 'invite.created', invite_id, jsonb_build_object('role', p_role));
  return invite_id;
end;
$function$;
