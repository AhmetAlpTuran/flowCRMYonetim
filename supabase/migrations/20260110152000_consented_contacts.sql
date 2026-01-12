create table if not exists public.consented_contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  full_name text,
  phone text not null,
  email text,
  tags text[] not null default array[]::text[],
  last_contacted_at timestamptz,
  consented_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (tenant_id, phone)
);

alter table public.consented_contacts enable row level security;

drop policy if exists "consented_contacts_access" on public.consented_contacts;
create policy "consented_contacts_access" on public.consented_contacts
for all
using (public.user_has_permission(tenant_id, 'campaigns'))
with check (public.user_has_permission(tenant_id, 'campaigns'));

create index if not exists idx_consented_contacts_tenant
on public.consented_contacts (tenant_id);
