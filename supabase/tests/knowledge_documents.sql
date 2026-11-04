-- Knowledge documents, passages, embeddings and hybrid bot search. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

create function pg_temp.onehot(k integer) returns extensions.vector language sql as $$
  select ('[' || array_to_string(array(select case when i = k then 1 else 0 end
    from generate_series(1, 1536) i), ',') || ']')::extensions.vector;
$$;
create function pg_temp.onehot_json(k integer) returns jsonb language sql as $$
  select to_jsonb(array(select case when i = k then 1 else 0 end from generate_series(1, 1536) i));
$$;
create function pg_temp.leased_job(p_tenant uuid, p_connection uuid, p_phone text, p_body text)
returns public.bot_reply_jobs language plpgsql as $$
declare conversation uuid; input_id uuid := gen_random_uuid(); job public.bot_reply_jobs;
begin
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (p_tenant, p_connection, p_phone, 'Arama', 'open') returning id into conversation;
  insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (input_id, p_tenant, conversation, p_connection, 'Customer', p_body, true);
  update public.conversations set last_customer_message_at = now() where id = conversation;
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id) values (p_tenant, conversation, input_id);
  select * into job from public.claim_bot_reply();
  return job;
end;
$$;
create function pg_temp.as_user(p_user text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', p_user)::text, true);
$$;

do $$
declare t uuid := gen_random_uuid(); t2 uuid := gen_random_uuid(); conn uuid := gen_random_uuid();
  owner_id uuid := gen_random_uuid(); agent uuid := gen_random_uuid(); outsider uuid := gen_random_uuid();
  other_admin uuid := gen_random_uuid(); entry uuid; chunk public.knowledge_chunks;
begin
  insert into auth.users(id, email) values (owner_id, 'o-' || owner_id || '@example.invalid'),
    (agent, 'a-' || agent || '@example.invalid'), (outsider, 'x-' || outsider || '@example.invalid'),
    (other_admin, 'b-' || other_admin || '@example.invalid');
  insert into public.tenants(id, name) values (t, 'Otel'), (t2, 'Baska');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, owner_id, 'admin', public.tenant_module_keys()), (t, agent, 'user', array['knowledge']),
    (t, outsider, 'user', array['inbox']), (t2, other_admin, 'admin', public.tenant_module_keys());
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '975000000001', '975000000002', 'fixture', 'active', now());
  insert into public.whatsapp_connection_credentials(connection_id, tenant_id, key_id, ciphertext, iv)
    values (conn, t, 'fixture', repeat('A', 24), repeat('A', 16));
  insert into public.bot_settings(tenant_id, is_active) values (t, true);

  -- Manual entries get one passage, kept in sync with their text.
  insert into public.knowledge_base(tenant_id, title, content) values (t, 'Kahvaltı', 'Kahvaltı 08:00-10:30 arası, glutensiz menü var.')
    returning id into entry;
  select * into chunk from public.knowledge_chunks where entry_id = entry;
  if chunk.tenant_id <> t or chunk.heading <> 'Kahvaltı' or chunk.embedding is not null then
    raise exception 'Entry passage missing';
  end if;
  update public.knowledge_chunks set embedding = pg_temp.onehot(1), embedding_model = 'm1' where id = chunk.id;
  update public.knowledge_base set tags = array['yemek'] where id = entry;
  if (select embedding_model from public.knowledge_chunks where entry_id = entry) is distinct from 'm1' then
    raise exception 'Unchanged entry lost its embedding';
  end if;
  update public.knowledge_base set content = content || ' Hafta sonu 11:00''e kadar.' where id = entry;
  if (select embedding is not null or content not like '%Hafta sonu%' from public.knowledge_chunks where entry_id = entry) then
    raise exception 'Changed entry kept a stale embedding';
  end if;
  -- Another tenant's ready document with a passage on the same topic.
  insert into public.knowledge_documents(id, tenant_id, title, file_name, format, storage_path, size_bytes, state, chunk_count)
    values ('99999999-9999-4999-8999-999999999999', t2, 'Baska', 'b.txt', 'txt',
      t2 || '/99999999-9999-4999-8999-999999999999.txt', 10, 'ready', 1);
  insert into public.knowledge_chunks(tenant_id, document_id, ordinal, content, content_hash, embedding, embedding_model)
    values (t2, '99999999-9999-4999-8999-999999999999', 0, 'Otopark ücretli.', md5('b'), pg_temp.onehot(2), 'm1');

  -- Simulated uploads (the app writes these through Storage).
  insert into storage.objects(bucket_id, name, metadata) values
    ('knowledge-documents', t || '/11111111-1111-4111-8111-111111111111.pdf', '{"size": 2048}'),
    ('knowledge-documents', t || '/22222222-2222-4222-8222-222222222222.docx', '{"size": 4096}'),
    ('knowledge-documents', t || '/33333333-3333-4333-8333-333333333333.xlsx', '{"size": 20971520}');
  perform set_config('test.t', t::text, true);
  perform set_config('test.t2', t2::text, true);
  perform set_config('test.conn', conn::text, true);
  perform set_config('test.agent', agent::text, true);
  perform set_config('test.outsider', outsider::text, true);
  perform set_config('test.other', other_admin::text, true);
  perform set_config('test.entry', entry::text, true);
