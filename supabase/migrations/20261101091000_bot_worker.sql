alter table public.bot_reply_jobs
  add column prepared_at timestamptz,
  add column generation_started_at timestamptz,
  add column automation_revision bigint,
  add column context_revision bigint,
  add column expires_at timestamptz,
  add constraint bot_reply_jobs_tenant_id_id_key unique (tenant_id, id);
create index bot_jobs_active_conversation on public.bot_reply_jobs(conversation_id, state, leased_until)
  where state in ('queued', 'leased');
create index bot_jobs_expired_lease on public.bot_reply_jobs(leased_until) where state = 'leased';
create index messages_context_history on public.messages(tenant_id, conversation_id, received_at desc, id desc);
alter table public.handoff_requests
  add column bot_job_id uuid unique,
  add constraint handoff_bot_job_fk foreign key (tenant_id, bot_job_id)
    references public.bot_reply_jobs(tenant_id, id) on delete set null (bot_job_id);
alter table public.inbox_dispatches
  add column source text not null default 'human' check (source in ('human', 'bot', 'bot_handoff')),
  add column bot_job_id uuid,
  add constraint inbox_dispatch_bot_job_fk foreign key (tenant_id, bot_job_id)
    references public.bot_reply_jobs(tenant_id, id) on delete set null (bot_job_id),
  add constraint inbox_dispatch_source check (
    (source = 'human' and bot_job_id is null) or (source <> 'human' and actor_id is null)
  );
create unique index inbox_dispatch_bot_job on public.inbox_dispatches(bot_job_id) where bot_job_id is not null;

-- A future subscription update can override the operator-configured default cap.
-- Tenant members cannot raise their own quota.
create table public.tenant_ai_limits (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  monthly_token_limit bigint not null check (monthly_token_limit between 0 and 1000000000000),
  updated_at timestamptz not null default now()
);
create table public.tenant_ai_usage (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  period_start date not null,
  reserved_tokens bigint not null default 0 check (reserved_tokens >= 0),
  consumed_tokens bigint not null default 0 check (consumed_tokens >= 0),
  request_count bigint not null default 0 check (request_count >= 0),
  primary key (tenant_id, period_start)
);
create table public.ai_usage_reservations (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  job_id uuid not null,
  lease_token uuid not null,
  period_start date not null,
  model text not null check (length(model) between 1 and 100),
  reserved_tokens integer not null check (reserved_tokens between 1 and 200000),
  actual_tokens integer check (actual_tokens between 0 and 2000000),
  status text not null default 'reserved' check (status in ('reserved', 'unknown', 'settled')),
  response_id text check (length(response_id) <= 200),
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  primary key (job_id, lease_token),
  foreign key (tenant_id, period_start) references public.tenant_ai_usage(tenant_id, period_start) on delete cascade,
  check ((status = 'settled') = (actual_tokens is not null))
);
create index ai_usage_reservations_period on public.ai_usage_reservations(tenant_id, period_start);
alter table public.tenant_ai_limits enable row level security;
alter table public.tenant_ai_usage enable row level security;
alter table public.ai_usage_reservations enable row level security;
revoke all on public.tenant_ai_limits, public.tenant_ai_usage, public.ai_usage_reservations from public, anon, authenticated;
grant all on public.tenant_ai_limits, public.tenant_ai_usage, public.ai_usage_reservations to service_role;
grant select on public.tenant_ai_limits, public.tenant_ai_usage to authenticated;
create policy ai_limits_admin_read on public.tenant_ai_limits for select to authenticated using (public.is_tenant_admin(tenant_id));
create policy ai_usage_admin_read on public.tenant_ai_usage for select to authenticated using (public.is_tenant_admin(tenant_id));

create function public.mark_stale_ai_reservations(p_limit integer default 100)
returns integer language plpgsql security invoker set search_path = '' as $$
declare affected integer;
begin
  perform public.require_service_role();
  if p_limit is null or p_limit not between 1 and 1000 then
    raise exception 'Invalid batch limit' using errcode = '22023';
  end if;
  with stale as (
    select r.job_id, r.lease_token from public.ai_usage_reservations r
    where r.status = 'reserved' and r.created_at < now() - interval '5 minutes' and not exists (
      select 1 from public.bot_reply_jobs j where j.id = r.job_id and j.tenant_id = r.tenant_id
        and j.state = 'leased' and j.lease_token = r.lease_token and j.leased_until > now()
    ) order by r.created_at limit p_limit for update of r skip locked
  )
  update public.ai_usage_reservations r set status = 'unknown'
    from stale where r.job_id = stale.job_id and r.lease_token = stale.lease_token;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

