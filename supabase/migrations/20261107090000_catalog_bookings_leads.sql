-- Business data the custom bots act on: a per-tenant catalog of typed resources
-- (rooms, vehicles, ...), bookings that can never overlap, and sales leads.
-- Module permission: `catalog`. The database is the source of truth for availability;
-- external_* columns leave room for a future Google Sheets sync (roadmap 2d).

create extension if not exists btree_gist with schema extensions;

-- New module, enabled for every existing and future business.
create or replace function public.tenant_module_keys()
returns text[] language sql immutable set search_path = '' as $$
  select array['dashboard', 'inbox', 'handoff', 'bot', 'knowledge', 'campaigns', 'templates', 'users', 'catalog']::text[];
$$;
update public.tenants set features = features || array['catalog'] where not ('catalog' = any(features));
update public.tenant_memberships set permissions = permissions || array['catalog']
  where role = 'admin' and not ('catalog' = any(permissions));

-- Field definitions: [{key, label, type: text|number|select|boolean, options?, filterable?}]
create or replace function public.valid_resource_fields(p_fields jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(p_fields) = 'array' and jsonb_array_length(p_fields) <= 30
    and (select count(distinct f->>'key') = count(*) from jsonb_array_elements(p_fields) f)
    and not exists (
      select 1 from jsonb_array_elements(p_fields) f
      where jsonb_typeof(f) <> 'object'
        or coalesce(f->>'key', '') !~ '^[a-z][a-z0-9_]{0,39}$'
        or length(coalesce(f->>'label', '')) not between 1 and 80
        or coalesce(f->>'type', '') not in ('text', 'number', 'select', 'boolean')
        or (f->>'type' = 'select' and (jsonb_typeof(f->'options') <> 'array'
          or jsonb_array_length(f->'options') not between 1 and 50
          or exists (select 1 from jsonb_array_elements(f->'options') o
            where jsonb_typeof(o) <> 'string' or length(o #>> '{}') not between 1 and 80)))
        or (f ? 'filterable' and jsonb_typeof(f->'filterable') <> 'boolean'));
$$;

create table public.resource_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  key text not null check (key ~ '^[a-z][a-z0-9_]{0,39}$'),
  name text not null check (length(name) between 1 and 80),
  kind text not null check (kind in ('bookable', 'listing')),
  booking_unit text check (booking_unit is null or booking_unit in ('night', 'day', 'hour')),
  fields jsonb not null default '[]' check (public.valid_resource_fields(fields)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, key),
  unique (tenant_id, id),
  check (kind = 'listing' or booking_unit is not null)
);

create table public.resources (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  type_id uuid not null,
  name text not null check (length(name) between 1 and 200),
  description text check (description is null or length(description) <= 4000),
  attributes jsonb not null default '{}' check (jsonb_typeof(attributes) = 'object' and octet_length(attributes::text) <= 16384),
  price numeric(12, 2) check (price is null or price >= 0),
  currency text not null default 'TRY' check (currency ~ '^[A-Z]{3}$'),
  capacity integer check (capacity is null or capacity between 1 and 1000),
  status text not null default 'active' check (status in ('active', 'inactive', 'reserved', 'sold')),
  photos text[] not null default array[]::text[] check (cardinality(photos) <= 10),
  external_source text check (external_source is null or length(external_source) <= 40),
  external_id text check (external_id is null or length(external_id) <= 200),
  external_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, type_id) references public.resource_types(tenant_id, id) on delete cascade
);
create index resources_tenant_type on public.resources(tenant_id, type_id, status);
create unique index resources_external on public.resources(tenant_id, external_source, external_id)
  where external_id is not null;

-- Attributes must match the type's fields: known keys and matching value types.
create or replace function public.validate_resource_attributes()
returns trigger language plpgsql set search_path = '' as $$
declare f jsonb; v jsonb; k text;
begin
  select fields into f from public.resource_types where id = new.type_id and tenant_id = new.tenant_id;
  for k in select jsonb_object_keys(new.attributes) loop
    select x into v from jsonb_array_elements(f) x where x->>'key' = k;
    if v is null then raise exception 'Unknown attribute %', k using errcode = '22023'; end if;
    if jsonb_typeof(new.attributes->k) = 'null' then continue; end if;
    if (v->>'type' = 'number' and jsonb_typeof(new.attributes->k) <> 'number')
      or (v->>'type' = 'boolean' and jsonb_typeof(new.attributes->k) <> 'boolean')
      or (v->>'type' = 'text' and (jsonb_typeof(new.attributes->k) <> 'string' or length(new.attributes->>k) > 500))
      or (v->>'type' = 'select' and not (v->'options' @> jsonb_build_array(new.attributes->k))) then
      raise exception 'Invalid value for %', k using errcode = '22023';
    end if;
  end loop;
  new.updated_at := now();
  return new;
end;
$$;
create trigger resources_validate_attributes before insert or update on public.resources
  for each row execute function public.validate_resource_attributes();

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  resource_id uuid not null,
  period tstzrange not null check (not isempty(period) and lower_inc(period) and not upper_inc(period)
    and lower(period) is not null and upper(period) is not null
    and upper(period) - lower(period) <= interval '90 days'),
  status text not null check (status in ('hold', 'confirmed', 'cancelled')),
  hold_expires_at timestamptz,
  customer_name text check (customer_name is null or length(customer_name) <= 120),
  customer_phone text check (customer_phone is null or customer_phone ~ '^[1-9][0-9]{7,14}$'),
  conversation_id uuid,
  note text check (note is null or length(note) <= 1000),
  source text not null check (source in ('agent', 'bot', 'import')),
  request_key text check (request_key is null or length(request_key) <= 200),
  created_by uuid references auth.users(id) on delete set null,
  external_source text,
  external_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, resource_id) references public.resources(tenant_id, id) on delete cascade,
  foreign key (tenant_id, conversation_id) references public.conversations(tenant_id, id) on delete set null (conversation_id),
  check (status <> 'hold' or hold_expires_at is not null),
  -- The guarantee: two live bookings of the same resource can never overlap.
  constraint bookings_no_overlap exclude using gist (resource_id with =, period with &&)
    where (status <> 'cancelled')
);
create unique index bookings_request_key on public.bookings(tenant_id, request_key) where request_key is not null;
create index bookings_tenant_period on public.bookings using gist (tenant_id, period);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  resource_id uuid,
  conversation_id uuid,
  customer_name text check (customer_name is null or length(customer_name) <= 120),
  customer_phone text check (customer_phone is null or customer_phone ~ '^[1-9][0-9]{7,14}$'),
  kind text not null check (kind in ('inquiry', 'test_drive', 'trade_in', 'financing', 'booking_request', 'other')),
  details jsonb not null default '{}' check (jsonb_typeof(details) = 'object' and octet_length(details::text) <= 8192),
  preferred_at timestamptz,
  status text not null default 'new' check (status in ('new', 'contacted', 'won', 'lost')),
  source text not null check (source in ('agent', 'bot')),
  request_key text check (request_key is null or length(request_key) <= 200),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, resource_id) references public.resources(tenant_id, id) on delete set null (resource_id),
  foreign key (tenant_id, conversation_id) references public.conversations(tenant_id, id) on delete set null (conversation_id)
);
create unique index leads_request_key on public.leads(tenant_id, request_key) where request_key is not null;
create index leads_tenant_status on public.leads(tenant_id, status, created_at desc);

