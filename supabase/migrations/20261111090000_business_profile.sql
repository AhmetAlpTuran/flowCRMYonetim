-- Business profile (Ayarlar → İşletme): administrators rename the business and pick its
-- identity color through one audited RPC. Clients keep no direct write on tenants.

create or replace function public.update_business_profile(p_tenant_id uuid, p_name text, p_brand_color text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  clean_name text := btrim(coalesce(p_name, ''));
  color text := upper(btrim(coalesce(p_brand_color, '')));
  current_row public.tenants;
begin
  if uid is null or p_tenant_id is null or not public.is_tenant_admin(p_tenant_id) then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if length(clean_name) < 2 or length(clean_name) > 80 then
    raise exception 'Business name must be 2-80 characters' using errcode = '22023', hint = 'business_name';
  end if;
  if color !~ '^#[0-9A-F]{6}$' then
    raise exception 'Brand color must be #RRGGBB' using errcode = '22023', hint = 'brand_color';
  end if;
  select * into current_row from public.tenants where id = p_tenant_id for update;
  if not found then
    raise exception 'Business not found' using errcode = 'P0002';
  end if;
  if current_row.name = clean_name and upper(current_row.brand_color) = color then
    return;
  end if;
  update public.tenants set name = clean_name, brand_color = color where id = p_tenant_id;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (p_tenant_id, uid, 'tenant.profile_updated', p_tenant_id, jsonb_build_object(
      'old', jsonb_build_object('name', current_row.name, 'brand_color', current_row.brand_color),
      'new', jsonb_build_object('name', clean_name, 'brand_color', color)));
end;
$$;
revoke all on function public.update_business_profile(uuid, text, text) from public, anon;
grant execute on function public.update_business_profile(uuid, text, text) to authenticated;
