-- Metadata is tenant-readable; encrypted bearer credentials are service-only.
create or replace function public.require_service_role()
returns void language plpgsql stable security invoker set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service access required' using errcode = '42501';
  end if;
end;
$$;
create or replace function public.require_campaign_worker()
returns void language sql stable security invoker set search_path = '' as $$
  select public.require_service_role();
$$;

create or replace function public.is_tenant_admin(target_tenant uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.tenant_memberships m
    where m.tenant_id = target_tenant and m.user_id = auth.uid() and m.role = 'admin');
$$;
revoke all on function public.require_service_role() from public, anon, authenticated;
grant execute on function public.require_service_role() to service_role;
revoke all on function public.is_tenant_admin(uuid) from public, anon;
grant execute on function public.is_tenant_admin(uuid) to authenticated, service_role;

-- The former users permission allowed a manager to promote themselves to admin.
-- Direct role/permission writes now require an existing tenant administrator.
drop policy memberships_manage on public.tenant_memberships;
create policy memberships_manage on public.tenant_memberships for all to authenticated
  using (public.is_tenant_admin(tenant_id)) with check (public.is_tenant_admin(tenant_id));

create table public.whatsapp_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  waba_id text not null check (waba_id ~ '^[0-9]{1,40}$'),
  phone_number_id text not null unique check (phone_number_id ~ '^[0-9]{1,40}$'),
  display_phone_number text not null,
  verified_name text not null default '',
  status text not null check (status in ('active', 'inactive', 'needs_attention')),
  is_default boolean not null default false,
  token_expires_at timestamptz,
  verified_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id)
);
create unique index whatsapp_default_connection on public.whatsapp_connections(tenant_id)
  where is_default and status = 'active';
create index whatsapp_connections_tenant on public.whatsapp_connections(tenant_id, status);
alter table public.whatsapp_connections enable row level security;
revoke all on public.whatsapp_connections from public, anon, authenticated;
grant select on public.whatsapp_connections to authenticated;
grant all on public.whatsapp_connections to service_role;
create policy whatsapp_connections_read on public.whatsapp_connections for select to authenticated
  using (public.user_has_tenant(tenant_id));

create or replace function public.guard_whatsapp_connection_identity()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.tenant_id is distinct from old.tenant_id
    or new.waba_id is distinct from old.waba_id or new.phone_number_id is distinct from old.phone_number_id then
    raise exception 'WhatsApp connection identity is immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger whatsapp_connection_identity_guard before update on public.whatsapp_connections
  for each row execute function public.guard_whatsapp_connection_identity();
revoke all on function public.guard_whatsapp_connection_identity() from public, anon, authenticated;

create table public.whatsapp_connection_credentials (
  connection_id uuid primary key,
  tenant_id uuid not null,
  key_id text not null check (key_id ~ '^[A-Za-z0-9_-]{1,40}$'),
  ciphertext text not null check (length(ciphertext) between 24 and 32768),
  iv text not null check (length(iv) = 16),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, connection_id) references public.whatsapp_connections(tenant_id, id) on delete cascade
);
alter table public.whatsapp_connection_credentials enable row level security;
revoke all on public.whatsapp_connection_credentials from public, anon, authenticated;
grant all on public.whatsapp_connection_credentials to service_role;
-- Intentionally no user policy or SECURITY DEFINER credential-reading RPC.

create table public.tenant_audit_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  resource_id uuid,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index tenant_audit_events_recent on public.tenant_audit_events(tenant_id, created_at desc, id);
alter table public.tenant_audit_events enable row level security;
revoke all on public.tenant_audit_events from public, anon, authenticated;
grant select on public.tenant_audit_events to authenticated;
grant all on public.tenant_audit_events to service_role;
create policy tenant_audit_admin_read on public.tenant_audit_events for select to authenticated
  using (public.is_tenant_admin(tenant_id));

