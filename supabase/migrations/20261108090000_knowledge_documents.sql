-- Knowledge documents and semantic search (roadmap Phase 2f).
--
-- Businesses upload PDF, Word, Excel, CSV, Markdown or text files into the private
-- knowledge-documents bucket ({tenant}/{document}.{ext}). register_knowledge_document
-- queues the file; knowledge-worker extracts its text into knowledge_chunks and embeds
-- every chunk (documents and manual knowledge_base entries) with pgvector.
-- bot_knowledge_search fuses full-text and vector rankings for the bot worker, with
-- full-text search alone whenever embeddings are unavailable.

create extension if not exists vector with schema extensions;

insert into storage.buckets(id, name, public)
  values ('knowledge-documents', 'knowledge-documents', false)
  on conflict (id) do nothing;

alter table public.knowledge_base add constraint knowledge_base_tenant_id_key unique (tenant_id, id);
-- Entries never move between tenants. This runs before the passage foreign key below,
-- so the attempt reports the immutability error rather than a key violation.
create function public.prevent_knowledge_tenant_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.tenant_id is distinct from old.tenant_id then
    raise exception 'Tenant identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger knowledge_base_tenant_immutable before update of tenant_id on public.knowledge_base
  for each row execute function public.prevent_knowledge_tenant_change();
revoke all on function public.prevent_knowledge_tenant_change() from public, anon, authenticated;
alter table public.tenant_ai_usage
  add column if not exists embedding_tokens bigint not null default 0 check (embedding_tokens >= 0);

create table public.knowledge_documents (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 250),
  file_name text not null check (length(file_name) between 1 and 255),
  format text not null check (format in ('pdf', 'docx', 'xlsx', 'csv', 'txt', 'md')),
  storage_path text not null unique,
  size_bytes bigint not null check (size_bytes between 1 and 10485760),
  state text not null default 'queued' check (state in ('queued', 'leased', 'ready', 'failed')),
  error_code text check (error_code is null or error_code ~ '^[a-z_]{1,60}$'),
  attempts integer not null default 0 check (attempts between 0 and 3),
  available_at timestamptz not null default now(),
  lease_token uuid,
  leased_until timestamptz,
  chunk_count integer not null default 0 check (chunk_count between 0 and 400),
  char_count integer not null default 0 check (char_count >= 0),
  page_count integer check (page_count is null or page_count >= 0),
  created_by uuid references auth.users(id) on delete set null,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  check (storage_path = tenant_id::text || '/' || id::text || '.' || format),
  check (state <> 'leased' or (lease_token is not null and leased_until is not null))
);
create index knowledge_documents_tenant on public.knowledge_documents(tenant_id, created_at desc);
create index knowledge_documents_claimable on public.knowledge_documents(available_at)
  where state in ('queued', 'leased');

-- One row per searchable passage: a document chunk, or the single passage of a
-- manual entry (kept in sync by a trigger). Embeddings are filled by the worker.
create table public.knowledge_chunks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  document_id uuid,
  entry_id uuid unique,
  ordinal integer not null check (ordinal between 0 and 399),
  heading text check (heading is null or length(heading) <= 250),
  content text not null check (length(content) between 1 and 4000),
  content_hash text not null check (content_hash ~ '^[0-9a-f]{32}$'),
  embedding extensions.vector(1536),
  embedding_model text check (embedding_model is null or embedding_model ~ '^[a-zA-Z0-9_.:-]{1,100}$'),
  embedding_attempts integer not null default 0,
  embedding_available_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (tenant_id, document_id) references public.knowledge_documents(tenant_id, id) on delete cascade,
  foreign key (tenant_id, entry_id) references public.knowledge_base(tenant_id, id) on delete cascade,
  check ((document_id is null) <> (entry_id is null)),
  check ((embedding is null) = (embedding_model is null)),
  unique (document_id, ordinal)
);
create index knowledge_chunks_tenant on public.knowledge_chunks(tenant_id);

