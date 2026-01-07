-- Lock down tenant visibility to members only
DROP POLICY IF EXISTS "tenants_select_public" ON public.tenants;

-- Prevent self-assigning memberships
DROP POLICY IF EXISTS "memberships_insert" ON public.tenant_memberships;