create function public.settle_bot_usage(
  p_job_id uuid, p_lease_token uuid, p_usage jsonb default null,
  p_rejected boolean default false, p_response_id text default null
) returns boolean language plpgsql security invoker set search_path = '' as $$
declare reservation public.ai_usage_reservations; actual integer; input_count integer; output_count integer;
begin
  perform public.require_service_role();
  select * into reservation from public.ai_usage_reservations where job_id = p_job_id and lease_token = p_lease_token;
  if not found then return false; end if;
  if p_usage is not null then
    if p_rejected or jsonb_typeof(p_usage) <> 'object'
      or coalesce(p_usage->>'input_tokens', '') !~ '^[0-9]{1,7}$'
      or coalesce(p_usage->>'output_tokens', '') !~ '^[0-9]{1,7}$'
      or coalesce(p_usage->>'total_tokens', '') !~ '^[0-9]{1,7}$' then
      raise exception 'Invalid AI usage' using errcode = '22023';
    end if;
    input_count := (p_usage->>'input_tokens')::integer;
    output_count := (p_usage->>'output_tokens')::integer;
    actual := (p_usage->>'total_tokens')::integer;
    if actual > 2000000 or input_count + output_count <> actual then
      raise exception 'Invalid AI usage' using errcode = '22023';
    end if;
  elsif p_rejected then actual := 0;
  end if;
  -- Usage is independent of job lifetime. A human takeover can cancel a job while
  -- its provider call finishes, and that call still needs accurate settlement.
  perform 1 from public.tenant_ai_usage where tenant_id = reservation.tenant_id
    and period_start = reservation.period_start for update;
  if not found then return false; end if;
  select * into reservation from public.ai_usage_reservations
    where job_id = p_job_id and lease_token = p_lease_token for update;
  if not found then return false; end if;
  if reservation.status = 'settled' then
    return actual is null or reservation.actual_tokens = actual;
  end if;
  if actual is null then
    update public.ai_usage_reservations set status = 'unknown'
      where job_id = p_job_id and lease_token = p_lease_token;
    return true;
  end if;
  update public.tenant_ai_usage set reserved_tokens = reserved_tokens - reservation.reserved_tokens,
    consumed_tokens = consumed_tokens + actual
    where tenant_id = reservation.tenant_id and period_start = reservation.period_start;
  update public.ai_usage_reservations set status = 'settled', actual_tokens = actual,
    response_id = left(p_response_id, 200), settled_at = now()
    where job_id = p_job_id and lease_token = p_lease_token;
  return true;
end;
$$;

create function public.prepare_bot_reply(
  p_job_id uuid, p_lease_token uuid, p_automation_revision bigint, p_context_revision bigint,
  p_model text, p_reserve_tokens integer, p_default_limit bigint
) returns text language plpgsql security invoker set search_path = '' as $$
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
    or not exists(select 1 from public.bot_settings where tenant_id = job.tenant_id and is_active) then
    return 'stale';
  end if;
  update public.bot_reply_jobs set prepared_at = now(), automation_revision = p_automation_revision,
    context_revision = p_context_revision, updated_at = now() where id = job.id;
  if p_reserve_tokens = 0 then return 'prepared'; end if;
  if job.expires_at <= clock_timestamp() then return 'window_closed'; end if;
  select monthly_token_limit into token_limit from public.tenant_ai_limits where tenant_id = job.tenant_id;
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
$$;

create function public.cancel_bot_reply(p_job_id uuid, p_lease_token uuid, p_code text default 'context_changed')
returns boolean language plpgsql security invoker set search_path = '' as $$
declare job public.bot_reply_jobs;
begin
  perform public.require_service_role();
  select * into job from public.bot_reply_jobs where id = p_job_id;
  if not found then return false; end if;
  perform 1 from public.conversations where id = job.conversation_id and tenant_id = job.tenant_id for update;
  update public.bot_reply_jobs set state = 'cancelled', lease_token = null, leased_until = null,
    error_code = left(p_code, 100), updated_at = now()
    where id = job.id and state = 'leased' and lease_token = p_lease_token;
  return found;