-- Customers often type without Turkish letters ("ucretli", "kahvalti"), so search
-- compares text with those letters folded to ASCII on both sides.
create function public.knowledge_fold(p_text text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select translate(p_text, 'İIıÇçĞğÖöŞşÜüÂâÎîÛû', 'iiiccggoossuuaaiiuu');
$$;
create index knowledge_chunks_full_text on public.knowledge_chunks
  using gin (to_tsvector('simple', public.knowledge_fold(coalesce(heading, '') || ' ' || content))) where document_id is not null;
create index knowledge_base_folded_text on public.knowledge_base
  using gin (to_tsvector('simple', public.knowledge_fold(left(title, 250) || ' ' || left(content, 50000))));
create index knowledge_chunks_embedding_queue on public.knowledge_chunks(embedding_available_at)
  where embedding is null;

alter table public.knowledge_documents enable row level security;
alter table public.knowledge_chunks enable row level security;
create policy knowledge_documents_read on public.knowledge_documents for select to authenticated
  using (public.user_has_permission(tenant_id, 'knowledge'));
revoke insert, update, delete on public.knowledge_documents from anon, authenticated;
revoke all on public.knowledge_chunks from anon, authenticated;
grant all on public.knowledge_documents, public.knowledge_chunks to service_role;

-- Files: only {tenant}/{document}.{ext} in the caller's tenant, with the knowledge permission.
create policy knowledge_documents_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'knowledge-documents'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|docx|xlsx|csv|txt|md)$'
    and public.user_has_permission(((storage.foldername(name))[1])::uuid, 'knowledge'));