-- RLS: catalog members manage types, resources and leads directly; bookings are read
-- directly but written only through the functions below (expiry, overlap mapping).
alter table public.resource_types enable row level security;
alter table public.resources enable row level security;
alter table public.bookings enable row level security;
alter table public.leads enable row level security;
create policy resource_types_access on public.resource_types for all to authenticated
  using (public.user_has_permission(tenant_id, 'catalog')) with check (public.user_has_permission(tenant_id, 'catalog'));
create policy resources_access on public.resources for all to authenticated
  using (public.user_has_permission(tenant_id, 'catalog')) with check (public.user_has_permission(tenant_id, 'catalog'));
create policy bookings_read on public.bookings for select to authenticated
  using (public.user_has_permission(tenant_id, 'catalog'));
create policy leads_access on public.leads for all to authenticated
  using (public.user_has_permission(tenant_id, 'catalog')) with check (public.user_has_permission(tenant_id, 'catalog'));
revoke insert, update, delete on public.bookings from anon, authenticated;
revoke all on public.resource_types, public.resources, public.leads from anon;

-- Expired holds stop blocking: they are cancelled before any availability decision.
create or replace function public.expire_booking_holds(p_resource_id uuid)
returns void language sql security definer set search_path = '' as $$
  update public.bookings set status = 'cancelled', updated_at = now()
    where resource_id = p_resource_id and status = 'hold' and hold_expires_at <= now();
$$;
revoke all on function public.expire_booking_holds(uuid) from public, anon, authenticated;

