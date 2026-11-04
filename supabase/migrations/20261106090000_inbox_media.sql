-- Inbound WhatsApp media. Customer images, voice notes, videos, documents and
-- stickers are queued on insert, downloaded by `media-worker` with the tenant's own
-- token, and stored privately under {tenant}/{conversation}/{message}. Agents with the
-- inbox permission read them through Storage RLS; clients never write media rows.

insert into storage.buckets(id, name, public)
  values ('inbox-media', 'inbox-media', false)
  on conflict (id) do nothing;

create table if not exists public.message_media (
  message_id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  conversation_id uuid not null,
  connection_id uuid not null,
  kind text not null check (kind in ('image', 'video', 'audio', 'document', 'sticker')),
  provider_media_id text not null check (provider_media_id ~ '^[0-9]{1,40}$'),
  mime_type text check (mime_type is null or length(mime_type) <= 100),
  file_name text check (file_name is null or length(file_name) <= 255),
  caption text check (caption is null or length(caption) <= 4096),
  state text not null default 'queued'
    check (state in ('queued', 'leased', 'stored', 'failed', 'too_large')),
  attempts integer not null default 0 check (attempts between 0 and 5),
  available_at timestamptz not null default now(),
  lease_token uuid,
  leased_until timestamptz,
  storage_path text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  error_code text check (error_code is null or length(error_code) <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, message_id) references public.messages(tenant_id, id) on delete cascade,
  foreign key (tenant_id, conversation_id) references public.conversations(tenant_id, id) on delete cascade,
  foreign key (tenant_id, connection_id) references public.whatsapp_connections(tenant_id, id),
  check (state <> 'leased' or (lease_token is not null and leased_until is not null)),
  check (state <> 'stored' or storage_path is not null)
);
create index if not exists message_media_claimable on public.message_media(available_at)
  where state in ('queued', 'leased');
create index if not exists message_media_conversation on public.message_media(tenant_id, conversation_id);

alter table public.message_media enable row level security;
drop policy if exists message_media_read on public.message_media;
create policy message_media_read on public.message_media for select to authenticated
  using (public.user_has_permission(tenant_id, 'inbox'));
revoke insert, update, delete on public.message_media from anon, authenticated;

-- Realtime lets an open chat refresh when a download finishes.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_media') then
    alter publication supabase_realtime add table public.message_media;
  end if;
end;
$$;

drop policy if exists inbox_media_read on storage.objects;
create policy inbox_media_read on storage.objects for select to authenticated
  using (bucket_id = 'inbox-media'
    and (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and public.user_has_permission(((storage.foldername(name))[1])::uuid, 'inbox'));

create or replace function public.queue_inbound_media()
returns trigger language plpgsql security definer set search_path = '' as $$
declare part jsonb;
begin
  if not new.is_from_customer or new.connection_id is null
    or new.message_type not in ('image', 'video', 'audio', 'document', 'sticker') then
    return new;
  end if;
  part := new.provider_content -> new.message_type;
  if jsonb_typeof(part) <> 'object' or coalesce(part->>'id', '') !~ '^[0-9]{1,40}$' then
    return new;
  end if;
  insert into public.message_media(message_id, tenant_id, conversation_id, connection_id, kind,
      provider_media_id, mime_type, file_name, caption)
    values (new.id, new.tenant_id, new.conversation_id, new.connection_id, new.message_type,
      part->>'id', left(part->>'mime_type', 100), left(part->>'filename', 255), left(part->>'caption', 4096))
    on conflict (message_id) do nothing;
  return new;
end;
$$;
drop trigger if exists messages_queue_inbound_media on public.messages;
create trigger messages_queue_inbound_media after insert on public.messages
  for each row execute function public.queue_inbound_media();

create or replace function public.require_media_worker()
returns void language plpgsql stable set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Media worker required' using errcode = '42501';
  end if;
end;
$$;

-- Fenced leases; an expired lease becomes claimable again.
create or replace function public.claim_message_media(p_limit integer default 5)
returns setof public.message_media language plpgsql security invoker set search_path = '' as $$
begin
  perform public.require_media_worker();
  -- A crashed worker on the final attempt must not leave the row leased forever.
  update public.message_media set state = 'failed', error_code = 'attempts_exhausted',
    lease_token = null, leased_until = null, updated_at = now()
    where state = 'leased' and leased_until <= now() and attempts >= 5;
  return query
  with candidates as (
    select m.message_id from public.message_media m
    where (m.state = 'queued' and m.available_at <= now())
       or (m.state = 'leased' and m.leased_until <= now())
    order by m.available_at, m.message_id
    limit least(greatest(coalesce(p_limit, 5), 1), 20)
    for update skip locked
  )
  update public.message_media m set state = 'leased', lease_token = gen_random_uuid(),
    leased_until = now() + interval '2 minutes', attempts = m.attempts + 1, updated_at = now()
  from candidates where m.message_id = candidates.message_id and m.attempts < 5
  returning m.*;
end;
$$;

-- p_outcome: stored | retry | failed | too_large. Retries back off and stop after 5 attempts.
create or replace function public.finish_message_media(
  p_message_id uuid, p_lease_token uuid, p_outcome text, p_storage_path text default null,
  p_size_bytes bigint default null, p_mime_type text default null, p_error_code text default null
) returns boolean language plpgsql security invoker set search_path = '' as $$
declare job public.message_media;
begin
  perform public.require_media_worker();
  if p_outcome is null or p_outcome not in ('stored', 'retry', 'failed', 'too_large') then
    raise exception 'Invalid media outcome' using errcode = '22023';
  end if;
  select * into job from public.message_media where message_id = p_message_id for update;
  if not found or job.state <> 'leased' or job.lease_token is distinct from p_lease_token then
    return false;
  end if;
  if p_outcome = 'stored' then
    if p_storage_path is null or p_storage_path not like job.tenant_id::text || '/' || job.conversation_id::text || '/%' then
      raise exception 'Storage path must be tenant scoped' using errcode = '22023';
    end if;
    update public.message_media set state = 'stored', storage_path = p_storage_path, size_bytes = p_size_bytes,
      mime_type = coalesce(left(p_mime_type, 100), mime_type), error_code = null,
      lease_token = null, leased_until = null, updated_at = now()
      where message_id = p_message_id;
  elsif p_outcome = 'retry' and job.attempts < 5 then
    update public.message_media set state = 'queued', error_code = left(p_error_code, 100),
      available_at = now() + make_interval(secs => 30 * power(2, job.attempts)),
      lease_token = null, leased_until = null, updated_at = now()
      where message_id = p_message_id;
  else
    update public.message_media set state = case when p_outcome = 'too_large' then 'too_large' else 'failed' end,
      error_code = left(coalesce(p_error_code, p_outcome), 100), lease_token = null, leased_until = null,
      updated_at = now() where message_id = p_message_id;
  end if;
  return true;
end;
$$;

revoke all on function public.queue_inbound_media() from public, anon, authenticated;
revoke all on function public.claim_message_media(integer) from public, anon, authenticated;
revoke all on function public.finish_message_media(uuid, uuid, text, text, bigint, text, text) from public, anon, authenticated;
grant execute on function public.claim_message_media(integer) to service_role;
grant execute on function public.finish_message_media(uuid, uuid, text, text, bigint, text, text) to service_role;
grant select, insert, update on public.message_media to service_role;
