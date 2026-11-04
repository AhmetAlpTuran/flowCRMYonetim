-- Self-service business creation and invite lifecycle. All changes roll back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare owner_id uuid := gen_random_uuid(); manager_id uuid := gen_random_uuid();
  invitee_id uuid := gen_random_uuid(); stranger_id uuid := gen_random_uuid();
  unconfirmed_id uuid := gen_random_uuid();
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (owner_id, 'owner-' || owner_id || '@example.invalid', now()),
    (manager_id, 'manager-' || manager_id || '@example.invalid', now()),
    (invitee_id, 'Invitee-' || invitee_id || '@Example.invalid', now()),
    (stranger_id, 'stranger-' || stranger_id || '@example.invalid', now()),
    (unconfirmed_id, 'unconfirmed-' || unconfirmed_id || '@example.invalid', null);
  perform set_config('test.owner', owner_id::text, true);
  perform set_config('test.manager', manager_id::text, true);
  perform set_config('test.invitee', invitee_id::text, true);
  perform set_config('test.stranger', stranger_id::text, true);
  perform set_config('test.unconfirmed', unconfirmed_id::text, true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);

-- An unconfirmed user cannot create a business.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.unconfirmed'))::text, true);
do $$
begin
  perform public.create_business('Onaysiz Galeri');
  raise exception 'Unconfirmed user created a business';
exception when sqlstate 'P0013' then null;
end;
$$;

-- The owner creates a business, becomes its admin with every module, and is bounded.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.owner'))::text, true);
do $$
declare tenant uuid; member public.tenant_memberships;
begin
  begin
    perform public.create_business(' x ');
    raise exception 'Short business name accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.create_business('Galeri', 'red');
    raise exception 'Invalid brand color accepted';
  exception when sqlstate '22023' then null;
  end;
  tenant := public.create_business('  Smoke Oto Galeri  ', '#12ab34');
  select * into member from public.tenant_memberships where tenant_id = tenant and user_id = auth.uid();
  if member.role <> 'admin' or not public.tenant_module_keys() <@ member.permissions then
    raise exception 'Creator is not a full administrator';
  end if;
  if not exists (select 1 from public.tenants where id = tenant and name = 'Smoke Oto Galeri'
      and brand_color = '#12AB34' and features @> array['inbox', 'campaigns']) then
    raise exception 'Business row not normalized';
  end if;
  if not exists (select 1 from public.tenant_audit_events where tenant_id = tenant and action = 'tenant.created') then
    raise exception 'Business creation not audited';
  end if;
  perform public.create_business('Ikinci');
  perform public.create_business('Ucuncu');
  begin
    perform public.create_business('Dorduncu');
    raise exception 'Business limit not enforced';
  exception when sqlstate 'P0010' then null;
  end;
  perform set_config('test.tenant', tenant::text, true);
end;
$$;

-- Direct invite writes are revoked; the admin invites a limited manager.
do $$
declare manager_email text; invite uuid;
begin
  begin
    insert into public.tenant_invites(tenant_id, email) values (current_setting('test.tenant')::uuid, 'direct@example.invalid');
    raise exception 'Direct invite insert allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.create_tenant_invite(current_setting('test.tenant')::uuid, 'not-an-email', 'user', array['inbox']);
    raise exception 'Invalid email accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.create_tenant_invite(current_setting('test.tenant')::uuid, 'x@example.invalid', 'user', array['billing']);
    raise exception 'Unknown module accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.create_tenant_invite(current_setting('test.tenant')::uuid,
      'owner-' || current_setting('test.owner') || '@example.invalid', 'user', array['inbox']);
    raise exception 'Existing member invited';
  exception when sqlstate 'P0011' then null;
  end;
  -- Membership is granted directly here only to set up a non-admin manager.
  reset role;
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions)
    values (current_setting('test.tenant')::uuid, current_setting('test.manager')::uuid, 'user', array['users', 'inbox']);
  set local role authenticated;
end;
$$;

