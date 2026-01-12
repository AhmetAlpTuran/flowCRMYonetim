create table if not exists public.handoff_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  conversation_id uuid not null references public.conversations on delete cascade,
  note text,
  status text not null check (status in ('open', 'in_progress', 'done'))
    default 'open',
  created_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

alter table public.handoff_requests enable row level security;

drop policy if exists "handoff_requests_access" on public.handoff_requests;
create policy "handoff_requests_access" on public.handoff_requests
for all
using (public.user_has_permission(tenant_id, 'handoff'))
with check (public.user_has_permission(tenant_id, 'handoff'));

create index if not exists idx_handoff_requests_tenant
on public.handoff_requests (tenant_id, created_at desc);
