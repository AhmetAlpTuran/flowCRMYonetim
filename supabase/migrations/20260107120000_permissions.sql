-- Add permissions to tenant memberships
alter table public.tenant_memberships
add column if not exists permissions text[] not null default array['inbox']::text[];

-- Permission helper
create or replace function public.user_has_permission(
  target_tenant uuid,
  permission text
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.tenant_memberships tm
    where tm.tenant_id = target_tenant
      and tm.user_id = auth.uid()
      and (
        tm.role = 'admin'
        or permission = any(tm.permissions)
      )
  );
$$;

-- Update policies to include permission checks
drop policy if exists "contacts_access" on public.contacts;
create policy "contacts_access" on public.contacts
for all
using (public.user_has_permission(tenant_id, 'inbox'))
with check (public.user_has_permission(tenant_id, 'inbox'));

drop policy if exists "conversations_access" on public.conversations;
create policy "conversations_access" on public.conversations
for all
using (public.user_has_permission(tenant_id, 'inbox'))
with check (public.user_has_permission(tenant_id, 'inbox'));

drop policy if exists "messages_access" on public.messages;
create policy "messages_access" on public.messages
for all
using (public.user_has_permission(tenant_id, 'inbox'))
with check (public.user_has_permission(tenant_id, 'inbox'));

drop policy if exists "templates_access" on public.templates;
create policy "templates_access" on public.templates
for all
using (public.user_has_permission(tenant_id, 'templates'))
with check (public.user_has_permission(tenant_id, 'templates'));

drop policy if exists "campaigns_access" on public.campaigns;
create policy "campaigns_access" on public.campaigns
for all
using (public.user_has_permission(tenant_id, 'campaigns'))
with check (public.user_has_permission(tenant_id, 'campaigns'));

drop policy if exists "message_jobs_access" on public.message_jobs;
create policy "message_jobs_access" on public.message_jobs
for all
using (public.user_has_permission(tenant_id, 'campaigns'))
with check (public.user_has_permission(tenant_id, 'campaigns'));