end;
$$;

set local role authenticated;
select pg_temp.as_user(current_setting('test.outsider'));
do $$
declare t uuid := current_setting('test.t')::uuid;
begin
  begin
    perform public.register_knowledge_document(t, '11111111-1111-4111-8111-111111111111', 'Otel', 'otel.pdf');
    raise exception 'Member without knowledge permission registered a document';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id, name) values ('knowledge-documents', t || '/44444444-4444-4444-8444-444444444444.pdf');
    raise exception 'Member without knowledge permission uploaded a file';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select pg_temp.as_user(current_setting('test.agent'));
do $$
declare t uuid := current_setting('test.t')::uuid; t2 uuid := current_setting('test.t2')::uuid;
  doc public.knowledge_documents; again public.knowledge_documents;
begin
  -- Storage: own tenant folder, supported extensions only.
  insert into storage.objects(bucket_id, name) values ('knowledge-documents', t || '/55555555-5555-4555-8555-555555555555.md');
  begin
    insert into storage.objects(bucket_id, name) values ('knowledge-documents', t2 || '/66666666-6666-4666-8666-666666666666.pdf');
    raise exception 'Upload into another tenant accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id, name) values ('knowledge-documents', t || '/77777777-7777-4777-8777-777777777777.exe');
    raise exception 'Executable upload accepted';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.register_knowledge_document(t, '88888888-8888-4888-8888-888888888888', 'Yok', 'yok.pdf');
    raise exception 'Registered a document without a file';
  exception when sqlstate 'P0002' then null;
  end;
  begin
    perform public.register_knowledge_document(t, '11111111-1111-4111-8111-111111111111', 'Otel', 'otel.exe');
    raise exception 'Unsupported format accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.register_knowledge_document(t, '33333333-3333-4333-8333-333333333333', 'Büyük', 'buyuk.xlsx');
    raise exception 'Oversized file accepted';
  exception when sqlstate '22023' then null;
  end;
  doc := public.register_knowledge_document(t, '11111111-1111-4111-8111-111111111111', ' Otel rehberi ', 'Otel Rehberi.PDF');
  if doc.state <> 'queued' or doc.format <> 'pdf' or doc.size_bytes <> 2048 or doc.title <> 'Otel rehberi'
    or doc.storage_path <> t || '/11111111-1111-4111-8111-111111111111.pdf'
    or doc.created_by <> current_setting('test.agent')::uuid then
    raise exception 'Registered document wrong: %', row_to_json(doc);
  end if;
  again := public.register_knowledge_document(t, '11111111-1111-4111-8111-111111111111', 'Başka', 'otel.pdf');
  if again.id <> doc.id or again.title <> 'Otel rehberi' then raise exception 'Re-registering changed the document'; end if;
  perform public.register_knowledge_document(t, '22222222-2222-4222-8222-222222222222', 'Kurallar', 'kurallar.docx');
  if (select count(*) from public.knowledge_documents) <> 2 then raise exception 'Agent cannot list documents'; end if;
  begin
    update public.knowledge_documents set state = 'ready' where id = doc.id;
    raise exception 'Client changed document state';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.claim_knowledge_document();
    raise exception 'Client claimed a document';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select pg_temp.as_user(current_setting('test.other'));
do $$
begin
  if exists (select 1 from public.knowledge_documents where tenant_id = current_setting('test.t')::uuid) then
    raise exception 'Documents leaked across tenants';
  end if;
  begin
    perform public.register_knowledge_document(current_setting('test.t2')::uuid,
      '11111111-1111-4111-8111-111111111111', 'Çalıntı', 'otel.pdf');
    raise exception 'Another tenant took over a document id';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare t uuid := current_setting('test.t')::uuid; job public.knowledge_documents; second public.knowledge_documents;
  version bigint; passages integer;
