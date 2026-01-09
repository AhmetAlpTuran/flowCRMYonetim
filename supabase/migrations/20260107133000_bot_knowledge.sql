-- Bot settings (per tenant)
create table if not exists public.bot_settings (
  tenant_id uuid primary key references public.tenants on delete cascade,
  name text not null default 'Ava',
  tone text not null default 'Profesyonel ve net',
  language text not null default 'Turkce',
  system_prompt text not null default 'Kisa, profesyonel bir musteri temsilcisi gibi yanit ver.',
  model text not null default 'gpt-4o-mini',
  temperature numeric not null default 0.3,
  memory_hours int not null default 6,
  max_history_messages int not null default 12,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Knowledge base entries
create table if not exists public.knowledge_base (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  title text not null,
  content text not null,
  tags text[] not null default array[]::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.bot_settings enable row level security;
alter table public.knowledge_base enable row level security;

drop policy if exists "bot_settings_access" on public.bot_settings;
create policy "bot_settings_access" on public.bot_settings
for all
using (public.user_has_permission(tenant_id, 'bot'))
with check (public.user_has_permission(tenant_id, 'bot'));

drop policy if exists "knowledge_base_access" on public.knowledge_base;
create policy "knowledge_base_access" on public.knowledge_base
for all
using (public.user_has_permission(tenant_id, 'knowledge'))
with check (public.user_has_permission(tenant_id, 'knowledge'));

create index if not exists idx_knowledge_base_tenant_updated
on public.knowledge_base (tenant_id, updated_at desc);
