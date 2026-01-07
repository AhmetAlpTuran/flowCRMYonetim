-- Core extensions
create extension if not exists pgcrypto;

-- Tenants
create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  brand_color text not null default '#1F4B99',
  features text[] not null default array[]::text[],
  created_at timestamptz not null default now()
);

-- User profile linked to auth.users
create table if not exists public.user_profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

-- Tenant memberships
create table if not exists public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  role text not null check (role in ('admin', 'user')),
  created_at timestamptz not null default now(),
  unique (tenant_id, user_id)
);

-- Contacts
create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  full_name text not null,
  phone text not null,
  email text,
  tags text[] not null default array[]::text[],
  last_contacted_at timestamptz,
  created_at timestamptz not null default now()
);

-- Conversations
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  contact_id uuid references public.contacts on delete set null,
  title text not null,
  last_message text,
  status text not null check (status in ('open', 'pending', 'handoff', 'closed')),
  tags text[] not null default array[]::text[],
  unread_count int not null default 0,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Messages
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  conversation_id uuid not null references public.conversations on delete cascade,
  sender text not null,
  body text not null,
  is_from_customer boolean not null default false,
  sent_at timestamptz not null default now()
);

-- Templates (WhatsApp)
create table if not exists public.templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  name text not null,
  category text not null,
  language text not null,
  status text not null,
  components jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Campaigns
create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  name text not null,
  audience_filter jsonb not null default '{}'::jsonb,
  template_id uuid references public.templates on delete set null,
  status text not null check (status in ('draft', 'scheduled', 'running', 'completed', 'failed')),
  created_at timestamptz not null default now()
);

-- Message jobs (queue)
create table if not exists public.message_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  campaign_id uuid references public.campaigns on delete set null,
  contact_id uuid references public.contacts on delete set null,
  template_id uuid references public.templates on delete set null,
  status text not null check (status in ('queued', 'sending', 'sent', 'failed')),
  attempts int not null default 0,
  last_error text,
  created_at timestamptz not null default now()
);

-- Helper function for RLS
create or replace function public.user_has_tenant(target_tenant uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.tenant_memberships tm
    where tm.tenant_id = target_tenant
      and tm.user_id = auth.uid()
  );
$$;

-- Enable RLS
alter table public.tenants enable row level security;
alter table public.user_profiles enable row level security;
alter table public.tenant_memberships enable row level security;
alter table public.contacts enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.templates enable row level security;
alter table public.campaigns enable row level security;
alter table public.message_jobs enable row level security;

-- Policies
create policy "tenants_select" on public.tenants
for select
using (public.user_has_tenant(id));

create policy "tenants_select_authenticated" on public.tenants
for select
using (auth.role() = 'authenticated');

create policy "tenants_select_anon" on public.tenants
for select
using (auth.role() = 'anon');

create policy "profiles_select" on public.user_profiles
for select
using (id = auth.uid());

create policy "profiles_insert" on public.user_profiles
for insert
with check (id = auth.uid());

create policy "memberships_select" on public.tenant_memberships
for select
using (user_id = auth.uid());

create policy "memberships_insert" on public.tenant_memberships
for insert
with check (user_id = auth.uid());

create policy "contacts_access" on public.contacts
for all
using (public.user_has_tenant(tenant_id))
with check (public.user_has_tenant(tenant_id));

create policy "conversations_access" on public.conversations
for all
using (public.user_has_tenant(tenant_id))
with check (public.user_has_tenant(tenant_id));

create policy "messages_access" on public.messages
for all
using (public.user_has_tenant(tenant_id))
with check (public.user_has_tenant(tenant_id));

create policy "templates_access" on public.templates
for all
using (public.user_has_tenant(tenant_id))
with check (public.user_has_tenant(tenant_id));

create policy "campaigns_access" on public.campaigns
for all
using (public.user_has_tenant(tenant_id))
with check (public.user_has_tenant(tenant_id));

create policy "message_jobs_access" on public.message_jobs
for all
using (public.user_has_tenant(tenant_id))
with check (public.user_has_tenant(tenant_id));

-- Indexes
create index if not exists idx_conversations_tenant_updated
on public.conversations (tenant_id, updated_at desc);

create index if not exists idx_messages_conversation
on public.messages (conversation_id, sent_at desc);

create index if not exists idx_contacts_tenant
on public.contacts (tenant_id);

create index if not exists idx_templates_tenant
on public.templates (tenant_id);

create index if not exists idx_campaigns_tenant
on public.campaigns (tenant_id);
