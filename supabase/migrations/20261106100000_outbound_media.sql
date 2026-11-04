-- Agents send images and documents. The app uploads the file to
-- inbox-media/{tenant}/{conversation}/outbound/{message}.{ext}; enqueue_inbox_media_message
-- applies every enqueue_inbox_message rule (permission, ownership, 24-hour window,
-- connection) and records the media; inbox-worker uploads it to Meta just before the
-- single fenced send.

alter table public.message_media
  add column if not exists direction text not null default 'inbound';
alter table public.message_media alter column provider_media_id drop not null;
alter table public.message_media add constraint message_media_direction_check
  check (direction in ('inbound', 'outbound'));
alter table public.message_media add constraint message_media_inbound_id
  check (direction = 'outbound' or provider_media_id is not null);

-- Uploads only into the caller's own tenant/conversation outbound folder; no
-- overwrite or delete from clients.
drop policy if exists inbox_media_outbound_upload on storage.objects;
create policy inbox_media_outbound_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'inbox-media'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/outbound/[0-9a-f-]{36}\.(jpg|png|pdf|docx|xlsx|doc|xls|txt)$'
    and public.user_has_permission(((storage.foldername(name))[1])::uuid, 'inbox')
    and exists (select 1 from public.conversations c
      where c.tenant_id = ((storage.foldername(name))[1])::uuid
        and c.id = ((storage.foldername(name))[2])::uuid));

create or replace function public.outbound_media_limit(p_kind text, p_mime_type text)
returns bigint language sql immutable set search_path = '' as $$
  select case
    when p_kind = 'image' and p_mime_type in ('image/jpeg', 'image/png') then 5 * 1024 * 1024
    when p_kind = 'document' and p_mime_type in (
      'application/pdf', 'text/plain', 'application/msword', 'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') then 16 * 1024 * 1024
  end;
$$;

create or replace function public.enqueue_inbox_media_message(
  p_tenant_id uuid, p_conversation_id uuid, p_message_id uuid, p_storage_path text,
  p_kind text, p_mime_type text, p_file_name text default null, p_caption text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  caption text := nullif(btrim(coalesce(p_caption, '')), '');
  file_name text := nullif(left(btrim(coalesce(p_file_name, '')), 255), '');
  object_size bigint;
  limit_bytes bigint := public.outbound_media_limit(p_kind, p_mime_type);
  body text;
  result jsonb;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  if p_message_id is null or limit_bytes is null or (caption is not null and length(caption) > 1024)
    or p_storage_path is null
    or p_storage_path not like p_tenant_id::text || '/' || p_conversation_id::text || '/outbound/' || p_message_id::text || '.%' then
    raise exception 'Unsupported media' using errcode = 'P0009';
  end if;
  select (o.metadata->>'size')::bigint into object_size from storage.objects o
    where o.bucket_id = 'inbox-media' and o.name = p_storage_path;
  if object_size is null or object_size <= 0 or object_size > limit_bytes then
    raise exception 'Uploaded media missing or too large' using errcode = 'P0009';
  end if;
  body := coalesce(caption, case when p_kind = 'image' then '[Fotoğraf]'
    else '[Belge' || coalesce(': ' || file_name, '') || ']' end);
  result := public.enqueue_inbox_message(p_tenant_id, p_conversation_id, p_message_id, body);
  update public.messages set message_type = p_kind where id = p_message_id and tenant_id = p_tenant_id;
  insert into public.message_media(message_id, tenant_id, conversation_id, connection_id, kind, direction,
      mime_type, file_name, caption, state, storage_path, size_bytes)
    select m.id, m.tenant_id, m.conversation_id, m.connection_id, p_kind, 'outbound',
      p_mime_type, file_name, caption, 'stored', p_storage_path, object_size
    from public.messages m where m.id = p_message_id and m.tenant_id = p_tenant_id
    on conflict (message_id) do nothing;
  return result;
end;
$$;
revoke all on function public.enqueue_inbox_media_message(uuid, uuid, uuid, text, text, text, text, text) from public, anon;
grant execute on function public.enqueue_inbox_media_message(uuid, uuid, uuid, text, text, text, text, text) to authenticated;
