-- Catalog photos and bot listing photos. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.prepared_job(p_tenant uuid, p_connection uuid, p_phone text)
returns public.bot_reply_jobs language plpgsql as $$
declare conversation uuid; input_id uuid := gen_random_uuid(); v_job public.bot_reply_jobs; ctx jsonb;
begin
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (p_tenant, p_connection, p_phone, 'Photos', 'open') returning id into conversation;
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (input_id, p_tenant, conversation, p_connection, 'Customer', 'Egea''nın fotoğrafları var mı?', true);
  update public.conversations set last_customer_message_at = now() where id = conversation;
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id) values (p_tenant, conversation, input_id);
  select * into v_job from public.claim_bot_reply();
  ctx := public.bot_reply_context(v_job.id, v_job.lease_token);
  perform public.prepare_bot_reply(v_job.id, v_job.lease_token, (ctx->>'automation_revision')::bigint,
    (ctx->>'context_revision')::bigint, 'gpt-4o-mini', 3000, 100000);
  perform public.settle_bot_usage(v_job.id, v_job.lease_token, '{"input_tokens":900,"output_tokens":40,"total_tokens":940}');
  select * into v_job from public.bot_reply_jobs where id = v_job.id;
  return v_job;
end;
$$;
create function pg_temp.path(p_tenant uuid, p_resource uuid, p_n integer, p_ext text default 'jpg') returns text
language sql as $$
  select p_tenant || '/' || p_resource || '/' || lpad(p_n::text, 8, '0') || '-0000-4000-8000-000000000000.' || p_ext;
$$;

do $$
declare t uuid := gen_random_uuid(); t2 uuid := gen_random_uuid(); conn uuid := gen_random_uuid();
  agent uuid := gen_random_uuid(); car uuid := gen_random_uuid(); other_car uuid := gen_random_uuid(); car_type uuid;
begin
  insert into auth.users(id, email) values (agent, 'a-' || agent || '@example.invalid');
  insert into public.tenants(id, name) values (t, 'Galeri'), (t2, 'Baska Galeri');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values (t, agent, 'user', array['catalog']);
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '972001', '9720011', 'x', 'active', now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values (conn, t, 'fixture', repeat('A', 24), repeat('A', 16));
  insert into public.bot_settings(tenant_id, name, is_active) values (t, 'Ava', true);
  insert into public.resource_types(tenant_id, key, name, kind) values (t, 'vehicle', 'Araç', 'listing') returning id into car_type;
  insert into public.resources(id, tenant_id, type_id, name) values (car, t, car_type, '2019 Fiat Egea');
  insert into public.resource_types(tenant_id, key, name, kind) values (t2, 'vehicle', 'Araç', 'listing') returning id into car_type;
  insert into public.resources(id, tenant_id, type_id, name, photos)
    values (other_car, t2, car_type, 'Clio', array[pg_temp.path(t2, other_car, 1)]);

  -- An item's photo list may only name its own folder, once each, as JPG or PNG.
  update public.resources set photos = array[pg_temp.path(t, car, 1), pg_temp.path(t, car, 2, 'png')] where id = car;
  begin
    update public.resources set photos = array[pg_temp.path(t2, other_car, 1)] where id = car;
    raise exception 'Another business''s photo accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    update public.resources set photos = array[pg_temp.path(t, car, 1), pg_temp.path(t, car, 1)] where id = car;
    raise exception 'Duplicate photo accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    update public.resources set photos = array[pg_temp.path(t, car, 3, 'gif')] where id = car;
    raise exception 'GIF accepted';
  exception when sqlstate '22023' then null;
  end;
  insert into storage.objects(bucket_id, name, metadata) values
    ('catalog-photos', pg_temp.path(t, car, 1), '{"size": 120000}'),
    ('catalog-photos', pg_temp.path(t, car, 2, 'png'), '{"size": 80000}');
  perform set_config('test.t', t::text, true);
  perform set_config('test.t2', t2::text, true);
  perform set_config('test.conn', conn::text, true);
  perform set_config('test.agent', agent::text, true);
  perform set_config('test.car', car::text, true);
  perform set_config('test.other_car', other_car::text, true);
end;
$$;