end;
$$;

create function public.complete_bot_reply(p_job_id uuid, p_lease_token uuid, p_decision jsonb)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  job public.bot_reply_jobs;
  conversation public.conversations;
  settings public.bot_settings;
  version bigint;
  decision jsonb := p_decision;
  message_text text;
  source_kind text;
  reason text;
  source_id text;
begin
  perform public.require_service_role();
  if decision is null or jsonb_typeof(decision) <> 'object'
    or coalesce(decision->>'action', '') not in ('reply', 'handoff')
    or jsonb_typeof(decision->'text') is distinct from 'string'
    or coalesce(decision->>'reason', '') !~ '^[a-z_]{1,100}$'
    or jsonb_typeof(decision->'knowledge_ids') is distinct from 'array'
    or jsonb_array_length(decision->'knowledge_ids') > 5 then
    raise exception 'Invalid bot decision' using errcode = '22023';
  end if;
  select * into job from public.bot_reply_jobs where id = p_job_id;
  if not found then return false; end if;
  select * into conversation from public.conversations where id = job.conversation_id and tenant_id = job.tenant_id for update;
  select * into job from public.bot_reply_jobs where id = p_job_id for update;
  if not found or job.lease_token is distinct from p_lease_token then return false; end if;
  if job.state in ('completed', 'handoff') then return true; end if;
  if job.state <> 'leased' or job.prepared_at is null then return false; end if;
  select * into settings from public.bot_settings where tenant_id = job.tenant_id and is_active;
  if not found or conversation.status <> 'open' or conversation.last_customer_message_id is distinct from job.input_message_id
    or conversation.automation_revision is distinct from job.automation_revision then
    update public.bot_reply_jobs set state = 'cancelled', error_code = 'conversation_changed',
      leased_until = null, updated_at = now() where id = job.id;
    return false;
  end if;
  select revision into version from public.bot_context_versions where tenant_id = job.tenant_id for share;
  if version is distinct from job.context_revision then
    decision := jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'bot_configuration_changed', 'knowledge_ids', '[]'::jsonb);
  elsif job.expires_at <= clock_timestamp() then
    decision := jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'customer_service_window_closed', 'knowledge_ids', '[]'::jsonb);
  end if;
  if job.generation_started_at is not null and not exists (
    select 1 from public.ai_usage_reservations where job_id = job.id and lease_token = p_lease_token
      and (status = 'settled' or (status = 'unknown' and decision->>'action' = 'handoff'))
  ) then return false; end if;
  reason := decision->>'reason';
  if decision->>'action' = 'reply' then
    if job.generation_started_at is null or length(btrim(decision->>'text')) not between 1 and 4096
      or reason not in ('knowledge_answer', 'greeting_or_clarification')
      or (reason = 'knowledge_answer' and jsonb_array_length(decision->'knowledge_ids') = 0) then
      raise exception 'Invalid bot reply' using errcode = '22023';
    end if;
    for source_id in select jsonb_array_elements_text(decision->'knowledge_ids') loop
      if source_id !~ '^[0-9a-f-]{36}$' or not exists (
        select 1 from public.knowledge_base where tenant_id = job.tenant_id and id::text = source_id
      ) then raise exception 'Invalid knowledge source' using errcode = '22023'; end if;
    end loop;
    message_text := decision->>'text';
    source_kind := 'bot';
  else
    if decision->>'text' <> '' or jsonb_array_length(decision->'knowledge_ids') <> 0 then
      raise exception 'Invalid handoff decision' using errcode = '22023';
    end if;
    insert into public.handoff_requests(tenant_id, conversation_id, bot_job_id, note, status)
      values(job.tenant_id, conversation.id, job.id, 'Bot yönlendirmesi (' || reason || ')', 'open');
    update public.conversations set status = 'handoff', updated_at = clock_timestamp()
      where id = conversation.id returning * into conversation;
    message_text := case when lower(settings.language) in ('turkce', 'türkçe', 'tr', 'tr-tr', 'tr_tr')
      then 'Konuşmanızı bir müşteri temsilcisine yönlendirdim.'
      else 'I have passed this conversation to our support team.' end;
    source_kind := 'bot_handoff';
    insert into public.tenant_audit_events(tenant_id, action, resource_id, details)
      values(job.tenant_id, 'conversation.bot_handoff', conversation.id,
        jsonb_build_object('job_id', job.id, 'reason', reason));
  end if;
  -- A handoff remains visible to staff after window expiry, with no out-of-window notice.
  if job.expires_at > clock_timestamp() and conversation.connection_id is not null then
    insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
      values(job.id, job.tenant_id, conversation.id, conversation.connection_id, settings.name, message_text, false);
    insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, source, bot_job_id, expires_at)
      values(job.id, job.tenant_id, conversation.id, conversation.connection_id, conversation.customer_phone,
        source_kind, job.id, job.expires_at);
    update public.conversations set last_message = message_text, last_message_at = clock_timestamp(), updated_at = clock_timestamp()
      where id = conversation.id;
  end if;
  update public.bot_reply_jobs set state = case when source_kind = 'bot' then 'completed' else 'handoff' end,
    output = decision, automation_revision = conversation.automation_revision, context_revision = version,
    leased_until = null, error_code = case when source_kind = 'bot_handoff' then reason else null end,
    updated_at = now() where id = job.id;
  return true;