-- Shared insert used by agents and the bot. Locks the resource so concurrent requests
-- serialize; the exclusion constraint is the final guarantee (23P01 -> P0015).
create or replace function public.insert_booking(
  p_tenant_id uuid, p_resource_id uuid, p_start timestamptz, p_end timestamptz, p_status text,
  p_hold_minutes integer, p_customer_name text, p_customer_phone text, p_conversation_id uuid,
  p_note text, p_source text, p_request_key text, p_actor uuid
) returns public.bookings language plpgsql security definer set search_path = '' as $$
declare v_resource public.resources; v_type public.resource_types; v_existing public.bookings; v_row public.bookings;
begin
  if p_request_key is not null then
    select * into v_existing from public.bookings where tenant_id = p_tenant_id and request_key = p_request_key;
    if found then return v_existing; end if;
  end if;
  select * into v_resource from public.resources where id = p_resource_id and tenant_id = p_tenant_id for update;
  if not found or v_resource.status not in ('active', 'reserved') then
    raise exception 'Resource unavailable' using errcode = 'P0002';
  end if;
  select * into v_type from public.resource_types where id = v_resource.type_id and tenant_id = p_tenant_id;
  if v_type.kind <> 'bookable' then raise exception 'Resource is not bookable' using errcode = '22023'; end if;
  if p_start is null or p_end is null or p_end <= p_start or p_end - p_start > interval '90 days'
    or p_start < now() - interval '1 day' then
    raise exception 'Invalid booking period' using errcode = '22023';
  end if;
  perform public.expire_booking_holds(p_resource_id);
  begin
    insert into public.bookings(tenant_id, resource_id, period, status, hold_expires_at, customer_name,
        customer_phone, conversation_id, note, source, request_key, created_by)
      values (p_tenant_id, p_resource_id, tstzrange(p_start, p_end, '[)'), p_status,
        case when p_status = 'hold' then now() + make_interval(mins => least(greatest(coalesce(p_hold_minutes, 15), 1), 1440)) end,
        left(nullif(btrim(p_customer_name), ''), 120), p_customer_phone, p_conversation_id,
        left(nullif(btrim(p_note), ''), 1000), p_source, p_request_key, p_actor)
      returning * into v_row;
  exception when exclusion_violation then
    raise exception 'Overlaps another booking' using errcode = 'P0015';
  end;
  return v_row;
end;
$$;
revoke all on function public.insert_booking(uuid, uuid, timestamptz, timestamptz, text, integer, text, text, uuid, text, text, text, uuid) from public, anon, authenticated;

-- Agent-facing ---------------------------------------------------------------

create or replace function public.create_booking(
  p_tenant_id uuid, p_resource_id uuid, p_start timestamptz, p_end timestamptz,
  p_customer_name text default null, p_customer_phone text default null, p_note text default null,
  p_request_key text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_row public.bookings;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'catalog'), false) then
    raise exception 'Catalog permission required' using errcode = '42501';
  end if;
  v_row := public.insert_booking(p_tenant_id, p_resource_id, p_start, p_end, 'confirmed', null,
    p_customer_name, public.contact_phone(p_customer_phone), null, p_note, 'agent', p_request_key, auth.uid());
  return v_row.id;
end;
$$;

create or replace function public.set_booking_status(p_tenant_id uuid, p_booking_id uuid, p_status text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_row public.bookings;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'catalog'), false) then
    raise exception 'Catalog permission required' using errcode = '42501';
  end if;
  if p_status not in ('confirmed', 'cancelled') then raise exception 'Invalid status' using errcode = '22023'; end if;
  select * into v_row from public.bookings where id = p_booking_id and tenant_id = p_tenant_id for update;
  if not found then raise exception 'Booking not found' using errcode = 'P0002'; end if;
  if v_row.status = 'hold' and v_row.hold_expires_at <= now() and p_status = 'confirmed' then
    update public.bookings set status = 'cancelled', updated_at = now() where id = p_booking_id;
    raise exception 'Hold expired' using errcode = 'P0016';
  end if;
  if v_row.status = 'cancelled' and p_status = 'confirmed' then
    raise exception 'Cancelled bookings cannot be confirmed' using errcode = 'P0016';
  end if;
  update public.bookings set status = p_status, hold_expires_at = case when p_status = 'confirmed' then null else hold_expires_at end,
    updated_at = now() where id = p_booking_id;
  return p_status;
end;
$$;

revoke all on function public.create_booking(uuid, uuid, timestamptz, timestamptz, text, text, text, text) from public, anon;
revoke all on function public.set_booking_status(uuid, uuid, text) from public, anon;
grant execute on function public.create_booking(uuid, uuid, timestamptz, timestamptz, text, text, text, text) to authenticated;
grant execute on function public.set_booking_status(uuid, uuid, text) to authenticated;