create or replace function public.save_whatsapp_connection(
  p_tenant_id uuid, p_actor_id uuid, p_connection_id uuid, p_waba_id text,
  p_phone_number_id text, p_metadata jsonb, p_credential jsonb, p_is_default boolean default false
) returns uuid language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  perform 1 from public.tenants where id = p_tenant_id for update;
  if not found or not exists (select 1 from public.tenant_memberships m
    where m.tenant_id = p_tenant_id and m.user_id = p_actor_id and m.role = 'admin') then
    raise exception 'Tenant administrator required' using errcode = '42501';
  end if;
  if p_is_default then
    update public.whatsapp_connections set is_default = false, updated_at = now()
      where tenant_id = p_tenant_id and is_default;
  end if;
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id,
    display_phone_number, verified_name, status, is_default, token_expires_at, verified_at)
  values (p_connection_id, p_tenant_id, p_waba_id, p_phone_number_id,
    p_metadata->>'display_phone_number', coalesce(p_metadata->>'verified_name', ''), 'active',
    coalesce(p_is_default, false), (p_metadata->>'token_expires_at')::timestamptz, now())
  on conflict (id) do update set display_phone_number = excluded.display_phone_number,
    verified_name = excluded.verified_name, status = 'active', is_default = excluded.is_default,
    token_expires_at = excluded.token_expires_at, verified_at = now(), updated_at = now()
  where whatsapp_connections.tenant_id = p_tenant_id
    and whatsapp_connections.phone_number_id = p_phone_number_id and whatsapp_connections.waba_id = p_waba_id;
  if not found then raise exception 'Connection identity mismatch' using errcode = '42501'; end if;
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
  values (p_connection_id, p_tenant_id, p_credential->>'key_id', p_credential->>'ciphertext', p_credential->>'iv')
  on conflict (connection_id) do update set key_id = excluded.key_id, ciphertext = excluded.ciphertext,
    iv = excluded.iv, updated_at = now();
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id)
    values (p_tenant_id, p_actor_id, 'whatsapp.connection_saved', p_connection_id);
  return p_connection_id;
end;
$$;

create or replace function public.disconnect_whatsapp_connection(p_tenant_id uuid, p_actor_id uuid, p_connection_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  if not exists (select 1 from public.tenant_memberships m where m.tenant_id = p_tenant_id
    and m.user_id = p_actor_id and m.role = 'admin') then
    raise exception 'Tenant administrator required' using errcode = '42501';
  end if;
  update public.whatsapp_connections set status = 'inactive', is_default = false, updated_at = now()
    where id = p_connection_id and tenant_id = p_tenant_id;
  if not found then raise exception 'Connection not found' using errcode = 'P0002'; end if;
  delete from public.whatsapp_connection_credentials where connection_id = p_connection_id and tenant_id = p_tenant_id;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id)
    values (p_tenant_id, p_actor_id, 'whatsapp.connection_disconnected', p_connection_id);
end;
$$;
revoke all on function public.save_whatsapp_connection(uuid, uuid, uuid, text, text, jsonb, jsonb, boolean) from public, anon, authenticated;
revoke all on function public.disconnect_whatsapp_connection(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.save_whatsapp_connection(uuid, uuid, uuid, text, text, jsonb, jsonb, boolean) to service_role;
grant execute on function public.disconnect_whatsapp_connection(uuid, uuid, uuid) to service_role;

alter table public.campaigns add column connection_id uuid;
alter table public.campaigns add constraint campaigns_connection_tenant_fk
  foreign key (tenant_id, connection_id) references public.whatsapp_connections(tenant_id, id);
alter table public.templates add column waba_id text check (waba_id ~ '^[0-9]{1,40}$');

create or replace function public.guard_campaign_connection()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if old.queued_at is not null and new.connection_id is distinct from old.connection_id then
    raise exception 'Queued campaign connection is immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;
create trigger campaign_connection_guard before update on public.campaigns
  for each row execute function public.guard_campaign_connection();
revoke all on function public.guard_campaign_connection() from public, anon, authenticated;
