-- Business profile updates: administrators only, validated, locked and audited.
-- All changes roll back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare owner_id uuid := gen_random_uuid(); member_id uuid := gen_random_uuid();
  other_admin_id uuid := gen_random_uuid();
  tenant uuid := gen_random_uuid(); other_tenant uuid := gen_random_uuid();
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (owner_id, 'owner-' || owner_id || '@example.invalid', now()),
    (member_id, 'member-' || member_id || '@example.invalid', now()),
    (other_admin_id, 'other-' || other_admin_id || '@example.invalid', now());
  insert into public.tenants(id, name, brand_color, features, created_by) values
    (tenant, 'Profil Galeri', '#1F4B99', public.tenant_module_keys(), owner_id),
    (other_tenant, 'Baska Galeri', '#0F7B5F', public.tenant_module_keys(), other_admin_id);
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (tenant, owner_id, 'admin', public.tenant_module_keys()),
    (tenant, member_id, 'user', array['inbox', 'users']),
    (other_tenant, other_admin_id, 'admin', public.tenant_module_keys());
  perform set_config('test.owner', owner_id::text, true);
  perform set_config('test.member', member_id::text, true);
  perform set_config('test.other_admin', other_admin_id::text, true);
  perform set_config('test.tenant', tenant::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);

-- Clients cannot write the tenants table directly.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.owner'))::text, true);
do $$
declare changed integer;
begin
  begin
    update public.tenants set name = 'Dogrudan' where id = current_setting('test.tenant')::uuid;
    get diagnostics changed = row_count;
    if changed > 0 then raise exception 'Direct tenant update allowed'; end if;
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- The administrator renames the business and changes its color; both are audited.
do $$
declare row_after public.tenants; audit public.tenant_audit_events;
begin
  perform public.update_business_profile(current_setting('test.tenant')::uuid, '  Yeni Profil Galeri  ', '#9b2335');
  select * into row_after from public.tenants where id = current_setting('test.tenant')::uuid;
  if row_after.name <> 'Yeni Profil Galeri' or row_after.brand_color <> '#9B2335' then
    raise exception 'Profile not saved normalized: % %', row_after.name, row_after.brand_color;
  end if;
  select * into audit from public.tenant_audit_events
    where tenant_id = current_setting('test.tenant')::uuid and action = 'tenant.profile_updated';
  if not found or audit.actor_id <> auth.uid()
      or audit.details #>> '{old,name}' <> 'Profil Galeri'
      or audit.details #>> '{old,brand_color}' <> '#1F4B99'
      or audit.details #>> '{new,name}' <> 'Yeni Profil Galeri'
      or audit.details #>> '{new,brand_color}' <> '#9B2335' then
    raise exception 'Profile update not audited with old and new values';
  end if;
  -- Saving the same values again changes nothing and adds no audit row.
  perform public.update_business_profile(current_setting('test.tenant')::uuid, 'Yeni Profil Galeri', '#9B2335');
  if (select count(*) from public.tenant_audit_events
      where tenant_id = current_setting('test.tenant')::uuid and action = 'tenant.profile_updated') <> 1 then
    raise exception 'Unchanged profile was audited again';
  end if;
end;
$$;

-- Invalid names and colors are rejected with SQLSTATE 22023.
do $$
begin
  begin
    perform public.update_business_profile(current_setting('test.tenant')::uuid, ' x ', '#1F4B99');
    raise exception 'Short business name accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.update_business_profile(current_setting('test.tenant')::uuid, repeat('a', 81), '#1F4B99');
    raise exception 'Long business name accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.update_business_profile(current_setting('test.tenant')::uuid, null, '#1F4B99');
    raise exception 'Missing business name accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.update_business_profile(current_setting('test.tenant')::uuid, 'Galeri', 'red');
    raise exception 'Named color accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.update_business_profile(current_setting('test.tenant')::uuid, 'Galeri', '#12345');
    raise exception 'Short hex color accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.update_business_profile(current_setting('test.tenant')::uuid, 'Galeri', '#GG0000');
    raise exception 'Non-hex color accepted';
  exception when sqlstate '22023' then null;
  end;
  if (select name from public.tenants where id = current_setting('test.tenant')::uuid) <> 'Yeni Profil Galeri' then
    raise exception 'Rejected input changed the business';
  end if;
end;
$$;

-- A member who is not an administrator (even with user management) is denied.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.member'))::text, true);
do $$
begin
  perform public.update_business_profile(current_setting('test.tenant')::uuid, 'Uye Degistirdi', '#334155');
  raise exception 'Non-admin member updated the business';
exception when insufficient_privilege then null;
end;
$$;

-- An administrator of another business is denied.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.other_admin'))::text, true);
do $$
begin
  perform public.update_business_profile(current_setting('test.tenant')::uuid, 'Yabanci Degistirdi', '#334155');
  raise exception 'Another business admin updated the business';
exception when insufficient_privilege then null;
end;
$$;

-- Anonymous callers cannot execute the function at all.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
begin
  perform public.update_business_profile(current_setting('test.tenant')::uuid, 'Anonim', '#334155');
  raise exception 'Anonymous caller updated the business';
exception when insufficient_privilege then null;
end;
$$;

reset role;
do $$
begin
  if (select name from public.tenants where id = current_setting('test.tenant')::uuid) <> 'Yeni Profil Galeri' then
    raise exception 'A denied caller changed the business';
  end if;
end;
$$;
rollback;