end;
$$;

create function public.retry_bot_reply(p_job_id uuid, p_lease_token uuid, p_retry_after_seconds integer default 0)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare job public.bot_reply_jobs; next_attempt timestamptz;
begin
  perform public.require_service_role();
  if p_retry_after_seconds is null or p_retry_after_seconds not between 0 and 3600 then
    raise exception 'Invalid retry delay' using errcode = '22023';
  end if;
  select * into job from public.bot_reply_jobs where id = p_job_id;
  if not found then return false; end if;
  perform 1 from public.conversations where tenant_id = job.tenant_id and id = job.conversation_id for update;
  select * into job from public.bot_reply_jobs where id = p_job_id for update;
  if not found or job.state <> 'leased' or job.lease_token is distinct from p_lease_token or job.attempts >= 3 then return false; end if;
  if job.generation_started_at is not null and not exists (
    select 1 from public.ai_usage_reservations where job_id = job.id and lease_token = p_lease_token and status = 'settled' and actual_tokens = 0
  ) then return false; end if;
  next_attempt := clock_timestamp() + make_interval(secs =>
    greatest(p_retry_after_seconds, (30 * power(2, greatest(job.attempts - 1, 0)))::integer) + 1 + floor(random() * 5)::integer);
  if next_attempt >= job.expires_at then return false; end if;
  update public.bot_reply_jobs set state = 'queued', lease_token = null, leased_until = null,
    prepared_at = null, generation_started_at = null, available_at = next_attempt, updated_at = now()
    where id = job.id;
  return true;
end;
$$;