create policy knowledge_documents_file_read on storage.objects for select to authenticated
  using (
    bucket_id = 'knowledge-documents'
    and (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and public.user_has_permission(((storage.foldername(name))[1])::uuid, 'knowledge'));
create policy knowledge_documents_file_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'knowledge-documents'
    and (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and public.user_has_permission(((storage.foldername(name))[1])::uuid, 'knowledge'));

create function public.bump_bot_context_version(p_tenant_id uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.bot_context_versions(tenant_id) values (p_tenant_id)
    on conflict (tenant_id) do update set revision = public.bot_context_versions.revision + 1;
$$;

-- Manual entries get one passage (title + first 4000 characters) for vector search;
-- an unchanged text keeps its embedding (see reset_knowledge_chunk_embedding).
create function public.sync_knowledge_entry_chunk()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  passage text := left(new.content, 4000);
  heading text := left(new.title, 250);
begin
  insert into public.knowledge_chunks(tenant_id, entry_id, ordinal, heading, content, content_hash)
    values (new.tenant_id, new.id, 0, heading, passage, md5(heading || E'\n' || passage))
    on conflict (entry_id) do update set heading = excluded.heading, content = excluded.content,
      content_hash = excluded.content_hash;
  return new;
end;
$$;
create trigger knowledge_entry_chunk after insert or update of title, content on public.knowledge_base
  for each row execute function public.sync_knowledge_entry_chunk();
insert into public.knowledge_chunks(tenant_id, entry_id, ordinal, heading, content, content_hash)
  select tenant_id, id, 0, left(title, 250), left(content, 4000), md5(left(title, 250) || E'\n' || left(content, 4000))
  from public.knowledge_base
  on conflict (entry_id) do nothing;

create function public.knowledge_document_format(p_name text)
returns text language sql immutable set search_path = '' as $$
  select lower(substring(p_name from '\.([A-Za-z]{2,4})$'))
  where lower(substring(p_name from '\.([A-Za-z]{2,4})$')) in ('pdf', 'docx', 'xlsx', 'csv', 'txt', 'md');
$$;

-- The app uploads the file first, then registers it. Size and existence come from
-- Storage, never from the client. Re-registering the same document is a no-op.
create function public.register_knowledge_document(
  p_tenant_id uuid, p_document_id uuid, p_title text, p_file_name text
) returns public.knowledge_documents
language plpgsql security definer set search_path = '' as $$
declare
  existing public.knowledge_documents;
  object_name text;
  object_size bigint;
  doc_format text;
  doc public.knowledge_documents;
begin
  if p_tenant_id is null or p_document_id is null or not public.user_has_permission(p_tenant_id, 'knowledge') then
    raise exception 'Knowledge permission required' using errcode = '42501';
  end if;
  select * into existing from public.knowledge_documents where id = p_document_id;
  if found then
    if existing.tenant_id <> p_tenant_id then
      raise exception 'Knowledge permission required' using errcode = '42501';
    end if;
    return existing;
  end if;
  if length(btrim(coalesce(p_title, ''))) not between 1 and 250
    or length(coalesce(p_file_name, '')) not between 1 and 255 then
    raise exception 'Invalid document' using errcode = '22023';
  end if;
  doc_format := public.knowledge_document_format(p_file_name);
  if doc_format is null then
    raise exception 'Unsupported document format' using errcode = '22023';
  end if;
  object_name := p_tenant_id::text || '/' || p_document_id::text || '.' || doc_format;
  select (o.metadata->>'size')::bigint into object_size from storage.objects o
    where o.bucket_id = 'knowledge-documents' and o.name = object_name;
  if not found then
    raise exception 'Uploaded file not found' using errcode = 'P0002';
  end if;
  if coalesce(object_size, 0) not between 1 and 10485760 then
    raise exception 'Document too large' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('knowledge_documents:' || p_tenant_id::text));
  if (select count(*) from public.knowledge_documents where tenant_id = p_tenant_id) >= 50 then
    raise exception 'Document limit reached' using errcode = 'P0001', hint = 'document_limit';
  end if;
  insert into public.knowledge_documents(id, tenant_id, title, file_name, format, storage_path, size_bytes, created_by)
    values (p_document_id, p_tenant_id, btrim(p_title), p_file_name, doc_format, object_name, object_size, auth.uid())
    returning * into doc;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (p_tenant_id, auth.uid(), 'knowledge.document_added', doc.id,
      jsonb_build_object('file_name', doc.file_name, 'size_bytes', doc.size_bytes));
  return doc;
end;
$$;

-- The app removes the Storage object first; deleting the row removes its passages.
create function public.delete_knowledge_document(p_tenant_id uuid, p_document_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare doc public.knowledge_documents;
begin
  if p_tenant_id is null or not public.user_has_permission(p_tenant_id, 'knowledge') then
    raise exception 'Knowledge permission required' using errcode = '42501';
  end if;
  delete from public.knowledge_documents where tenant_id = p_tenant_id and id = p_document_id
    returning * into doc;
  if not found then return false; end if;
  if doc.state = 'ready' then perform public.bump_bot_context_version(p_tenant_id); end if;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, resource_id, details)
    values (p_tenant_id, auth.uid(), 'knowledge.document_deleted', doc.id,
      jsonb_build_object('file_name', doc.file_name));
  return true;
end;
$$;

create function public.retry_knowledge_document(p_tenant_id uuid, p_document_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_tenant_id is null or not public.user_has_permission(p_tenant_id, 'knowledge') then
    raise exception 'Knowledge permission required' using errcode = '42501';
  end if;
  update public.knowledge_documents set state = 'queued', attempts = 0, error_code = null,
    available_at = now(), updated_at = now()
    where tenant_id = p_tenant_id and id = p_document_id and state = 'failed';
  return found;
end;
$$;

-- Worker: fenced leases, at most three attempts per document.
create function public.claim_knowledge_document()
returns setof public.knowledge_documents language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  update public.knowledge_documents set state = 'failed', error_code = 'attempts_exhausted',
    lease_token = null, leased_until = null, updated_at = now()
    where state = 'leased' and leased_until <= now() and attempts >= 3;
  return query
  with candidate as (
    select d.id from public.knowledge_documents d
    where ((d.state = 'queued' and d.available_at <= now()) or (d.state = 'leased' and d.leased_until <= now()))
      and d.attempts < 3
    order by d.available_at, d.id limit 1
    for update skip locked
  )
  update public.knowledge_documents d set state = 'leased', lease_token = gen_random_uuid(),
    leased_until = now() + interval '3 minutes', attempts = d.attempts + 1, updated_at = now()
  from candidate where d.id = candidate.id
  returning d.*;
end;
$$;

-- p_outcome: ready (with p_chunks [{heading, content}]), retry, or failed (with p_error_code).
create function public.finish_knowledge_document(
  p_document_id uuid, p_lease_token uuid, p_outcome text, p_chunks jsonb default null,
  p_page_count integer default null, p_error_code text default null
) returns boolean language plpgsql security invoker set search_path = '' as $$
declare
  doc public.knowledge_documents;
  chunk jsonb;
  v_ordinal integer := 0;
  total integer := 0;
begin
  perform public.require_service_role();
  if p_outcome is null or p_outcome not in ('ready', 'retry', 'failed')
    or (p_outcome = 'failed' and coalesce(p_error_code, '') not in ('unsupported_format', 'no_text',
      'too_large', 'too_many_chunks', 'unreadable', 'file_missing')) then
    raise exception 'Invalid document outcome' using errcode = '22023';
  end if;
  select * into doc from public.knowledge_documents where id = p_document_id for update;
  if not found or doc.state <> 'leased' or doc.lease_token is distinct from p_lease_token then
    return false;
  end if;
  if p_outcome = 'ready' then
    if jsonb_typeof(p_chunks) is distinct from 'array' or jsonb_array_length(p_chunks) not between 1 and 400 then
      raise exception 'Invalid document chunks' using errcode = '22023';
    end if;
    delete from public.knowledge_chunks where tenant_id = doc.tenant_id and document_id = doc.id;
    for chunk in select value from jsonb_array_elements(p_chunks) loop
      if jsonb_typeof(chunk) <> 'object' or jsonb_typeof(chunk->'content') is distinct from 'string'
        or length(btrim(chunk->>'content')) not between 1 and 4000
        or (chunk ? 'heading' and jsonb_typeof(chunk->'heading') not in ('string', 'null'))
        or length(coalesce(chunk->>'heading', '')) > 250 then
        raise exception 'Invalid document chunk' using errcode = '22023';
      end if;
      insert into public.knowledge_chunks(tenant_id, document_id, ordinal, heading, content, content_hash)
        values (doc.tenant_id, doc.id, v_ordinal, nullif(chunk->>'heading', ''), chunk->>'content',
          md5(coalesce(nullif(chunk->>'heading', ''), '') || E'\n' || (chunk->>'content')));
      v_ordinal := v_ordinal + 1;
      total := total + length(chunk->>'content');
    end loop;
    update public.knowledge_documents set state = 'ready', chunk_count = v_ordinal, char_count = total,
      page_count = p_page_count, error_code = null, lease_token = null, leased_until = null,
      processed_at = now(), updated_at = now()
      where id = doc.id;
    perform public.bump_bot_context_version(doc.tenant_id);
  elsif p_outcome = 'retry' and doc.attempts < 3 then
    update public.knowledge_documents set state = 'queued', lease_token = null, leased_until = null,
      available_at = now() + make_interval(mins => doc.attempts * 2), updated_at = now()
      where id = doc.id;
  else
    update public.knowledge_documents set state = 'failed',
      error_code = case when p_outcome = 'failed' then p_error_code else 'attempts_exhausted' end,
      lease_token = null, leased_until = null, processed_at = now(), updated_at = now()
      where id = doc.id;
  end if;
  return true;
end;
$$;

-- Passages without an embedding, oldest first. Each claim pushes the passage back
-- with exponential backoff until its embedding is saved. Search only uses embeddings
-- of the configured model; after changing OPENAI_EMBEDDING_MODEL, clear the old ones
-- (update public.knowledge_chunks set embedding = null, embedding_model = null).
create function public.claim_knowledge_embeddings(p_model text, p_limit integer default 64)
returns table(id uuid, tenant_id uuid, heading text, content text, content_hash text)
language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_service_role();
  if coalesce(p_model, '') !~ '^[a-zA-Z0-9_.:-]{1,100}$' then
    raise exception 'Invalid embedding model' using errcode = '22023';
  end if;
  return query
  with candidates as (
    select c.id from public.knowledge_chunks c
    left join public.knowledge_documents d on d.tenant_id = c.tenant_id and d.id = c.document_id
    where c.embedding is null and c.embedding_available_at <= now()
      and (c.document_id is null or d.state = 'ready')
    order by c.embedding_available_at, c.id
    limit least(greatest(coalesce(p_limit, 64), 1), 256)
    for update of c skip locked
  )
  update public.knowledge_chunks c set embedding_attempts = c.embedding_attempts + 1,
    embedding_available_at = now() + least(interval '6 hours', interval '1 minute' * power(2, least(c.embedding_attempts, 10)))
  from candidates where c.id = candidates.id
  returning c.id, c.tenant_id, c.heading, c.content, c.content_hash;
end;
$$;

-- p_items: [{id, content_hash, embedding: [1536 numbers]}] of one tenant. Passages
-- whose text changed since the claim keep waiting for a fresh embedding.
create function public.save_knowledge_embeddings(
  p_tenant_id uuid, p_model text, p_tokens integer, p_items jsonb
) returns integer language plpgsql security invoker set search_path = '' as $$
declare
  item jsonb;
  saved integer := 0;
  period date := date_trunc('month', now() at time zone 'UTC')::date;
begin
  perform public.require_service_role();
  if coalesce(p_model, '') !~ '^[a-zA-Z0-9_.:-]{1,100}$' or coalesce(p_tokens, -1) < 0
    or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) > 256 then
    raise exception 'Invalid embeddings' using errcode = '22023';
  end if;
  for item in select value from jsonb_array_elements(p_items) loop
    if coalesce(item->>'id', '') !~ '^[0-9a-f-]{36}$' or jsonb_typeof(item->'embedding') is distinct from 'array'
      or jsonb_array_length(item->'embedding') <> 1536 then
      raise exception 'Invalid embedding item' using errcode = '22023';
    end if;
    update public.knowledge_chunks set embedding = (item->>'embedding')::extensions.vector(1536),
      embedding_model = p_model, embedding_attempts = 0, embedding_available_at = now()
      where tenant_id = p_tenant_id and id = (item->>'id')::uuid and content_hash = item->>'content_hash';
    if found then saved := saved + 1; end if;
  end loop;
  if p_tokens > 0 and exists (select 1 from public.tenants where id = p_tenant_id) then
    insert into public.tenant_ai_usage(tenant_id, period_start, embedding_tokens) values (p_tenant_id, period, p_tokens)
      on conflict (tenant_id, period_start) do update
      set embedding_tokens = public.tenant_ai_usage.embedding_tokens + excluded.embedding_tokens;
  end if;
  return saved;
end;
$$;

-- A changed passage (new text, or a re-embed after a model change) is claimable again.
create function public.reset_knowledge_chunk_embedding()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.content_hash is distinct from old.content_hash then
    new.embedding := null;
    new.embedding_model := null;
    new.embedding_attempts := 0;
    new.embedding_available_at := now();
  end if;
  return new;
end;
$$;
create trigger knowledge_chunk_reset_embedding before update of content_hash on public.knowledge_chunks
  for each row execute function public.reset_knowledge_chunk_embedding();

-- Words of the customer's message (folded) as an OR query, without very short words
-- and common Turkish filler. Longer words also match by a shortened prefix, a rough
-- stand-in for Turkish suffixes (otoparkınız -> otopark:*, kahvaltıda -> kahval:*).
create function public.knowledge_search_query(p_text text)
returns tsquery language sql immutable set search_path = '' as $$
  select string_agg(case when length(word) >= 6
      then quote_literal(left(word, greatest(5, length(word) - 4))) || ':*'
      else quote_literal(word) end, ' | ')::tsquery
  from unnest(tsvector_to_array(to_tsvector('simple',
    public.knowledge_fold(left(coalesce(p_text, ''), 4096))))) as word
  where length(word) >= 3 and word <> all (array['var', 'yok', 'icin', 'ile', 'bir', 'gibi', 'ama',
    'veya', 'daha', 'cok', 'acaba', 'merhaba', 'selam', 'lutfen', 'nedir', 'olur', 'olan',
    'misiniz', 'musunuz', 'the', 'and', 'for']);
$$;

-- Hybrid knowledge for a leased bot job: reciprocal rank fusion of full-text matches
-- (entries and ready document passages) and, when a query embedding is supplied,
-- the nearest passages by cosine distance. Returns at most five sources. The
-- embedding's token use is recorded for the tenant.
create function public.bot_knowledge_search(
  p_job_id uuid, p_lease_token uuid, p_query_embedding extensions.vector default null,
  p_embedding_model text default null, p_embedding_tokens integer default 0
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  job public.bot_reply_jobs;
  input_body text;
  search_query tsquery;
  result jsonb;
  period date := date_trunc('month', now() at time zone 'UTC')::date;
begin
  perform public.require_service_role();
  select * into job from public.bot_reply_jobs where id = p_job_id and state = 'leased'
    and lease_token = p_lease_token and leased_until > now();
  if not found then return null; end if;
  select body into input_body from public.messages where tenant_id = job.tenant_id and id = job.input_message_id;
  if p_query_embedding is not null and (extensions.vector_dims(p_query_embedding) <> 1536
      or coalesce(p_embedding_model, '') !~ '^[a-zA-Z0-9_.:-]{1,100}$') then
    raise exception 'Invalid query embedding' using errcode = '22023';
  end if;
  if coalesce(p_embedding_tokens, 0) > 0 then
    insert into public.tenant_ai_usage(tenant_id, period_start, embedding_tokens)
      values (job.tenant_id, period, least(p_embedding_tokens, 100000))
      on conflict (tenant_id, period_start) do update
      set embedding_tokens = public.tenant_ai_usage.embedding_tokens + excluded.embedding_tokens;
  end if;
  search_query := public.knowledge_search_query(input_body);

  with lexical as (
    select kind, source_id, row_number() over (order by score desc, source_id) as rank from (
      select 'entry' as kind, kb.id as source_id,
        ts_rank(to_tsvector('simple', public.knowledge_fold(left(kb.title, 250) || ' ' || left(kb.content, 50000))), search_query, 1) as score
      from public.knowledge_base kb
      where search_query is not null and kb.tenant_id = job.tenant_id
        and to_tsvector('simple', public.knowledge_fold(left(kb.title, 250) || ' ' || left(kb.content, 50000))) @@ search_query
      union all
      select 'chunk', c.id,
        ts_rank(to_tsvector('simple', public.knowledge_fold(coalesce(c.heading, '') || ' ' || c.content)), search_query, 1)
      from public.knowledge_chunks c
      join public.knowledge_documents d on d.tenant_id = c.tenant_id and d.id = c.document_id and d.state = 'ready'
      where search_query is not null and c.tenant_id = job.tenant_id and c.document_id is not null
        and to_tsvector('simple', public.knowledge_fold(coalesce(c.heading, '') || ' ' || c.content)) @@ search_query
    ) matches
    order by score desc, source_id limit 20
  ), semantic as (
    select case when c.entry_id is null then 'chunk' else 'entry' end as kind,
      coalesce(c.entry_id, c.id) as source_id,
      row_number() over (order by c.embedding operator(extensions.<=>) p_query_embedding, c.id) as rank
    from public.knowledge_chunks c
    left join public.knowledge_documents d on d.tenant_id = c.tenant_id and d.id = c.document_id
    where p_query_embedding is not null and c.tenant_id = job.tenant_id
      and c.embedding is not null and c.embedding_model = p_embedding_model
      and (c.document_id is null or d.state = 'ready')
      and c.embedding operator(extensions.<=>) p_query_embedding < 0.8
    order by c.embedding operator(extensions.<=>) p_query_embedding, c.id limit 20
  ), fused as (
    select kind, source_id, sum(1.0 / (60 + rank)) as score
    from (select * from lexical union all select * from semantic) ranked
    group by kind, source_id
    order by score desc, source_id limit 5
  )
  select coalesce(jsonb_agg(item order by score desc), '[]'::jsonb) into result from (
    select f.score, jsonb_build_object('id', kb.id, 'title', left(kb.title, 250), 'content',
      case when length(kb.content) <= 4000 or search_query is null then left(kb.content, 4000)
        else left(ts_headline('simple', left(kb.content, 50000), search_query,
          'MaxWords=250, MinWords=50, MaxFragments=3'), 4000) end) as item
    from fused f join public.knowledge_base kb on kb.tenant_id = job.tenant_id and kb.id = f.source_id
    where f.kind = 'entry'
    union all
    select f.score, jsonb_build_object('id', c.id,
      'title', left(d.title || coalesce(' – ' || c.heading, ''), 250), 'content', c.content)
    from fused f join public.knowledge_chunks c on c.tenant_id = job.tenant_id and c.id = f.source_id
    join public.knowledge_documents d on d.tenant_id = c.tenant_id and d.id = c.document_id
    where f.kind = 'chunk'
  ) items;

  -- Nothing matched: the latest entries, else the opening passages of recent documents.
  if jsonb_array_length(result) = 0 then
    select coalesce(jsonb_agg(item), '[]'::jsonb) into result from (
      select jsonb_build_object('id', id, 'title', left(title, 250), 'content', left(content, 4000)) as item
      from public.knowledge_base where tenant_id = job.tenant_id order by updated_at desc, id limit 5
    ) recent;
  end if;
  if jsonb_array_length(result) = 0 then
    select coalesce(jsonb_agg(item), '[]'::jsonb) into result from (
      select jsonb_build_object('id', c.id, 'title', left(d.title || coalesce(' – ' || c.heading, ''), 250),
        'content', c.content) as item
      from public.knowledge_documents d
      join public.knowledge_chunks c on c.tenant_id = d.tenant_id and c.document_id = d.id and c.ordinal = 0
      where d.tenant_id = job.tenant_id and d.state = 'ready'
      order by d.processed_at desc, d.id limit 3
    ) recent;
  end if;
  return result;
end;
$$;

revoke all on function public.bump_bot_context_version(uuid) from public, anon, authenticated;
grant execute on function public.knowledge_fold(text) to authenticated, service_role;
revoke all on function public.sync_knowledge_entry_chunk() from public, anon, authenticated;
revoke all on function public.reset_knowledge_chunk_embedding() from public, anon, authenticated;
revoke all on function public.register_knowledge_document(uuid, uuid, text, text) from public, anon;
revoke all on function public.delete_knowledge_document(uuid, uuid) from public, anon;
revoke all on function public.retry_knowledge_document(uuid, uuid) from public, anon;
grant execute on function public.register_knowledge_document(uuid, uuid, text, text) to authenticated;
grant execute on function public.delete_knowledge_document(uuid, uuid) to authenticated;
grant execute on function public.retry_knowledge_document(uuid, uuid) to authenticated;
revoke all on function public.claim_knowledge_document() from public, anon, authenticated;
revoke all on function public.finish_knowledge_document(uuid, uuid, text, jsonb, integer, text) from public, anon, authenticated;
revoke all on function public.claim_knowledge_embeddings(text, integer) from public, anon, authenticated;
revoke all on function public.save_knowledge_embeddings(uuid, text, integer, jsonb) from public, anon, authenticated;
revoke all on function public.bot_knowledge_search(uuid, uuid, extensions.vector, text, integer) from public, anon, authenticated;
grant execute on function public.claim_knowledge_document() to service_role;
grant execute on function public.finish_knowledge_document(uuid, uuid, text, jsonb, integer, text) to service_role;
grant execute on function public.claim_knowledge_embeddings(text, integer) to service_role;
grant execute on function public.save_knowledge_embeddings(uuid, text, integer, jsonb) to service_role;
grant execute on function public.bot_knowledge_search(uuid, uuid, extensions.vector, text, integer) to service_role;

-- Bot replies may cite document passages as well as manual entries. This is the
-- previous complete_bot_reply with only the knowledge source check widened.
CREATE OR REPLACE FUNCTION public.complete_bot_reply(p_job_id uuid, p_lease_token uuid, p_decision jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  job public.bot_reply_jobs;
  conversation public.conversations;
  settings public.bot_settings;
  version bigint;
  decision jsonb := p_decision;
  message_text text;
  source_kind text;
  reason text;
  source_id text;
  buttons jsonb;
  button jsonb;
begin
  perform public.require_service_role();
  if decision is null or jsonb_typeof(decision) <> 'object'
    or coalesce(decision->>'action', '') not in ('reply', 'handoff')
    or jsonb_typeof(decision->'text') is distinct from 'string'
    or coalesce(decision->>'reason', '') !~ '^[a-z_]{1,100}$'
    or jsonb_typeof(decision->'knowledge_ids') is distinct from 'array'
    or jsonb_array_length(decision->'knowledge_ids') > 5 then
    raise exception 'Invalid bot decision' using errcode = '22023';
  end if;
  select * into job from public.bot_reply_jobs where id = p_job_id;
  if not found then return false; end if;
  select * into conversation from public.conversations where id = job.conversation_id and tenant_id = job.tenant_id for update;
  select * into job from public.bot_reply_jobs where id = p_job_id for update;
  if not found or job.lease_token is distinct from p_lease_token then return false; end if;
  if job.state in ('completed', 'handoff') then return true; end if;
  if job.state <> 'leased' or job.prepared_at is null then return false; end if;
  select * into settings from public.bot_settings where tenant_id = job.tenant_id and is_active;
  if not found or conversation.status <> 'open' or conversation.last_customer_message_id is distinct from job.input_message_id
    or conversation.automation_revision is distinct from job.automation_revision then
    update public.bot_reply_jobs set state = 'cancelled', error_code = 'conversation_changed',
      leased_until = null, updated_at = now() where id = job.id;
    return false;
  end if;
  select revision into version from public.bot_context_versions where tenant_id = job.tenant_id for share;
  if version is distinct from job.context_revision then
    decision := jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'bot_configuration_changed', 'knowledge_ids', '[]'::jsonb);
  elsif job.expires_at <= clock_timestamp() then
    decision := jsonb_build_object('action', 'handoff', 'text', '', 'reason', 'customer_service_window_closed', 'knowledge_ids', '[]'::jsonb);
  end if;
  if job.generation_started_at is not null and not exists (
    select 1 from public.ai_usage_reservations where job_id = job.id and lease_token = p_lease_token
      and (status = 'settled' or (status = 'unknown' and decision->>'action' = 'handoff'))
  ) then return false; end if;
  reason := decision->>'reason';
  if decision->>'action' = 'reply' then
    if job.generation_started_at is null or length(btrim(decision->>'text')) not between 1 and 4096
      or reason not in ('knowledge_answer', 'greeting_or_clarification', 'tool_answer')
      or (reason = 'knowledge_answer' and jsonb_array_length(decision->'knowledge_ids') = 0) then
      raise exception 'Invalid bot reply' using errcode = '22023';
    end if;
    for source_id in select jsonb_array_elements_text(decision->'knowledge_ids') loop
      -- Sources are manual entries or passages of the business's documents.
      if source_id !~ '^[0-9a-f-]{36}$' or not (exists (
        select 1 from public.knowledge_base where tenant_id = job.tenant_id and id::text = source_id
      ) or exists (
        select 1 from public.knowledge_chunks where tenant_id = job.tenant_id and document_id is not null
          and id::text = source_id
      )) then raise exception 'Invalid knowledge source' using errcode = '22023'; end if;
    end loop;
    message_text := decision->>'text';
    source_kind := 'bot';
    -- Optional reply buttons (added by the worker for a fresh hold, never by the model):
    -- 1-3 of {id: booking:confirm|cancel:<booking uuid of this conversation>, title}.
    if decision ? 'buttons' then
      buttons := decision->'buttons';
      if jsonb_typeof(buttons) <> 'array' or jsonb_array_length(buttons) not between 1 and 3
        or length(message_text) > 1024 then
        raise exception 'Invalid reply buttons' using errcode = '22023';
      end if;
      for button in select value from jsonb_array_elements(buttons) loop
        if jsonb_typeof(button) <> 'object' or length(coalesce(button->>'title', '')) not between 1 and 20
          or coalesce(button->>'id', '') !~ '^booking:(confirm|cancel):[0-9a-f-]{36}$'
          or not exists (select 1 from public.bookings b where b.tenant_id = job.tenant_id
            and b.conversation_id = conversation.id and b.id::text = split_part(button->>'id', ':', 3)) then
          raise exception 'Invalid reply buttons' using errcode = '22023';
        end if;
      end loop;
    end if;
  else
    if decision->>'text' <> '' or jsonb_array_length(decision->'knowledge_ids') <> 0 then
      raise exception 'Invalid handoff decision' using errcode = '22023';
    end if;
    insert into public.handoff_requests(tenant_id, conversation_id, bot_job_id, note, status)
      values(job.tenant_id, conversation.id, job.id, 'Bot yönlendirmesi (' || reason || ')', 'open');
    update public.conversations set status = 'handoff', updated_at = clock_timestamp()
      where id = conversation.id returning * into conversation;
    message_text := case when lower(settings.language) in ('turkce', 'türkçe', 'tr', 'tr-tr', 'tr_tr')
      then 'Konuşmanızı bir müşteri temsilcisine yönlendirdim.'
      else 'I have passed this conversation to our support team.' end;
    source_kind := 'bot_handoff';
    insert into public.tenant_audit_events(tenant_id, action, resource_id, details)
      values(job.tenant_id, 'conversation.bot_handoff', conversation.id,
        jsonb_build_object('job_id', job.id, 'reason', reason));
  end if;
  -- A handoff remains visible to staff after window expiry, with no out-of-window notice.
  if job.expires_at > clock_timestamp() and conversation.connection_id is not null then
    insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer,
        message_type, provider_content)
      values(job.id, job.tenant_id, conversation.id, conversation.connection_id, settings.name, message_text, false,
        case when buttons is null then 'text' else 'interactive' end,
        case when buttons is null then null else jsonb_build_object('interactive', jsonb_build_object('buttons', buttons)) end);
    insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, source, bot_job_id, expires_at)
      values(job.id, job.tenant_id, conversation.id, conversation.connection_id, conversation.customer_phone,
        source_kind, job.id, job.expires_at);
    update public.conversations set last_message = message_text, last_message_at = clock_timestamp(), updated_at = clock_timestamp()
      where id = conversation.id;
  end if;
  update public.bot_reply_jobs set state = case when source_kind = 'bot' then 'completed' else 'handoff' end,
    output = decision, automation_revision = conversation.automation_revision, context_revision = version,
    leased_until = null, error_code = case when source_kind = 'bot_handoff' then reason else null end,
    updated_at = now() where id = job.id;
  return true;
end;
$function$;