begin
  select * into job from public.claim_knowledge_document();
  select * into second from public.claim_knowledge_document();
  if job.state <> 'leased' or job.attempts <> 1 or second.id = job.id then raise exception 'Claim not fenced'; end if;
  if public.finish_knowledge_document(job.id, gen_random_uuid(), 'ready', '[{"content":"x"}]') then
    raise exception 'Stale lease finished a document';
  end if;
  begin
    perform public.finish_knowledge_document(job.id, job.lease_token, 'ready', '[{"content":""}]');
    raise exception 'Empty chunk accepted';
  exception when sqlstate '22023' then null;
  end;
  select revision into version from public.bot_context_versions where tenant_id = t;
  if not public.finish_knowledge_document(job.id, job.lease_token, 'ready',
      '[{"heading":"Sayfa 1","content":"Otopark ücretsizdir, 40 araçlık."},{"heading":null,"content":"Havuz 09:00-19:00 açık."}]', 3) then
    raise exception 'Valid chunks rejected';
  end if;
  select * into job from public.knowledge_documents where id = job.id;
  if job.state <> 'ready' or job.chunk_count <> 2 or job.page_count <> 3 or job.lease_token is not null then
    raise exception 'Document not ready: %', row_to_json(job);
  end if;
  if (select revision from public.bot_context_versions where tenant_id = t) <> version + 1 then
    raise exception 'Ready document did not change the bot context version';
  end if;

  -- The second document fails with a reason; an agent may queue it again.
  if not public.finish_knowledge_document(second.id, second.lease_token, 'failed', null, null, 'no_text') then
    raise exception 'Failure not recorded';
  end if;
  if (select state || ':' || error_code from public.knowledge_documents where id = second.id) <> 'failed:no_text' then
    raise exception 'Failure reason missing';
  end if;
  begin
    perform public.finish_knowledge_document(second.id, second.lease_token, 'failed', null, null, 'whatever');
    raise exception 'Unknown error code accepted';
  exception when sqlstate '22023' then null;
  end;

  -- Embedding queue: passages of ready documents and entries, not of failed ones.
  select count(*) into passages from public.claim_knowledge_embeddings('text-embedding-3-small', 50)
    where tenant_id = t;
  if passages <> 3 then raise exception 'Expected 3 passages to embed, got %', passages; end if;
  if exists (select 1 from public.claim_knowledge_embeddings('text-embedding-3-small', 50) where tenant_id = t) then
    raise exception 'Claimed passages were not backed off';
  end if;
end;
$$;

-- Search needs a leased bot job.
do $$
declare t uuid := current_setting('test.t')::uuid; t2 uuid := current_setting('test.t2')::uuid;
  conn uuid := current_setting('test.conn')::uuid; entry uuid := current_setting('test.entry')::uuid;
  bot public.bot_reply_jobs; parking_job public.bot_reply_jobs; ctx jsonb; result jsonb;
  parking uuid; pool uuid; other_parking uuid; saved integer;