create function public.claim_bot_reply()
returns setof public.bot_reply_jobs language plpgsql security invoker set search_path = '' as $$
declare conversation public.conversations; job public.bot_reply_jobs; version bigint; active boolean;
begin
  perform public.require_service_role();
  -- One conversation per transaction keeps the lock order independent of tenant
  -- quota buckets. Parallel workers can select other conversations with SKIP LOCKED.
  select c.* into conversation from public.bot_reply_jobs candidate
    join public.conversations c on c.id = candidate.conversation_id and c.tenant_id = candidate.tenant_id
  where ((candidate.state = 'queued' and candidate.available_at <= now())
    or (candidate.state = 'leased' and candidate.leased_until <= now())) and not exists (
    select 1 from public.bot_reply_jobs busy where busy.conversation_id = c.id
      and busy.state = 'leased' and busy.leased_until > now()
  ) order by candidate.created_at, candidate.id limit 1 for update of c skip locked;
  if not found then return; end if;
  for job in select * from public.bot_reply_jobs where conversation_id = conversation.id and tenant_id = conversation.tenant_id
    and state = 'leased' and leased_until <= now() for update loop
    if job.generation_started_at is not null then
      perform public.settle_bot_usage(job.id, job.lease_token);
      perform public.complete_bot_reply(job.id, job.lease_token,
        jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'ai_generation_unknown', 'knowledge_ids', '[]'::jsonb));
    elsif job.attempts >= 3 then
      update public.bot_reply_jobs set prepared_at = now() where id = job.id;
      perform public.complete_bot_reply(job.id, job.lease_token,
        jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'ai_worker_retry_exhausted', 'knowledge_ids', '[]'::jsonb));
    else
      update public.bot_reply_jobs set state = 'queued', lease_token = null, leased_until = null,
        prepared_at = null, available_at = now(), updated_at = now() where id = job.id;
    end if;
  end loop;
  select * into conversation from public.conversations where id = conversation.id;
  select coalesce(is_active, false) into active from public.bot_settings where tenant_id = conversation.tenant_id;
  update public.bot_reply_jobs set state = 'cancelled', error_code = 'input_superseded', updated_at = now()
    where conversation_id = conversation.id and tenant_id = conversation.tenant_id and state = 'queued'
      and (input_message_id is distinct from conversation.last_customer_message_id or conversation.status <> 'open' or not coalesce(active, false)
        or not exists (select 1 from public.messages m where m.id = bot_reply_jobs.input_message_id
          and m.tenant_id = conversation.tenant_id and m.conversation_id = conversation.id
          and m.connection_id = conversation.connection_id and m.is_from_customer));
  if conversation.status <> 'open' or not coalesce(active, false) or exists (
    select 1 from public.bot_reply_jobs where conversation_id = conversation.id and state = 'leased'
  ) then return; end if;
  select revision into version from public.bot_context_versions where tenant_id = conversation.tenant_id;
  return query
  update public.bot_reply_jobs j set state = 'leased', lease_token = gen_random_uuid(),
    leased_until = now() + interval '120 seconds', attempts = attempts + 1,
    prepared_at = null, generation_started_at = null,
    automation_revision = conversation.automation_revision, context_revision = version,
    expires_at = least(m.sent_at, m.received_at) + interval '24 hours', updated_at = now()
    from public.messages m where j.conversation_id = conversation.id and j.tenant_id = conversation.tenant_id
      and j.input_message_id = conversation.last_customer_message_id and j.state = 'queued' and j.available_at <= now()
      and j.attempts < 3 and m.id = j.input_message_id and m.tenant_id = j.tenant_id
      and m.conversation_id = j.conversation_id and m.connection_id = conversation.connection_id and m.is_from_customer
    returning j.*;
end;
$$;

create function public.bot_dispatch_allowed(p_job_id uuid, p_tenant_id uuid, p_conversation_id uuid, p_source text)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from public.bot_reply_jobs j
    join public.conversations c on c.id = j.conversation_id and c.tenant_id = j.tenant_id
    join public.bot_settings s on s.tenant_id = j.tenant_id and s.is_active
    join public.bot_context_versions v on v.tenant_id = j.tenant_id
    where j.id = p_job_id and j.tenant_id = p_tenant_id and c.id = p_conversation_id
      and c.automation_revision = j.automation_revision
      and ((p_source = 'bot' and j.state = 'completed' and c.status = 'open'
        and c.last_customer_message_id = j.input_message_id and v.revision = j.context_revision)
        or (p_source = 'bot_handoff' and j.state = 'handoff' and c.status = 'handoff'))
  );
$$;

create function public.reconcile_bot_delivery_failures(p_limit integer default 20)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  conversation public.conversations;
  dispatch public.inbox_dispatches;
  job public.bot_reply_jobs;
  handoffs integer := 0;
  failures integer := 0;
