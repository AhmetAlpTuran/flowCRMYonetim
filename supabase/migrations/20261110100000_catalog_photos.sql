-- Catalog photos and the bot's listing photos (roadmap Phase 2c, auto dealer "send_listing").
--
-- Items keep up to ten photos in the private catalog-photos bucket at
-- {tenant}/{resource}/{uuid}.jpg|png (resources.photos holds the paths; the app uploads
-- and orders them). The bot can send up to three photos with a reply: the worker attaches
-- them after a send_photos tool call and complete_bot_reply accepts only photos of the
-- business's own items. Each photo becomes an outbound image message with its own
-- dispatch, sent after the reply text in order; inbox-worker reads it from the bucket
-- recorded in message_media.storage_bucket.

insert into storage.buckets(id, name, public)
  values ('catalog-photos', 'catalog-photos', false)
  on conflict (id) do nothing;

create policy catalog_photos_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'catalog-photos'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png)$'
    and public.user_has_permission(((storage.foldername(name))[1])::uuid, 'catalog')
    -- objects.name: inside the subquery a bare `name` would be resources.name.
    and exists (select 1 from public.resources r
      where r.tenant_id = ((storage.foldername(objects.name))[1])::uuid
        and r.id = ((storage.foldername(objects.name))[2])::uuid));
create policy catalog_photos_read on storage.objects for select to authenticated
  using (
    bucket_id = 'catalog-photos'
    and (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and public.user_has_permission(((storage.foldername(name))[1])::uuid, 'catalog'));
create policy catalog_photos_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'catalog-photos'
    and (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and public.user_has_permission(((storage.foldername(name))[1])::uuid, 'catalog'));

-- An item's photo list may only name files in its own folder, once each.
create function public.check_resource_photos()
returns trigger language plpgsql set search_path = '' as $$
declare path text;
begin
  if cardinality(new.photos) <> (select count(distinct p) from unnest(new.photos) p) then
    raise exception 'Duplicate photo' using errcode = '22023';
  end if;
  foreach path in array new.photos loop
    if path !~ ('^' || new.tenant_id::text || '/' || new.id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png)$') then
      raise exception 'Photo outside this item' using errcode = '22023';
    end if;
  end loop;
  return new;
end;
$$;
create trigger resources_check_photos before insert or update of photos on public.resources
  for each row execute function public.check_resource_photos();

alter table public.message_media
  add column if not exists storage_bucket text not null default 'inbox-media';
alter table public.message_media add constraint message_media_storage_bucket_check
  check (storage_bucket in ('inbox-media', 'catalog-photos'));

-- A bot job now owns its reply dispatch plus one dispatch per photo. Keep the guarantee of
-- a single reply dispatch per job (its ID is the job's); photo dispatches have their own
-- deterministic IDs. No data changes.
drop index if exists public.inbox_dispatch_bot_job;
create unique index inbox_dispatch_bot_job_reply on public.inbox_dispatches(bot_job_id)
  where bot_job_id is not null and id = bot_job_id;

-- complete_bot_reply: the previous definition with reply photos added.
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
  profile_id uuid;
  photos jsonb;
  photo jsonb;
  photo_index integer := 0;
  photo_id uuid;
  photo_size bigint;
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
  select * into settings from public.effective_bot_settings(job.tenant_id, conversation.connection_id) where is_active;
  select c.bot_profile_id into profile_id from public.whatsapp_connections c
    where c.tenant_id = job.tenant_id and c.id = conversation.connection_id;
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
    -- Optional photos (added by the worker after send_photos, never by the model):
    -- 1-3 of {path: a photo of one of this business's items, caption}.
    if decision ? 'photos' then
      photos := decision->'photos';
      if jsonb_typeof(photos) <> 'array' or jsonb_array_length(photos) not between 1 and 3 then
        raise exception 'Invalid reply photos' using errcode = '22023';
      end if;
      for photo in select value from jsonb_array_elements(photos) loop
        if jsonb_typeof(photo) <> 'object' or jsonb_typeof(photo->'path') is distinct from 'string'
          or split_part(photo->>'path', '/', 1) <> job.tenant_id::text
          or length(coalesce(photo->>'caption', '')) > 1024
          or not exists (select 1 from public.resources r where r.tenant_id = job.tenant_id
            and (photo->>'path') = any(r.photos)) then
          raise exception 'Invalid reply photos' using errcode = '22023';
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
    -- Photos follow the text, each as its own image message and dispatch (sent in order).
    if photos is not null then
      for photo in select value from jsonb_array_elements(photos) loop
        photo_index := photo_index + 1;
        photo_id := md5(job.id::text || ':photo:' || photo_index)::uuid;
        select (o.metadata->>'size')::bigint into photo_size from storage.objects o
          where o.bucket_id = 'catalog-photos' and o.name = photo->>'path';
        insert into public.messages(id, tenant_id, conversation_id, connection_id, sender, body, is_from_customer, message_type)
          values (photo_id, job.tenant_id, conversation.id, conversation.connection_id, settings.name,
            coalesce(nullif(btrim(photo->>'caption'), ''), '[image]'), false, 'image');
        insert into public.message_media(message_id, tenant_id, conversation_id, connection_id, kind, direction,
            mime_type, file_name, caption, state, storage_path, size_bytes, storage_bucket)
          values (photo_id, job.tenant_id, conversation.id, conversation.connection_id, 'image', 'outbound',
            case when photo->>'path' like '%.png' then 'image/png' else 'image/jpeg' end,
            split_part(photo->>'path', '/', 3), nullif(btrim(photo->>'caption'), ''), 'stored',
            photo->>'path', photo_size, 'catalog-photos');
        insert into public.inbox_dispatches(id, tenant_id, conversation_id, connection_id, recipient_phone, source, bot_job_id, expires_at)
          values (photo_id, job.tenant_id, conversation.id, conversation.connection_id, conversation.customer_phone,
            'bot', job.id, job.expires_at);
      end loop;
    end if;
    update public.conversations set last_message = message_text, last_message_at = clock_timestamp(), updated_at = clock_timestamp()
      where id = conversation.id;
  end if;
  update public.bot_reply_jobs set state = case when source_kind = 'bot' then 'completed' else 'handoff' end,
    output = decision, automation_revision = conversation.automation_revision, context_revision = version,
    bot_profile_id = profile_id,
    leased_until = null, error_code = case when source_kind = 'bot_handoff' then reason else null end,
    updated_at = now() where id = job.id;
  return true;
end;
$function$;