-- Uploads: only into this business's own items, JPG or PNG.
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.agent'))::text, true);
do $$
declare t uuid := current_setting('test.t')::uuid; car uuid := current_setting('test.car')::uuid;
begin
  insert into storage.objects(bucket_id, name) values ('catalog-photos', pg_temp.path(t, car, 3));
  begin
    insert into storage.objects(bucket_id, name)
      values ('catalog-photos', pg_temp.path(current_setting('test.t2')::uuid, current_setting('test.other_car')::uuid, 2));
    raise exception 'Upload into another business accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id, name) values ('catalog-photos', pg_temp.path(t, car, 4, 'gif'));
    raise exception 'GIF upload accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id, name) values ('catalog-photos', pg_temp.path(t, gen_random_uuid(), 5));
    raise exception 'Upload for an unknown item accepted';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare t uuid := current_setting('test.t')::uuid; car uuid := current_setting('test.car')::uuid;
  job public.bot_reply_jobs; base jsonb; first_photo uuid; second_photo uuid; order_ok boolean;
begin
  job := pg_temp.prepared_job(t, current_setting('test.conn')::uuid, '905553330001');
  base := '{"action":"reply","text":"İşte Egea''nın fotoğrafları.","reason":"tool_answer","knowledge_ids":[]}';
  begin
    perform public.complete_bot_reply(job.id, job.lease_token, base || jsonb_build_object('photos', jsonb_build_array(
      jsonb_build_object('path', pg_temp.path(current_setting('test.t2')::uuid, current_setting('test.other_car')::uuid, 1)))));
    raise exception 'Another business''s photo sent';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.complete_bot_reply(job.id, job.lease_token, base || jsonb_build_object('photos', jsonb_build_array(
      jsonb_build_object('path', pg_temp.path(t, car, 9)))));
    raise exception 'A photo that is not on the item was sent';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.complete_bot_reply(job.id, job.lease_token, base || jsonb_build_object('photos', jsonb_build_array(
      jsonb_build_object('path', pg_temp.path(t, car, 1)), jsonb_build_object('path', pg_temp.path(t, car, 1)),
      jsonb_build_object('path', pg_temp.path(t, car, 1)), jsonb_build_object('path', pg_temp.path(t, car, 1)))));
    raise exception 'Four photos accepted';
  exception when sqlstate '22023' then null;
  end;

  if not public.complete_bot_reply(job.id, job.lease_token, base || jsonb_build_object('photos', jsonb_build_array(
      jsonb_build_object('path', pg_temp.path(t, car, 1), 'caption', '2019 Fiat Egea'),
      jsonb_build_object('path', pg_temp.path(t, car, 2, 'png'), 'caption', null)))) then
    raise exception 'Valid photos rejected';
  end if;
  first_photo := md5(job.id::text || ':photo:1')::uuid;
  second_photo := md5(job.id::text || ':photo:2')::uuid;
  if not exists (select 1 from public.messages where id = first_photo and message_type = 'image' and body = '2019 Fiat Egea'
      and sender = 'Ava' and not is_from_customer)
    or not exists (select 1 from public.messages where id = second_photo and body = '[image]') then
    raise exception 'Photo messages missing';
  end if;
  if not exists (select 1 from public.message_media where message_id = first_photo and storage_bucket = 'catalog-photos'
      and direction = 'outbound' and state = 'stored' and mime_type = 'image/jpeg' and size_bytes = 120000
      and caption = '2019 Fiat Egea')
    or not exists (select 1 from public.message_media where message_id = second_photo and mime_type = 'image/png'
      and caption is null) then
    raise exception 'Photo media rows wrong';
  end if;
  -- Text first, then the photos, all owned by the bot job.
  select bool_and(ok) into order_ok from (
    select d.source = 'bot' and d.bot_job_id = job.id
      and d.sequence > coalesce(lag(d.sequence) over (order by d.sequence), -1) as ok,
      d.id, row_number() over (order by d.sequence) as n
    from public.inbox_dispatches d where d.bot_job_id = job.id
  ) s;
  if (select count(*) from public.inbox_dispatches where bot_job_id = job.id) <> 3 or not order_ok
    or (select array_agg(id order by sequence) from public.inbox_dispatches where bot_job_id = job.id)
      <> array[job.id, first_photo, second_photo] then
    raise exception 'Dispatches not queued text-then-photos';
  end if;
  if not public.bot_dispatch_allowed(job.id, t, job.conversation_id, 'bot') then
    raise exception 'Photo dispatch would be refused';
  end if;
  update public.inbox_dispatches set state = 'cancelled' where bot_job_id = job.id;
end;
$$;
rollback;
