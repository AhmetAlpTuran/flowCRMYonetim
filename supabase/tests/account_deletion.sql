-- Account deletion plan and data removal. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare solo uuid := gen_random_uuid(); shared uuid := gen_random_uuid(); guarded uuid := gen_random_uuid();
  leaver uuid := gen_random_uuid(); colleague uuid := gen_random_uuid(); conv uuid := gen_random_uuid();
  plan jsonb;
begin
  insert into auth.users(id, email) values (leaver, 'leaver-' || leaver || '@example.invalid'),
    (colleague, 'colleague-' || colleague || '@example.invalid');
  insert into public.tenants(id, name) values (solo, 'Tek Kisilik'), (shared, 'Ortak'), (guarded, 'Tek Yonetici');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (solo, leaver, 'admin', array['inbox']),
    (shared, leaver, 'admin', array['inbox']), (shared, colleague, 'admin', array['inbox']),
    (guarded, leaver, 'admin', array['inbox']), (guarded, colleague, 'user', array['inbox']);
  insert into public.conversations(id, tenant_id, title, status, last_opened_by)
    values (conv, shared, 'Opened by leaver', 'open', leaver);

  plan := public.account_deletion_plan(leaver);
  if plan->'blocked' <> jsonb_build_array(jsonb_build_object('tenant_id', guarded, 'name', 'Tek Yonetici')) then
    raise exception 'Sole admin with members not blocked: %', plan;
  end if;
  if plan->'delete_tenants' <> jsonb_build_array(solo) or plan->'leave_tenants' <> jsonb_build_array(shared) then
    raise exception 'Plan wrong: %', plan;
  end if;
  begin
    perform public.delete_account_data(leaver);
    raise exception 'Blocked deletion proceeded';
  exception when sqlstate 'P0014' then null;
  end;
  if not exists (select 1 from public.tenants where id = solo) then raise exception 'Blocked deletion removed data'; end if;

  -- Promoting the colleague unblocks deletion.
  update public.tenant_memberships set role = 'admin' where tenant_id = guarded and user_id = colleague;
  plan := public.delete_account_data(leaver);
  if exists (select 1 from public.tenants where id = solo) then raise exception 'Sole-member business kept'; end if;
  if not exists (select 1 from public.tenants where id = shared) or not exists (select 1 from public.tenants where id = guarded) then
    raise exception 'Shared business deleted';
  end if;
  if (select count(*) from public.tenant_audit_events where action = 'member.account_deleted'
      and tenant_id in (shared, guarded)) <> 2 then raise exception 'Departures not audited'; end if;

  -- Deleting the Auth user now succeeds and cleans references.
  delete from auth.users where id = leaver;
  if exists (select 1 from public.tenant_memberships where user_id = leaver) then raise exception 'Membership survived'; end if;
  if exists (select 1 from public.user_profiles where id = leaver) then raise exception 'Profile survived'; end if;
  if (select last_opened_by from public.conversations where id = conv) is not null then
    raise exception 'Conversation still references the deleted user';
  end if;
  perform set_config('test.colleague', colleague::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.colleague'))::text, true);
do $$
begin
  if jsonb_array_length(public.my_account_deletion_plan()->'leave_tenants') <> 0 then
    raise exception 'Colleague plan wrong';
  end if;
  begin
    perform public.delete_account_data(current_setting('test.colleague')::uuid);
    raise exception 'Client ran service deletion';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.account_deletion_plan(gen_random_uuid());
    raise exception 'Client read another user''s plan';
  exception when insufficient_privilege then null;
  end;
end;
$$;
rollback;
