-- First-run setup checklist (roadmap Phase 1): which first steps a business has done,
-- for the "Kurulum" card administrators see on the dashboard.

create function public.tenant_setup_progress(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if p_tenant_id is null or not public.is_tenant_admin(p_tenant_id) then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'whatsapp', exists (select 1 from public.whatsapp_connections where tenant_id = p_tenant_id and status = 'active'),
    'knowledge', exists (select 1 from public.knowledge_base where tenant_id = p_tenant_id)
      or exists (select 1 from public.knowledge_documents where tenant_id = p_tenant_id and state = 'ready'),
    'bot', exists (select 1 from public.bot_settings where tenant_id = p_tenant_id and is_active)
      or exists (select 1 from public.bot_profiles where tenant_id = p_tenant_id and is_active),
    'catalog', exists (select 1 from public.resources where tenant_id = p_tenant_id),
    'team', (select count(*) from public.tenant_memberships where tenant_id = p_tenant_id) > 1
      or exists (select 1 from public.tenant_invites where tenant_id = p_tenant_id and status = 'pending'),
    'contacts', exists (select 1 from public.consented_contacts where tenant_id = p_tenant_id and opted_out_at is null),
    'billing', exists (select 1 from public.tenant_billing_profiles where tenant_id = p_tenant_id)
  );
end;
$$;
revoke all on function public.tenant_setup_progress(uuid) from public, anon;
grant execute on function public.tenant_setup_progress(uuid) to authenticated;
