-- Self-service onboarding: users create their own business and join others only
-- through invites addressed to their verified email. Identity, roles, expiry and
-- state transitions are server owned; clients lose direct invite writes.

alter table public.tenants
  add column if not exists created_by uuid references auth.users(id) on delete set null;
create index if not exists tenants_created_by on public.tenants(created_by) where created_by is not null;

alter table public.tenant_invites
  add column if not exists expires_at timestamptz,
  add column if not exists accepted_by uuid references auth.users(id) on delete set null;
update public.tenant_invites set expires_at = created_at + interval '14 days' where expires_at is null;
alter table public.tenant_invites alter column expires_at set default now() + interval '14 days';
alter table public.tenant_invites alter column expires_at set not null;

alter table public.tenant_invites drop constraint if exists tenant_invites_status_check;
alter table public.tenant_invites add constraint tenant_invites_status_check
  check (status in ('pending', 'accepted', 'declined', 'revoked', 'expired'));
alter table public.tenant_invites add constraint tenant_invites_email_format
  check (length(email) <= 320 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') not valid;

-- Keep only the newest pending invite per address before enforcing uniqueness.
with ranked as (
  select id, row_number() over (partition by tenant_id, lower(email) order by created_at desc, id desc) as position
  from public.tenant_invites where status = 'pending'
)
update public.tenant_invites i set status = 'revoked', responded_at = now()
from ranked r where r.id = i.id and r.position > 1;
create unique index if not exists tenant_invites_one_pending
  on public.tenant_invites(tenant_id, lower(email)) where status = 'pending';

-- Invites are read through RLS and written only through the functions below.
drop policy if exists invites_access on public.tenant_invites;
drop policy if exists invites_select on public.tenant_invites;
create policy invites_select on public.tenant_invites for select to authenticated
  using (public.can_manage_tenant(tenant_id));
revoke insert, update, delete on public.tenant_invites from anon, authenticated;

create or replace function public.tenant_module_keys()
returns text[] language sql immutable set search_path = '' as $$
  select array['dashboard', 'inbox', 'handoff', 'bot', 'knowledge', 'campaigns', 'templates', 'users']::text[];
$$;

create or replace function public.confirmed_auth_email()
returns text language sql stable security definer set search_path = '' as $$
  select lower(u.email) from auth.users u
  where u.id = auth.uid() and u.email is not null and u.email_confirmed_at is not null;
$$;
revoke all on function public.confirmed_auth_email() from public, anon;
grant execute on function public.confirmed_auth_email() to authenticated;

-- Creates a business owned by the caller. Bounded per user until plans exist.
create or replace function public.create_business(p_name text, p_brand_color text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
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
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (new_id, uid, 'tenant.created', new_id, jsonb_build_object('name', clean_name));
  return new_id;
end;
$$;
revoke all on function public.create_business(text, text) from public, anon;
grant execute on function public.create_business(text, text) to authenticated;

-- Creates or refreshes the pending invite for an address. Only administrators
-- may invite administrators; other managers may grant only modules they hold.
create or replace function public.create_tenant_invite(
  p_tenant_id uuid, p_email text, p_role text default 'user', p_permissions text[] default array['inbox']
) returns uuid language plpgsql security definer set search_path = '' as $$
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
$$;
revoke all on function public.create_tenant_invite(uuid, text, text, text[]) from public, anon;
grant execute on function public.create_tenant_invite(uuid, text, text, text[]) to authenticated;

create or replace function public.revoke_tenant_invite(p_invite_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); invite public.tenant_invites;
begin
  select * into invite from public.tenant_invites where id = p_invite_id for update;
  if not found or uid is null or not public.can_manage_tenant(invite.tenant_id) then
    raise exception 'Invite not found' using errcode = 'P0002';
  end if;
  if invite.role = 'admin' and not public.is_tenant_admin(invite.tenant_id) then
    raise exception 'Only administrators can revoke administrator invites' using errcode = '42501';
  end if;
  if invite.status <> 'pending' then return false; end if;
  update public.tenant_invites set status = 'revoked', responded_at = now() where id = p_invite_id;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id)
    values (invite.tenant_id, uid, 'invite.revoked', p_invite_id);
  return true;
end;
$$;
revoke all on function public.revoke_tenant_invite(uuid) from public, anon;
grant execute on function public.revoke_tenant_invite(uuid) to authenticated;

-- Pending, unexpired invites addressed to the caller's verified email.
create or replace function public.my_tenant_invites()
returns table(id uuid, tenant_id uuid, tenant_name text, brand_color text, role text, created_at timestamptz, expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select i.id, i.tenant_id, t.name, t.brand_color, i.role, i.created_at, i.expires_at
  from public.tenant_invites i join public.tenants t on t.id = i.tenant_id
  where public.confirmed_auth_email() is not null and lower(i.email) = public.confirmed_auth_email()
    and i.status = 'pending' and i.expires_at > now()
  order by i.created_at desc
  limit 50;
$$;
revoke all on function public.my_tenant_invites() from public, anon;
grant execute on function public.my_tenant_invites() to authenticated;

-- Accepting creates the membership atomically. Retrying an accepted invite is
-- idempotent for the same user. Returns the tenant ID when accepted.
create or replace function public.respond_tenant_invite(p_invite_id uuid, p_accept boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); address text := public.confirmed_auth_email(); invite public.tenant_invites;
begin
  if uid is null or address is null then
    raise exception 'Confirm your email to respond to invites' using errcode = 'P0013';
  end if;
  if p_accept is null then raise exception 'Response required' using errcode = '22023'; end if;
  select * into invite from public.tenant_invites where id = p_invite_id for update;
  if not found or lower(invite.email) <> address then
    raise exception 'Invite not found' using errcode = 'P0002';
  end if;
  if invite.status = 'accepted' and invite.accepted_by = uid and p_accept then
    return invite.tenant_id;
  end if;
  if invite.status <> 'pending' then
    raise exception 'Invite is no longer valid' using errcode = 'P0012';
  end if;
  if invite.expires_at <= now() then
    update public.tenant_invites set status = 'expired', responded_at = now() where id = p_invite_id;
    return null;
  end if;
  if not p_accept then
    update public.tenant_invites set status = 'declined', responded_at = now() where id = p_invite_id;
    insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id)
      values (invite.tenant_id, uid, 'invite.declined', p_invite_id);
    return null;
  end if;
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions)
    values (invite.tenant_id, uid, invite.role, invite.permissions)
    on conflict (tenant_id, user_id) do nothing;
  update public.tenant_invites set status = 'accepted', accepted_by = uid, responded_at = now()
    where id = p_invite_id;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (invite.tenant_id, uid, 'invite.accepted', p_invite_id, jsonb_build_object('role', invite.role));
  return invite.tenant_id;
end;
$$;
revoke all on function public.respond_tenant_invite(uuid, boolean) from public, anon;
grant execute on function public.respond_tenant_invite(uuid, boolean) to authenticated;
