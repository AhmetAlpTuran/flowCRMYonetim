-- Tenant admin + access request tables
alter table public.user_profiles
add column if not exists email text;

create or replace function public.can_manage_tenant(target_tenant uuid)
returns boolean
language sql
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
    from public.tenant_memberships tm
    where tm.tenant_id = target_tenant
      and tm.user_id = auth.uid()
      and (
        tm.role = 'admin'
        or 'users' = any(tm.permissions)
      )
  );
$$;

create table if not exists public.tenant_invites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  email text not null,
  role text not null check (role in ('admin', 'user')) default 'user',
  permissions text[] not null default array['inbox']::text[],
  status text not null
    check (status in ('pending', 'accepted', 'revoked', 'expired'))
    default 'pending',
  invited_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create table if not exists public.tenant_join_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  email text not null,
  message text,
  status text not null check (status in ('pending', 'approved', 'rejected'))
    default 'pending',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users on delete set null
);

alter table public.tenant_invites enable row level security;
alter table public.tenant_join_requests enable row level security;

drop policy if exists "profiles_select" on public.user_profiles;
create policy "profiles_select" on public.user_profiles
for select
using (
  id = auth.uid()
  or exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = user_profiles.id
      and public.can_manage_tenant(tm.tenant_id)
  )
);

drop policy if exists "profiles_update" on public.user_profiles;
create policy "profiles_update" on public.user_profiles
for update
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists "memberships_select" on public.tenant_memberships;
create policy "memberships_select" on public.tenant_memberships
for select
using (
  user_id = auth.uid()
  or public.can_manage_tenant(tenant_id)
);

drop policy if exists "memberships_manage" on public.tenant_memberships;
create policy "memberships_manage" on public.tenant_memberships
for all
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));

drop policy if exists "tenants_select_authenticated" on public.tenants;
drop policy if exists "tenants_select_public" on public.tenants;
create policy "tenants_select_public" on public.tenants
for select
using (is_public = true);

create policy "invites_access" on public.tenant_invites
for all
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));

create policy "join_requests_select" on public.tenant_join_requests
for select
using (
  user_id = auth.uid()
  or public.can_manage_tenant(tenant_id)
);

create policy "join_requests_insert" on public.tenant_join_requests
for insert
with check (user_id = auth.uid());

create policy "join_requests_update" on public.tenant_join_requests
for update
using (public.can_manage_tenant(tenant_id))
with check (public.can_manage_tenant(tenant_id));

create policy "join_requests_delete" on public.tenant_join_requests
for delete
using (public.can_manage_tenant(tenant_id));

update public.tenants
set features = array_append(features, 'users')
where not ('users' = any(features));
