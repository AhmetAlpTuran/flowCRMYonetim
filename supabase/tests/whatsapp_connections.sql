-- Authored security regression cases. Execute only in the deferred verification phase.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare
  tenant_a uuid := gen_random_uuid(); tenant_b uuid := gen_random_uuid();
  admin_a uuid := gen_random_uuid(); admin_b uuid := gen_random_uuid(); manager_a uuid := gen_random_uuid();
  conn_a uuid := gen_random_uuid(); conn_b uuid := gen_random_uuid();
  metadata jsonb := '{"display_phone_number":"+90 555 000 0000","verified_name":"Fixture","token_expires_at":null}';
  -- Database-shape fixtures only; actual authenticated encryption has separate tests.
  credential jsonb := jsonb_build_object('key_id', 'fixture', 'ciphertext', repeat('A', 24), 'iv', repeat('A', 16));
begin
  insert into auth.users(id, email) values
    (admin_a, admin_a::text || '@example.invalid'), (admin_b, admin_b::text || '@example.invalid'),
    (manager_a, manager_a::text || '@example.invalid');
  insert into public.tenants(id, name) values (tenant_a, 'Connection test A'), (tenant_b, 'Connection test B');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (tenant_a, admin_a, 'admin', '{}'), (tenant_b, admin_b, 'admin', '{}'),
    (tenant_a, manager_a, 'user', '{users}');
  perform public.save_whatsapp_connection(tenant_a, admin_a, conn_a, '111', '1111', metadata, credential, true);
  perform public.save_whatsapp_connection(tenant_b, admin_b, conn_b, '222', '2222', metadata, credential, true);
  begin
    update public.whatsapp_connections set phone_number_id = '9999' where id = conn_a;
    raise exception 'Connection identity was repointed';
  exception when object_not_in_prerequisite_state then null; end;
  begin
    perform public.save_whatsapp_connection(tenant_a, manager_a, gen_random_uuid(), '111', '3333', metadata, credential, false);
    raise exception 'Delegated manager connected a WhatsApp account';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_whatsapp_connection(tenant_b, admin_b, gen_random_uuid(), '222', '1111', metadata, credential, false);
    raise exception 'One phone number mapped to two tenants';
  exception when unique_violation then null; end;
  begin
    insert into public.campaigns(tenant_id, name, status, connection_id)
      values (tenant_b, 'Cross-tenant connection', 'draft', conn_a);
    raise exception 'Cross-tenant campaign connection accepted';
  exception when foreign_key_violation then null; end;
  perform set_config('test.connection_admin', admin_a::text, true);
  perform set_config('test.connection_manager', manager_a::text, true);
  perform set_config('test.connection_tenant', tenant_a::text, true);
  perform set_config('test.connection_id', conn_a::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.connection_admin'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  if (select count(*) from public.whatsapp_connections) <> 1 then
    raise exception 'Connection metadata leaked across tenants';
  end if;
  begin
    perform ciphertext from public.whatsapp_connection_credentials;
    raise exception 'Administrator could read encrypted credentials';
  exception when insufficient_privilege then null; end;
  begin
    update public.whatsapp_connections set status = 'inactive';
    raise exception 'Administrator bypassed audited connection endpoint';
  exception when insufficient_privilege then null; end;
end;
$$;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.connection_manager'))::text, true);
do $$
declare changed integer;
begin
  update public.tenant_memberships set role = 'admin'
    where tenant_id = current_setting('test.connection_tenant')::uuid and user_id = auth.uid();
  get diagnostics changed = row_count;
  if changed <> 0 or public.is_tenant_admin(current_setting('test.connection_tenant')::uuid) then
    raise exception 'Users permission escalated to tenant administrator';
  end if;
  begin
    perform public.disconnect_whatsapp_connection(current_setting('test.connection_tenant')::uuid,
      auth.uid(), current_setting('test.connection_id')::uuid);
    raise exception 'Authenticated caller invoked a service-only connection mutation';
  exception when insufficient_privilege then null; end;
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
begin
  perform public.disconnect_whatsapp_connection(current_setting('test.connection_tenant')::uuid,
    current_setting('test.connection_admin')::uuid, current_setting('test.connection_id')::uuid);
  if exists (select 1 from public.whatsapp_connection_credentials where connection_id = current_setting('test.connection_id')::uuid) then
    raise exception 'Disconnect retained active credentials';
  end if;
  if not exists (select 1 from public.whatsapp_connections where id = current_setting('test.connection_id')::uuid and status = 'inactive') then
    raise exception 'Disconnect did not retain inactive metadata';
  end if;
end;
$$;
rollback;
