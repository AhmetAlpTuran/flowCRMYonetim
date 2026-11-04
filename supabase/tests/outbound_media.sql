-- Outbound images/documents: upload policy, enqueue rules, idempotency. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare t uuid := gen_random_uuid(); other uuid := gen_random_uuid(); agent uuid := gen_random_uuid();
  conn uuid := gen_random_uuid(); conv uuid := gen_random_uuid(); other_conv uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values (agent, 'agent-' || agent || '@example.invalid');
  insert into public.tenants(id, name) values (t, 'Outbound media A'), (other, 'Outbound media B');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values (t, agent, 'user', array['inbox']);
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '940000000001', '940000000002', 'fixture', 'active', now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values (conn, t, 'fixture', repeat('A', 24), repeat('A', 16));
  insert into public.conversations(id, tenant_id, connection_id, customer_phone, title, status, last_customer_message_at)
    values (conv, t, conn, '905554440001', 'Media out', 'open', now());
  insert into public.conversations(id, tenant_id, title, status) values (other_conv, other, 'Other', 'open');
  perform set_config('test.tenant', t::text, true);
  perform set_config('test.other', other::text, true);
  perform set_config('test.other_conv', other_conv::text, true);
  perform set_config('test.agent', agent::text, true);
  perform set_config('test.conv', conv::text, true);
  perform set_config('test.msg', gen_random_uuid()::text, true);
  perform set_config('test.doc', gen_random_uuid()::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.agent'))::text, true);
do $$
declare t text := current_setting('test.tenant'); conv text := current_setting('test.conv');
  msg text := current_setting('test.msg'); doc text := current_setting('test.doc');
  path text := t || '/' || conv || '/outbound/' || msg || '.jpg';
  doc_path text := t || '/' || conv || '/outbound/' || doc || '.pdf';
  result jsonb; again jsonb;
begin
  -- Upload policy: own tenant/conversation outbound folder only.
  begin
    insert into storage.objects(bucket_id, name) values ('inbox-media',
      current_setting('test.other') || '/' || current_setting('test.other_conv') || '/outbound/' || msg || '.jpg');
    raise exception 'Upload into another tenant allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id, name) values ('inbox-media', t || '/' || conv || '/' || msg || '.jpg');
    raise exception 'Upload outside the outbound folder allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id, name) values ('inbox-media', t || '/' || conv || '/outbound/' || msg || '.exe');
    raise exception 'Executable upload allowed';
  exception when insufficient_privilege then null;
  end;
  insert into storage.objects(bucket_id, name, metadata) values
    ('inbox-media', path, '{"size": 2048, "mimetype": "image/jpeg"}'),
    ('inbox-media', doc_path, '{"size": 17000000, "mimetype": "application/pdf"}');

  -- Enqueue validation.
  begin
    perform public.enqueue_inbox_media_message(t::uuid, conv::uuid, gen_random_uuid(), path, 'image', 'image/jpeg');
    raise exception 'Path for another message accepted';
  exception when sqlstate 'P0009' then null;
  end;
  begin
    perform public.enqueue_inbox_media_message(t::uuid, conv::uuid, msg::uuid, path, 'image', 'image/gif');
    raise exception 'Unsupported MIME type accepted';
  exception when sqlstate 'P0009' then null;
  end;
  begin
    perform public.enqueue_inbox_media_message(t::uuid, conv::uuid, doc::uuid, doc_path, 'document', 'application/pdf');
    raise exception 'Oversized document accepted';
  exception when sqlstate 'P0009' then null;
  end;
  begin
    perform public.enqueue_inbox_media_message(t::uuid, conv::uuid, msg::uuid, path, 'image', 'image/jpeg', null, repeat('x', 1025));
    raise exception 'Overlong caption accepted';
  exception when sqlstate 'P0009' then null;
  end;
  begin
    perform public.enqueue_inbox_media_message(t::uuid, conv::uuid, gen_random_uuid(),
      t || '/' || conv || '/outbound/' || gen_random_uuid() || '.jpg', 'image', 'image/jpeg');
    raise exception 'Missing upload accepted';
  exception when sqlstate 'P0009' then null;
  end;

  result := public.enqueue_inbox_media_message(t::uuid, conv::uuid, msg::uuid, path, 'image', 'image/jpeg',
    'arac.jpg', 'Aracın ön tarafı');
  if result->>'state' <> 'queued' then raise exception 'Media reply not queued: %', result; end if;
  again := public.enqueue_inbox_media_message(t::uuid, conv::uuid, msg::uuid, path, 'image', 'image/jpeg',
    'arac.jpg', 'Aracın ön tarafı');
  if again->>'message_id' <> msg then raise exception 'Retry was not idempotent: %', again; end if;
  if not exists (select 1 from public.messages where id = msg::uuid and message_type = 'image'
      and body = 'Aracın ön tarafı' and not is_from_customer and sent_by = auth.uid()) then
    raise exception 'Outbound message row wrong';
  end if;
  if (select count(*) from public.message_media where message_id = msg::uuid and direction = 'outbound'
      and state = 'stored' and storage_path = path and size_bytes = 2048 and caption = 'Aracın ön tarafı') <> 1 then
    raise exception 'Outbound media row wrong';
  end if;
  if (select status from public.conversations where id = conv::uuid) <> 'pending' then
    raise exception 'Media reply did not take ownership like a text reply';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
begin
  if not exists (select 1 from public.inbox_dispatches where id = current_setting('test.msg')::uuid and state = 'queued') then
    raise exception 'No dispatch for the media reply';
  end if;
  if exists (select 1 from public.claim_message_media(20) where direction = 'outbound') then
    raise exception 'Download worker claimed an outbound file';
  end if;
end;
$$;
rollback;
