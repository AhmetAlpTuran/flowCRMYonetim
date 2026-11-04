-- Inbound media queue, leases, storage scoping and read access. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare t uuid := gen_random_uuid(); other uuid := gen_random_uuid(); agent uuid := gen_random_uuid();
  stranger uuid := gen_random_uuid(); conn uuid := gen_random_uuid(); conv uuid := gen_random_uuid();
  image_id uuid; doc_id uuid; job public.message_media; claimed integer;
begin
  insert into public.tenants(id, name) values (t, 'Media A'), (other, 'Media B');
  insert into auth.users(id, email, email_confirmed_at) values
    (agent, 'agent-' || agent || '@example.invalid', now()), (stranger, 'stranger-' || stranger || '@example.invalid', now());
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, agent, 'user', array['inbox']), (other, stranger, 'user', array['inbox']);
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '920000000001', '920000000002', '+90 555 000 0002', 'active', now());
  insert into public.conversations(id, tenant_id, title, status, connection_id, customer_phone)
    values (conv, t, 'Media', 'open', conn, '905552000001');

  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer, sent_at,
      message_type, provider_content) values
    (t, conv, conn, 'customer', '[image]', true, now(), 'image',
      '{"type":"image","image":{"id":"1111","mime_type":"image/jpeg","caption":"Araç fotoğrafı"}}')
    returning id into image_id;
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer, sent_at,
      message_type, provider_content) values
    (t, conv, conn, 'customer', '[document]', true, now(), 'document',
      '{"type":"document","document":{"id":"2222","mime_type":"application/pdf","filename":"ruhsat.pdf"}}')
    returning id into doc_id;
  -- Not queued: plain text, a malformed media id, and an outbound message.
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer, sent_at, message_type, provider_content)
    values (t, conv, conn, 'customer', 'merhaba', true, now(), 'text', '{"type":"text","text":{"body":"merhaba"}}'),
           (t, conv, conn, 'customer', '[audio]', true, now(), 'audio', '{"type":"audio","audio":{"id":"../x"}}'),
           (t, conv, conn, 'agent', '[image]', false, now(), 'image', '{"type":"image","image":{"id":"3333"}}');

  if (select count(*) from public.message_media where tenant_id = t) <> 2 then
    raise exception 'Unexpected media queue size';
  end if;
  select * into job from public.message_media where message_id = image_id;
  if job.kind <> 'image' or job.provider_media_id <> '1111' or job.mime_type <> 'image/jpeg'
    or job.caption <> 'Araç fotoğrafı' or job.state <> 'queued' then raise exception 'Image job not captured: %', job; end if;
  if (select file_name from public.message_media where message_id = doc_id) <> 'ruhsat.pdf' then
    raise exception 'Document file name lost';
  end if;

  select count(*) into claimed from public.claim_message_media(10) where tenant_id = t;
  if claimed <> 2 then raise exception 'Claim returned % jobs', claimed; end if;
  if exists (select 1 from public.claim_message_media(10) where tenant_id = t) then
    raise exception 'Leased jobs were claimed twice';
  end if;
  select * into job from public.message_media where message_id = image_id;
  if public.finish_message_media(image_id, gen_random_uuid(), 'stored', t || '/' || conv || '/x.jpg') then
    raise exception 'Stale lease finished a job';
  end if;
  begin
    perform public.finish_message_media(image_id, job.lease_token, 'stored', other || '/' || conv || '/x.jpg');
    raise exception 'Cross-tenant storage path accepted';
  exception when sqlstate '22023' then null;
  end;
  if not public.finish_message_media(image_id, job.lease_token, 'stored', t || '/' || conv || '/' || image_id || '.jpg', 2048, 'image/jpeg') then
    raise exception 'Valid finish rejected';
  end if;
  if (select state from public.message_media where message_id = image_id) <> 'stored' then raise exception 'Image not stored'; end if;

  -- Retry backs off; after five attempts the job fails instead of looping.
  select * into job from public.message_media where message_id = doc_id;
  perform public.finish_message_media(doc_id, job.lease_token, 'retry', null, null, null, 'whatsapp_transport');
  select * into job from public.message_media where message_id = doc_id;
  if job.state <> 'queued' or job.available_at <= now() + interval '30 seconds' then
    raise exception 'Retry did not back off: %', job.available_at - now();
  end if;
  update public.message_media set attempts = 4, available_at = now() where message_id = doc_id;
  select * into job from public.claim_message_media(10) where message_id = doc_id;
  perform public.finish_message_media(doc_id, job.lease_token, 'retry');
  if (select state from public.message_media where message_id = doc_id) <> 'failed' then
    raise exception 'Exhausted retries did not fail the job';
  end if;
  update public.message_media set state = 'leased', attempts = 5, lease_token = gen_random_uuid(),
    leased_until = now() - interval '1 second' where message_id = doc_id;
  perform public.claim_message_media(10);
  if (select error_code from public.message_media where message_id = doc_id) <> 'attempts_exhausted' then
    raise exception 'Expired final lease left the job stuck';
  end if;

  insert into storage.objects(bucket_id, name) values ('inbox-media', t || '/' || conv || '/' || image_id || '.jpg');
  perform set_config('test.tenant', t::text, true);
  perform set_config('test.agent', agent::text, true);
  perform set_config('test.stranger', stranger::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.agent'))::text, true);
do $$
begin
  if (select count(*) from public.message_media where tenant_id = current_setting('test.tenant')::uuid) <> 2 then
    raise exception 'Inbox agent cannot read media rows';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'inbox-media'
      and name like current_setting('test.tenant') || '/%') then
    raise exception 'Inbox agent cannot read the stored file';
  end if;
  begin
    perform public.claim_message_media(1);
    raise exception 'Client claimed media jobs';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.message_media set state = 'stored' where tenant_id = current_setting('test.tenant')::uuid;
    raise exception 'Client updated media rows';
  exception when insufficient_privilege then null;
  end;
end;
$$;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.stranger'))::text, true);
do $$
begin
  if exists (select 1 from public.message_media where tenant_id = current_setting('test.tenant')::uuid) then
    raise exception 'Other tenant sees media rows';
  end if;
  if exists (select 1 from storage.objects where bucket_id = 'inbox-media') then
    raise exception 'Other tenant sees stored files';
  end if;
end;
$$;
rollback;