-- Bot-facing (service role only; called by bot tools) ---------------------------
-- The customer's phone always comes from the conversation, never from model output.

create or replace function public.bot_conversation(p_tenant_id uuid, p_conversation_id uuid)
returns public.conversations language plpgsql stable security definer set search_path = '' as $$
declare v_row public.conversations;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  select * into v_row from public.conversations where id = p_conversation_id and tenant_id = p_tenant_id;
  if not found then raise exception 'Conversation unavailable' using errcode = 'P0002'; end if;
  return v_row;
end;
$$;

-- Filters: {"field": "value"} for text/select/boolean, {"field": {"min": n, "max": n}}
-- for numbers, plus optional {"price": {"min", "max"}}.
create or replace function public.bot_search_resources(
  p_tenant_id uuid, p_type_key text default null, p_query text default null,
  p_filters jsonb default '{}', p_limit integer default 5
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_filters jsonb := coalesce(p_filters, '{}'); v_term text := nullif(left(btrim(coalesce(p_query, '')), 100), '');
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then raise exception 'Filters must be an object' using errcode = '22023'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'type', t.key, 'name', r.name,
      'description', left(r.description, 500), 'price', r.price, 'currency', r.currency,
      'capacity', r.capacity, 'attributes', r.attributes, 'photo_count', cardinality(r.photos))
      order by r.price nulls last, r.name)
    from (
      select r.* from public.resources r join public.resource_types t on t.id = r.type_id
      where r.tenant_id = p_tenant_id and r.status = 'active'
        and (p_type_key is null or t.key = p_type_key)
        and (v_term is null or r.name ilike '%' || v_term || '%' or r.description ilike '%' || v_term || '%')
        and (not (v_filters ? 'price') or (
          (v_filters#>>'{price,min}' is null or r.price >= (v_filters#>>'{price,min}')::numeric)
          and (v_filters#>>'{price,max}' is null or r.price <= (v_filters#>>'{price,max}')::numeric)))
        and not exists (
          select 1 from jsonb_each(v_filters - 'price') f
          where case jsonb_typeof(f.value)
            when 'object' then not (
              (f.value->>'min' is null or (r.attributes->>f.key) ~ '^-?[0-9.]+$' and (r.attributes->>f.key)::numeric >= (f.value->>'min')::numeric)
              and (f.value->>'max' is null or (r.attributes->>f.key) ~ '^-?[0-9.]+$' and (r.attributes->>f.key)::numeric <= (f.value->>'max')::numeric))
            else (r.attributes->f.key) is distinct from f.value
              and lower(r.attributes->>f.key) is distinct from lower(f.value #>> '{}')
          end)
      order by r.price nulls last, r.name
      limit least(greatest(coalesce(p_limit, 5), 1), 10)
    ) r join public.resource_types t on t.id = r.type_id), '[]'::jsonb);
end;
$$;

create or replace function public.bot_check_availability(
  p_tenant_id uuid, p_resource_id uuid, p_start timestamptz, p_end timestamptz
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  if p_start is null or p_end is null or p_end <= p_start or p_end - p_start > interval '90 days' then
    raise exception 'Invalid period' using errcode = '22023';
  end if;
  if not exists (select 1 from public.resources r join public.resource_types t on t.id = r.type_id
      where r.id = p_resource_id and r.tenant_id = p_tenant_id and r.status = 'active' and t.kind = 'bookable') then
    raise exception 'Resource unavailable' using errcode = 'P0002';
  end if;
  perform public.expire_booking_holds(p_resource_id);
  return jsonb_build_object('available', not exists (
      select 1 from public.bookings b where b.resource_id = p_resource_id and b.status <> 'cancelled'
        and b.period && tstzrange(p_start, p_end, '[)')),
    'busy', coalesce((select jsonb_agg(jsonb_build_object('start', lower(b.period), 'end', upper(b.period)) order by lower(b.period))
      from public.bookings b where b.resource_id = p_resource_id and b.status <> 'cancelled'
        and b.period && tstzrange(p_start - interval '7 days', p_end + interval '7 days', '[)')), '[]'::jsonb));
end;
$$;

create or replace function public.bot_create_booking_hold(
  p_tenant_id uuid, p_conversation_id uuid, p_resource_id uuid, p_start timestamptz, p_end timestamptz,
  p_customer_name text, p_request_key text, p_hold_minutes integer default 15
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_conv public.conversations := public.bot_conversation(p_tenant_id, p_conversation_id); v_row public.bookings;
begin
  if p_request_key is null or length(p_request_key) < 8 then
    raise exception 'Request key required' using errcode = '22023';
  end if;
  v_row := public.insert_booking(p_tenant_id, p_resource_id, p_start, p_end, 'hold', p_hold_minutes,
    p_customer_name, v_conv.customer_phone, p_conversation_id, null, 'bot', p_request_key, null);
  if v_row.conversation_id is distinct from p_conversation_id then
    raise exception 'Request key belongs to another conversation' using errcode = '42501';
  end if;
  return jsonb_build_object('booking_id', v_row.id, 'status', v_row.status, 'hold_expires_at', v_row.hold_expires_at,
    'start', lower(v_row.period), 'end', upper(v_row.period));
end;
$$;

-- Confirms or cancels a booking that belongs to this conversation.
create or replace function public.bot_set_booking_status(
  p_tenant_id uuid, p_conversation_id uuid, p_booking_id uuid, p_status text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_conv public.conversations := public.bot_conversation(p_tenant_id, p_conversation_id); v_row public.bookings;
begin
  if p_status not in ('confirmed', 'cancelled') then raise exception 'Invalid status' using errcode = '22023'; end if;
  select * into v_row from public.bookings where id = p_booking_id and tenant_id = p_tenant_id
    and conversation_id = v_conv.id for update;
  if not found then raise exception 'Booking not found' using errcode = 'P0002'; end if;
  if v_row.status = p_status then
    return jsonb_build_object('booking_id', v_row.id, 'status', v_row.status);
  end if;
  if p_status = 'confirmed' and (v_row.status <> 'hold' or v_row.hold_expires_at <= now()) then
    update public.bookings set status = 'cancelled', updated_at = now()
      where id = p_booking_id and status = 'hold';
    raise exception 'Hold expired' using errcode = 'P0016';
  end if;
  update public.bookings set status = p_status, hold_expires_at = null, updated_at = now() where id = p_booking_id;
  return jsonb_build_object('booking_id', v_row.id, 'status', p_status);
end;
$$;

create or replace function public.bot_create_lead(
  p_tenant_id uuid, p_conversation_id uuid, p_kind text, p_resource_id uuid default null,
  p_details jsonb default '{}', p_preferred_at timestamptz default null, p_customer_name text default null,
  p_request_key text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_conv public.conversations := public.bot_conversation(p_tenant_id, p_conversation_id); v_row public.leads;
begin
  if p_request_key is null or length(p_request_key) < 8 then
    raise exception 'Request key required' using errcode = '22023';
  end if;
  select * into v_row from public.leads where tenant_id = p_tenant_id and request_key = p_request_key;
  if found then
    if v_row.conversation_id is distinct from p_conversation_id then
      raise exception 'Request key belongs to another conversation' using errcode = '42501';
    end if;
    return jsonb_build_object('lead_id', v_row.id, 'status', v_row.status);
  end if;
  if p_resource_id is not null and not exists (select 1 from public.resources where id = p_resource_id and tenant_id = p_tenant_id) then
    raise exception 'Resource unavailable' using errcode = 'P0002';
  end if;
  insert into public.leads(tenant_id, resource_id, conversation_id, customer_name, customer_phone, kind, details,
      preferred_at, source, request_key)
    values (p_tenant_id, p_resource_id, p_conversation_id, left(nullif(btrim(p_customer_name), ''), 120),
      v_conv.customer_phone, p_kind, coalesce(p_details, '{}'), p_preferred_at, 'bot', p_request_key)
    returning * into v_row;
  return jsonb_build_object('lead_id', v_row.id, 'status', v_row.status);
end;
$$;

revoke all on function public.bot_conversation(uuid, uuid) from public, anon, authenticated;
revoke all on function public.bot_search_resources(uuid, text, text, jsonb, integer) from public, anon, authenticated;
revoke all on function public.bot_check_availability(uuid, uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.bot_create_booking_hold(uuid, uuid, uuid, timestamptz, timestamptz, text, text, integer) from public, anon, authenticated;
revoke all on function public.bot_set_booking_status(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.bot_create_lead(uuid, uuid, text, uuid, jsonb, timestamptz, text, text) from public, anon, authenticated;
grant execute on function public.bot_search_resources(uuid, text, text, jsonb, integer) to service_role;
grant execute on function public.bot_check_availability(uuid, uuid, timestamptz, timestamptz) to service_role;
grant execute on function public.bot_create_booking_hold(uuid, uuid, uuid, timestamptz, timestamptz, text, text, integer) to service_role;
grant execute on function public.bot_set_booking_status(uuid, uuid, uuid, text) to service_role;
grant execute on function public.bot_create_lead(uuid, uuid, text, uuid, jsonb, timestamptz, text, text) to service_role;