begin
  perform public.require_service_role();
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception 'Invalid batch limit' using errcode = '22023';
  end if;
  for conversation in select c.* from public.conversations c where c.status = 'open' and exists (
    select 1 from public.inbox_dispatches d join public.bot_reply_jobs b on b.id = d.bot_job_id and b.tenant_id = d.tenant_id
    where d.tenant_id = c.tenant_id and d.conversation_id = c.id and d.source = 'bot' and b.state = 'completed'
      and b.input_message_id = c.last_customer_message_id and b.automation_revision = c.automation_revision
      and (d.state in ('failed', 'unknown', 'cancelled') or d.delivery_status = 'failed')
  ) order by c.updated_at, c.id limit p_limit for update of c skip locked loop
    begin
      select d.* into dispatch from public.inbox_dispatches d
        join public.bot_reply_jobs b on b.id = d.bot_job_id and b.tenant_id = d.tenant_id
        where d.tenant_id = conversation.tenant_id and d.conversation_id = conversation.id and d.source = 'bot'
          and b.state = 'completed' and b.input_message_id = conversation.last_customer_message_id
          and b.automation_revision = conversation.automation_revision
          and (d.state in ('failed', 'unknown', 'cancelled') or d.delivery_status = 'failed')
        order by d.sequence limit 1 for update of d;
      if not found then continue; end if;
      select * into job from public.bot_reply_jobs where id = dispatch.bot_job_id and tenant_id = conversation.tenant_id for update;
      insert into public.handoff_requests(tenant_id, conversation_id, bot_job_id, note, status)
        values(job.tenant_id, conversation.id, job.id, 'Bot gönderimi kontrol edilmeli (' ||
          coalesce(dispatch.delivery_error_code, dispatch.error_code, 'delivery_unconfirmed') || ')', 'open');
      update public.conversations set status = 'handoff', updated_at = now()
        where id = conversation.id returning * into conversation;
      update public.bot_reply_jobs set state = 'handoff', automation_revision = conversation.automation_revision,
        error_code = 'bot_delivery_unconfirmed', output = jsonb_build_object(
          'action', 'handoff', 'text', '', 'reason', 'bot_delivery_unconfirmed', 'knowledge_ids', '[]'::jsonb),
        updated_at = now() where id = job.id;
      insert into public.tenant_audit_events(tenant_id, action, resource_id, details)
        values(job.tenant_id, 'conversation.bot_handoff', conversation.id,
          jsonb_build_object('job_id', job.id, 'reason', 'bot_delivery_unconfirmed'));
      handoffs := handoffs + 1;
    exception when others then
      -- Keep the failed delivery eligible. Every partial handoff change rolls back.
      failures := failures + 1;
    end;
  end loop;
  return jsonb_build_object('handoffs', handoffs, 'failed', failures);
end;
$$;