begin
  select id into parking from public.knowledge_chunks where tenant_id = t and content like 'Otopark%';
  select id into pool from public.knowledge_chunks where tenant_id = t and content like 'Havuz%';
  select id into other_parking from public.knowledge_chunks where tenant_id = t2 and document_id is not null;

  saved := public.save_knowledge_embeddings(t, 'm1', 120, jsonb_build_array(
    jsonb_build_object('id', parking, 'content_hash', (select content_hash from public.knowledge_chunks where id = parking),
      'embedding', pg_temp.onehot_json(2)),
    jsonb_build_object('id', pool, 'content_hash', 'ffffffffffffffffffffffffffffffff', 'embedding', pg_temp.onehot_json(3)),
    jsonb_build_object('id', other_parking, 'content_hash', md5('b'), 'embedding', pg_temp.onehot_json(3))));
  if saved <> 1 then raise exception 'Expected only the matching passage of the tenant to be saved, got %', saved; end if;
  if (select embedding_model from public.knowledge_chunks where id = parking) <> 'm1'
    or (select embedding is not null from public.knowledge_chunks where id = pool) then
    raise exception 'Embeddings saved to the wrong passages';
  end if;
  update public.knowledge_chunks set embedding = pg_temp.onehot(1), embedding_model = 'm1' where entry_id = entry;
  if (select embedding_tokens from public.tenant_ai_usage where tenant_id = t) <> 120 then
    raise exception 'Embedding tokens not recorded';
  end if;
  begin
    perform public.save_knowledge_embeddings(t, 'm1', 1, jsonb_build_array(
      jsonb_build_object('id', pool, 'content_hash', 'x', 'embedding', '[1,2,3]'::jsonb)));
    raise exception 'Wrong dimensions accepted';
  exception when sqlstate '22023' then null;
  end;

  bot := pg_temp.leased_job(t, conn, '905557770001', 'Kahvaltıda glutensiz seçenek var mı?');
  parking_job := pg_temp.leased_job(t, conn, '905557770002', 'Arabamı nereye bırakırım, otoparkınız ücretli mi?');
  if public.bot_knowledge_search(bot.id, gen_random_uuid()) is not null then
    raise exception 'Search ran without the job lease';
  end if;
  -- Full text: Turkish suffixes still match ("kahvaltıda" -> kahval:*, "otoparkınız" -> otopark:*).
  result := public.bot_knowledge_search(bot.id, bot.lease_token);
  if result->0->>'id' <> entry::text or result->0->>'content' not like 'Kahvaltı 08:00%'
    or result @> jsonb_build_array(jsonb_build_object('id', parking)) then
    raise exception 'Lexical entry match wrong: %', result;
  end if;
  result := public.bot_knowledge_search(parking_job.id, parking_job.lease_token);
  if result->0->>'id' <> parking::text or result->0->>'title' <> 'Otel rehberi – Sayfa 1' then
    raise exception 'Lexical passage match wrong: %', result;
  end if;
  -- Typed without Turkish letters, the same passage is found.
  if public.knowledge_search_query('otoparkiniz UCRETLI mi') <> public.knowledge_search_query('Otoparkınız ücretli mi')
    or not public.knowledge_fold('Şişli Ğ İğne ıüöç') = 'sisli g igne iuoc' then
    raise exception 'Turkish letters not folded: %', public.knowledge_search_query('otoparkiniz UCRETLI mi');
  end if;
  -- Vector: the parking passage joins the kahvaltı results on meaning alone, and the
  -- other tenant's passage never appears.
  result := public.bot_knowledge_search(bot.id, bot.lease_token, pg_temp.onehot(2), 'm1', 9);
  if not result @> jsonb_build_array(jsonb_build_object('id', parking))
    or not result @> jsonb_build_array(jsonb_build_object('id', entry))
    or result::text like '%' || other_parking || '%' then
    raise exception 'Semantic match wrong: %', result;
  end if;
  if (select embedding_tokens from public.tenant_ai_usage where tenant_id = t) <> 129 then
    raise exception 'Query embedding tokens not recorded';
  end if;
  -- Embeddings of another model are ignored.
  result := public.bot_knowledge_search(bot.id, bot.lease_token, pg_temp.onehot(2), 'm2', 0);
  if result @> jsonb_build_array(jsonb_build_object('id', parking)) then
    raise exception 'Other-model embeddings used: %', result;
  end if;
  begin
    perform public.bot_knowledge_search(bot.id, bot.lease_token, '[1,2]'::extensions.vector, 'm1', 0);
    raise exception 'Short query embedding accepted';
  exception when sqlstate '22023' then null;
  end;

  -- Document passages are valid reply sources; another tenant's are not.
  ctx := public.bot_reply_context(bot.id, bot.lease_token);
  perform public.prepare_bot_reply(bot.id, bot.lease_token, (ctx->>'automation_revision')::bigint,
    (ctx->>'context_revision')::bigint, 'gpt-4o-mini', 3000, 100000);
  perform public.settle_bot_usage(bot.id, bot.lease_token, '{"input_tokens":900,"output_tokens":40,"total_tokens":940}');
  begin
    perform public.complete_bot_reply(bot.id, bot.lease_token, jsonb_build_object('action', 'reply',
      'text', 'Otopark ücretsiz.', 'reason', 'knowledge_answer', 'knowledge_ids', jsonb_build_array(other_parking)));
    raise exception 'Another tenant''s passage accepted as a source';
  exception when sqlstate '22023' then null;
  end;
  if not public.complete_bot_reply(bot.id, bot.lease_token, jsonb_build_object('action', 'reply',
      'text', 'Otopark ücretsizdir.', 'reason', 'knowledge_answer', 'knowledge_ids', jsonb_build_array(parking, entry))) then
    raise exception 'Document passage rejected as a source';
  end if;
  perform set_config('test.parking', parking::text, true);
end;
$$;

-- Agents retry failures and delete documents; passages go with them.
set local role authenticated;
select pg_temp.as_user(current_setting('test.agent'));
do $$
declare t uuid := current_setting('test.t')::uuid;
begin
  if not public.retry_knowledge_document(t, '22222222-2222-4222-8222-222222222222') then
    raise exception 'Failed document could not be retried';
  end if;
  if public.retry_knowledge_document(t, '11111111-1111-4111-8111-111111111111') then
    raise exception 'Ready document was re-queued';
  end if;
  if not public.delete_knowledge_document(t, '11111111-1111-4111-8111-111111111111') then
    raise exception 'Delete failed';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
begin
  if exists (select 1 from public.knowledge_chunks where id = current_setting('test.parking')::uuid) then
    raise exception 'Passages survived their document';
  end if;
  if (select state from public.knowledge_documents where id = '22222222-2222-4222-8222-222222222222') <> 'queued' then
    raise exception 'Retry did not queue the document';
  end if;
  if not exists (select 1 from public.tenant_audit_events where tenant_id = current_setting('test.t')::uuid
      and action = 'knowledge.document_deleted') then
    raise exception 'Delete not audited';
  end if;
end;
$$;
rollback;
