-- Industry pack setup: types, prompt, knowledge from answers, idempotency. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare t uuid := gen_random_uuid(); t2 uuid := gen_random_uuid(); owner_id uuid := gen_random_uuid();
  agent uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values (owner_id, 'owner-' || owner_id || '@example.invalid'),
    (agent, 'agent-' || agent || '@example.invalid');
  insert into public.tenants(id, name) values (t, 'Galeri'), (t2, 'Ozel Bot');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, owner_id, 'admin', public.tenant_module_keys()), (t2, owner_id, 'admin', public.tenant_module_keys()),
    (t, agent, 'user', array['bot', 'knowledge', 'catalog']);
  insert into public.bot_settings(tenant_id, system_prompt, is_active) values (t2, 'Benim özel talimatım.', true);
  perform set_config('test.t', t::text, true);
  perform set_config('test.t2', t2::text, true);
  perform set_config('test.owner', owner_id::text, true);
  perform set_config('test.agent', agent::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);

select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.agent'))::text, true);
do $$
begin
  perform public.apply_industry_pack(current_setting('test.t')::uuid, 'auto_dealer', '{}');
  raise exception 'Non-admin applied a pack';
exception when insufficient_privilege then null;
end;
$$;

select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.owner'))::text, true);
do $$
declare t uuid := current_setting('test.t')::uuid; t2 uuid := current_setting('test.t2')::uuid; result jsonb;
begin
  begin
    perform public.apply_industry_pack(t, 'casino', '{}');
    raise exception 'Unknown pack accepted';
  exception when sqlstate '22023' then null;
  end;
  if jsonb_array_length(public.industry_packs()) <> 3 then raise exception 'Pack list wrong'; end if;

  result := public.apply_industry_pack(t, 'auto_dealer',
    '{"address":"Bağdat Cd. No:1, Kadıköy. Hafta içi 09-19.","test_drive":"Ehliyetle, randevulu.","financing":"  ","unknown":"x"}');
  if result <> '{"types_added":1,"knowledge_added":2,"knowledge_updated":0,"prompt_applied":true,"bot_active":false}'::jsonb then
    raise exception 'First apply wrong: %', result;
  end if;
  if not exists (select 1 from public.resource_types where tenant_id = t and key = 'vehicle'
      and jsonb_array_length(fields) = 7) then raise exception 'Vehicle type missing'; end if;
  if (select count(*) from public.knowledge_base where tenant_id = t) <> 2
    or not exists (select 1 from public.knowledge_base where tenant_id = t and title = 'Test sürüşü koşulları'
      and content = 'Ehliyetle, randevulu.' and tags = array['paket:auto_dealer']) then
    raise exception 'Knowledge from answers wrong';
  end if;
  if (select system_prompt from public.bot_settings where tenant_id = t) not like 'Bu oto galerinin satış danışmanısın.%'
    or (select is_active from public.bot_settings where tenant_id = t) then
    raise exception 'Pack prompt not applied or bot switched on';
  end if;

  result := public.apply_industry_pack(t, 'auto_dealer',
    '{"address":"Bağdat Cd. No:1, Kadıköy. Hafta içi 09-19.","test_drive":"Ehliyetle, randevulu, 30 dk.","trade_in":"Takas kabul edilir."}');
  if result <> '{"types_added":0,"knowledge_added":1,"knowledge_updated":1,"prompt_applied":true,"bot_active":false}'::jsonb then
    raise exception 'Re-apply wrong: %', result;
  end if;
  if (select count(*) from public.knowledge_base where tenant_id = t) <> 3 then raise exception 'Re-apply duplicated knowledge'; end if;

  -- Adding a second pack keeps the first catalog type.
  perform public.apply_industry_pack(t, 'rental', '{}');
  if (select count(*) from public.resource_types where tenant_id = t) <> 2 then raise exception 'Second pack type missing'; end if;

  -- A custom prompt and an active bot are never overwritten.
  result := public.apply_industry_pack(t2, 'rental', '{"payment":"Kapora %30."}');
  if (result->>'prompt_applied')::boolean or not (result->>'bot_active')::boolean
    or (select system_prompt from public.bot_settings where tenant_id = t2) <> 'Benim özel talimatım.' then
    raise exception 'Custom prompt overwritten: %', result;
  end if;
end;
$$;
rollback;