revoke all on function public.settle_bot_usage(uuid, uuid, jsonb, boolean, text) from public, anon, authenticated;
revoke all on function public.mark_stale_ai_reservations(integer) from public, anon, authenticated;
revoke all on function public.prepare_bot_reply(uuid, uuid, bigint, bigint, text, integer, bigint) from public, anon, authenticated;
revoke all on function public.cancel_bot_reply(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.complete_bot_reply(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.retry_bot_reply(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.claim_bot_reply() from public, anon, authenticated;
revoke all on function public.bot_dispatch_allowed(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.reconcile_bot_delivery_failures(integer) from public, anon, authenticated;
grant execute on function public.settle_bot_usage(uuid, uuid, jsonb, boolean, text) to service_role;
grant execute on function public.mark_stale_ai_reservations(integer) to service_role;
grant execute on function public.prepare_bot_reply(uuid, uuid, bigint, bigint, text, integer, bigint) to service_role;
grant execute on function public.cancel_bot_reply(uuid, uuid, text) to service_role;
grant execute on function public.complete_bot_reply(uuid, uuid, jsonb) to service_role;
grant execute on function public.retry_bot_reply(uuid, uuid, integer) to service_role;
grant execute on function public.claim_bot_reply() to service_role;
grant execute on function public.bot_dispatch_allowed(uuid, uuid, uuid, text) to service_role;
grant execute on function public.reconcile_bot_delivery_failures(integer) to service_role;

-- Human and bot messages share one transport queue with source-specific authorization.
create or replace function public.start_inbox_dispatch(p_dispatch_id uuid, p_lease_token uuid)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare job public.inbox_dispatches; conversation public.conversations; failure text;
begin
  perform public.require_service_role();
  select * into job from public.inbox_dispatches where id = p_dispatch_id;
  if not found then return false; end if;
  select * into conversation from public.conversations
    where id = job.conversation_id and tenant_id = job.tenant_id for update;
  select * into job from public.inbox_dispatches where id = p_dispatch_id for update;
  if not found or job.state <> 'leased' or job.lease_token is distinct from p_lease_token
    or job.leased_until <= clock_timestamp() then return false; end if;
  if job.source <> 'human' then
    perform 1 from public.bot_context_versions where tenant_id = job.tenant_id for share;
  end if;
  if conversation.connection_id is distinct from job.connection_id
    or conversation.customer_phone is distinct from job.recipient_phone then
    failure := 'conversation_identity_changed';
  elsif conversation.status = 'closed' then
    failure := 'conversation_closed';
  elsif job.source <> 'human' and not public.bot_dispatch_allowed(job.bot_job_id, job.tenant_id, job.conversation_id, job.source) then
    failure := 'bot_ownership_changed';
  elsif job.source = 'human' and not exists (select 1 from public.tenant_memberships where tenant_id = job.tenant_id and user_id = job.actor_id
    and (role = 'admin' or 'inbox' = any(permissions))) then
    failure := 'sender_permission_revoked';
  elsif job.expires_at <= clock_timestamp() or conversation.last_customer_message_at is null
    or conversation.last_customer_message_at <= clock_timestamp() - interval '24 hours' then
    failure := 'customer_service_window_closed';
  end if;
  if failure is not null then
    update public.inbox_dispatches set state = 'failed', error_code = failure, leased_until = null, updated_at = now()
      where id = job.id;
    return false;
  end if;
  if not exists (select 1 from public.whatsapp_connections w
    join public.whatsapp_connection_credentials k on k.connection_id = w.id and k.tenant_id = w.tenant_id
    where w.id = job.connection_id and w.tenant_id = job.tenant_id and w.status = 'active'
      and (w.token_expires_at is null or w.token_expires_at > clock_timestamp() + interval '30 seconds')) then
    update public.inbox_dispatches set state = 'blocked', error_code = 'connection_unavailable',
      leased_until = null, available_at = now() + interval '5 minutes', updated_at = now() where id = job.id;
    return false;
  end if;
  update public.inbox_dispatches set state = 'sending', attempts = attempts + 1,
    dispatch_started_at = clock_timestamp(), leased_until = clock_timestamp() + interval '120 seconds', updated_at = now()
    where id = job.id;
  return true;
end;
$$;

-- Unsupported customer content becomes a local handoff, with no model call.
create or replace function public.materialize_whatsapp_message(p_event_key text)
returns text language plpgsql security invoker set search_path = '' as $$
declare
  event public.whatsapp_webhook_events;
  connection public.whatsapp_connections;
  conversation public.conversations;
  contact public.contacts;
  sender_phone text;
  message_type text;
  message_body text;
  input_id uuid;
  customer_time timestamptz;
  latest_input boolean;
begin
  perform public.require_service_role();
  select * into event from public.whatsapp_webhook_events
    where event_key = p_event_key for update;
  if not found or event.kind <> 'message' then
    raise exception 'Invalid message event' using errcode = '22023';
  end if;
  select * into connection from public.whatsapp_connections
    where waba_id = event.waba_id and phone_number_id = event.phone_number_id for share;
  if not found then return 'unmatched'; end if;
  if event.connection_id is not null and
    (event.connection_id <> connection.id or event.tenant_id <> connection.tenant_id) then
    raise exception 'Event identity changed' using errcode = '55000';
  end if;
  update public.whatsapp_webhook_events
    set tenant_id = connection.tenant_id, connection_id = connection.id
    where event_key = p_event_key;
  if connection.status = 'inactive' then return 'disconnected'; end if;

  sender_phone := event.payload->>'sender_phone';
  message_type := event.payload->>'type';
  if sender_phone is null or sender_phone !~ '^[1-9][0-9]{7,14}$'
    or message_type is null or message_type !~ '^[a-z_]{1,40}$'
    or jsonb_typeof(event.payload->'content') is distinct from 'object' then
    raise exception 'Invalid inbound content' using errcode = '22023';
  end if;
  -- Serialize contact creation across the tenant's business numbers. All materializers
  -- take this lock before a conversation row lock. Hash collisions only serialize work.
  perform pg_advisory_xact_lock(hashtextextended(connection.tenant_id::text || ':' || sender_phone, 0));
  if exists (select 1 from public.messages
    where connection_id = connection.id and wa_message_id = event.provider_message_id) then
    return 'duplicate';
  end if;
  select * into contact from public.contacts
    where tenant_id = connection.tenant_id and public.normalize_campaign_phone(phone) = sender_phone
    order by created_at, id limit 1;
  if not found then
    insert into public.contacts(tenant_id, full_name, phone)
      values(connection.tenant_id, coalesce(nullif(left(btrim(event.payload->>'contact_name'), 256), ''), sender_phone), sender_phone)
      returning * into contact;
  end if;
  insert into public.conversations(tenant_id, connection_id, customer_phone, contact_id, title, status)
    values(connection.tenant_id, connection.id, sender_phone, contact.id, contact.full_name, 'open')
    on conflict (connection_id, customer_phone) where connection_id is not null do nothing;
  select * into conversation from public.conversations
    where connection_id = connection.id and conversations.customer_phone = sender_phone for update;

  message_body := public.whatsapp_message_preview(event.payload);
  -- A provider clock ahead of receipt time must not extend the customer service window.
  customer_time := least(event.occurred_at, event.received_at);
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body,
    is_from_customer, sent_at, received_at, wa_message_id, message_type, provider_content)
    values(connection.tenant_id, conversation.id, connection.id, contact.full_name, message_body,
      true, event.occurred_at, event.received_at, event.provider_message_id, message_type, event.payload->'content')
    returning id into input_id;
  select last_customer_message_id = input_id into latest_input from public.conversations where id = conversation.id;
  update public.conversations set
    unread_count = unread_count + 1,
    last_customer_message_at = greatest(last_customer_message_at, customer_time),
    last_message = case when last_message_at is null or customer_time >= last_message_at then message_body else last_message end,
    last_message_at = greatest(last_message_at, customer_time),
    status = case when status = 'closed' and latest_input then 'open' else status end,
    updated_at = greatest(updated_at, event.received_at)
    where id = conversation.id
    returning * into conversation;

  -- Receiving a support message does not grant marketing consent. Human handoffs
  -- and pending conversations remain under human control. Older delayed inputs
  -- are displayed but do not create a new bot response job.
  if conversation.status = 'open' and latest_input and message_type <> 'reaction'
    and exists (select 1 from public.bot_settings where tenant_id = connection.tenant_id and is_active) then
    insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id)
      values(connection.tenant_id, conversation.id, input_id)
      on conflict (input_message_id) do nothing;
  end if;
  return 'applied';
end;
$$;

-- Saving identical settings must not interrupt in-flight conversations.
create or replace function public.track_bot_context_version()
returns trigger language plpgsql security definer set search_path = '' as $$
declare affected_tenant uuid;
begin
  if tg_op = 'UPDATE' and new.tenant_id is distinct from old.tenant_id then
    raise exception 'Tenant identity is immutable' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'updated_at') is not distinct from (to_jsonb(old) - 'updated_at') then
    return new;
  end if;
  affected_tenant := case when tg_op = 'DELETE' then old.tenant_id else new.tenant_id end;
  -- Tenant deletion can cascade through settings after the tenant row is gone.
  if exists(select 1 from public.tenants where id = affected_tenant) then
    insert into public.bot_context_versions(tenant_id) values(affected_tenant)
      on conflict (tenant_id) do update set revision = bot_context_versions.revision + 1;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- Reactions do not replace the actionable customer input.
create or replace function public.track_message_automation_context()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.is_from_customer and new.connection_id is not null and new.message_type <> 'reaction' then
    update public.conversations c set last_customer_message_id = new.id
      where c.tenant_id = new.tenant_id and c.id = new.conversation_id and c.connection_id = new.connection_id
        and not exists (select 1 from public.messages previous
          where previous.id = c.last_customer_message_id and previous.tenant_id = c.tenant_id
            and previous.conversation_id = c.id and least(previous.sent_at, previous.received_at) > least(new.sent_at, new.received_at));
  elsif new.sent_by is not null then
    update public.conversations set automation_revision = automation_revision + 1
      where tenant_id = new.tenant_id and id = new.conversation_id;
  end if;
  return new;
end;
$$;

update public.conversations c set last_customer_message_id = (
  select m.id from public.messages m where m.tenant_id = c.tenant_id and m.conversation_id = c.id
    and m.connection_id = c.connection_id and m.is_from_customer and m.message_type <> 'reaction'
  order by least(m.sent_at, m.received_at) desc, m.received_at desc, m.id desc limit 1
) where c.connection_id is not null and exists (
  select 1 from public.messages current_input where current_input.id = c.last_customer_message_id
    and current_input.tenant_id = c.tenant_id and current_input.message_type = 'reaction'
);
