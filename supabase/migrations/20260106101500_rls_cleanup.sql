-- Add public visibility flag for tenant directory
alter table public.tenants
add column if not exists is_public boolean not null default false;

-- Remove previous anon policy if exists
DROP POLICY IF EXISTS "tenants_select_anon" ON public.tenants;

-- Allow anon users to list only public tenants (for signup flow)
create policy "tenants_select_public" on public.tenants
for select
using (auth.role() = 'anon' and is_public = true);