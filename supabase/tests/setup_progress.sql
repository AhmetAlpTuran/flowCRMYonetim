-- First-run setup checklist. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare t uuid := gen_random_uuid(); owner_id uuid := gen_random_uuid(); member uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values (owner_id, 'o-' || owner_id || '@example.invalid'),
    (member, 'm-' || member || '@example.invalid');
  insert into public.tenants(id, name) values (t, 'Yeni');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, owner_id, 'admin', public.tenant_module_keys());
  perform set_config('test.t', t::text, true);
  perform set_config('test.owner', owner_id::text, true);
  perform set_config('test.member', member::text, true);
end;
$$;

select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.owner'))::text, true);
do $$
declare t uuid := current_setting('test.t')::uuid; progress jsonb;
begin
  progress := public.tenant_setup_progress(t);
  if progress <> '{"whatsapp":false,"knowledge":false,"bot":false,"catalog":false,"team":false,"contacts":false,"billing":false}'::jsonb then
    raise exception 'A new business should have nothing done: %', progress;
  end if;
  insert into public.whatsapp_connections(tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (t, '975001', '9750011', 'x', 'active', now());
  insert into public.knowledge_base(tenant_id, title, content) values (t, 'Saatler', 'Hafta içi 9-18.');
  insert into public.bot_settings(tenant_id, is_active) values (t, true);
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions)
    values (t, current_setting('test.member')::uuid, 'user', array['inbox']);
  progress := public.tenant_setup_progress(t);
  if not ((progress->>'whatsapp')::boolean and (progress->>'knowledge')::boolean and (progress->>'bot')::boolean
      and (progress->>'team')::boolean) or (progress->>'catalog')::boolean then
    raise exception 'Completed steps not detected: %', progress;
  end if;
end;
$$;

select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.member'))::text, true);
do $$
begin
  perform public.tenant_setup_progress(current_setting('test.t')::uuid);
  raise exception 'A non-admin read the setup progress';
exception when insufficient_privilege then null;
end;
$$;
rollback;
