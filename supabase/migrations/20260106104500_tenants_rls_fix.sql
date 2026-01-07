-- Remove overly-permissive tenant access for authenticated users
drop policy if exists "tenants_select_authenticated" on public.tenants;