-- A non-admin manager cannot escalate through invites.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.manager'))::text, true);
do $$
declare invite uuid; again uuid; address text := 'INVITEE-' || current_setting('test.invitee') || '@example.invalid';
begin
  begin
    perform public.create_tenant_invite(current_setting('test.tenant')::uuid, address, 'admin', array[]::text[]);
    raise exception 'Manager invited an administrator';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.create_tenant_invite(current_setting('test.tenant')::uuid, address, 'user', array['campaigns']);
    raise exception 'Manager granted a module they lack';
  exception when insufficient_privilege then null;
  end;
  invite := public.create_tenant_invite(current_setting('test.tenant')::uuid, address, 'user', array['inbox']);
  again := public.create_tenant_invite(current_setting('test.tenant')::uuid, lower(address), 'user', array['inbox', 'users']);
  if invite <> again then raise exception 'Re-inviting created a duplicate pending invite'; end if;
  if (select count(*) from public.tenant_invites where tenant_id = current_setting('test.tenant')::uuid
      and status = 'pending') <> 1 then raise exception 'Pending invite count mismatch'; end if;
  perform set_config('test.invite', invite::text, true);
end;
$$;

-- A stranger sees nothing and cannot accept someone else's invite.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.stranger'))::text, true);
do $$
begin
  if exists (select 1 from public.my_tenant_invites()) then raise exception 'Stranger sees invites'; end if;
  if exists (select 1 from public.tenant_invites) then raise exception 'Stranger reads invite table'; end if;
  begin
    perform public.respond_tenant_invite(current_setting('test.invite')::uuid, true);
    raise exception 'Stranger accepted an invite';
  exception when sqlstate 'P0002' then null;
  end;
  begin
    perform public.revoke_tenant_invite(current_setting('test.invite')::uuid);
    raise exception 'Stranger revoked an invite';
  exception when sqlstate 'P0002' then null;
  end;
end;
$$;

-- The invitee (case-insensitive email match) accepts once; retry is idempotent.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.invitee'))::text, true);
do $$
declare tenant uuid; member public.tenant_memberships;
begin
  if (select count(*) from public.my_tenant_invites()) <> 1 then raise exception 'Invitee cannot see the invite'; end if;
  tenant := public.respond_tenant_invite(current_setting('test.invite')::uuid, true);
  if tenant is distinct from current_setting('test.tenant')::uuid then raise exception 'Accept returned wrong tenant'; end if;
  select * into member from public.tenant_memberships where tenant_id = tenant and user_id = auth.uid();
  if member.role <> 'user' or member.permissions <> array['inbox', 'users'] then
    raise exception 'Accepted membership has wrong grants: % %', member.role, member.permissions;
  end if;
  if public.respond_tenant_invite(current_setting('test.invite')::uuid, true) is distinct from tenant then
    raise exception 'Accept retry was not idempotent';
  end if;
  begin
    perform public.respond_tenant_invite(current_setting('test.invite')::uuid, false);
    raise exception 'Accepted invite was declined later';
  exception when sqlstate 'P0012' then null;
  end;
  if exists (select 1 from public.my_tenant_invites()) then raise exception 'Accepted invite still listed'; end if;
end;
$$;

-- Admin revokes, decline and expiry paths.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.owner'))::text, true);
do $$
declare revoked uuid; expired uuid; stranger_email text := 'stranger-' || current_setting('test.stranger') || '@example.invalid';
begin
  revoked := public.create_tenant_invite(current_setting('test.tenant')::uuid, stranger_email, 'admin', array[]::text[]);
  if not (select permissions @> public.tenant_module_keys() from public.tenant_invites where id = revoked) then
    raise exception 'Admin invite did not grant every module';
  end if;
  if not public.revoke_tenant_invite(revoked) then raise exception 'Revoke failed'; end if;
  if public.revoke_tenant_invite(revoked) then raise exception 'Second revoke reported a change'; end if;
  expired := public.create_tenant_invite(current_setting('test.tenant')::uuid, stranger_email, 'user', array['inbox']);
  if expired = revoked then raise exception 'Revoked invite was reused'; end if;
  reset role;
  update public.tenant_invites set expires_at = now() - interval '1 minute' where id = expired;
  set local role authenticated;
  perform set_config('test.expired', expired::text, true);
end;
$$;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.stranger'))::text, true);
do $$
begin
  if exists (select 1 from public.my_tenant_invites()) then raise exception 'Expired invite listed'; end if;
  if public.respond_tenant_invite(current_setting('test.expired')::uuid, true) is not null then
    raise exception 'Expired invite accepted';
  end if;
  if exists (select 1 from public.tenant_memberships where user_id = auth.uid()) then
    raise exception 'Expired invite created a membership';
  end if;
end;
$$;
rollback;
