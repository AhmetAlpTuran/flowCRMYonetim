-- Contacts and marketing consent. `contacts` is the CRM list (inbox permission);
-- `consented_contacts` is the campaign audience (campaigns permission). Consent now
-- records its source, basis and actor; opt-outs are kept as evidence and excluded from
-- every audience and from already-queued dispatches. Clients lose direct consent writes.

alter table public.consented_contacts
  add column if not exists consent_source text not null default 'legacy',
  add column if not exists consent_note text,
  add column if not exists consented_by uuid references auth.users(id) on delete set null,
  add column if not exists opted_out_at timestamptz,
  add column if not exists opt_out_source text;
alter table public.consented_contacts alter column consent_source set default 'manual';
alter table public.consented_contacts add constraint consented_contacts_source_check
  check (consent_source in ('legacy', 'manual', 'import', 'whatsapp', 'form')) not valid;
alter table public.consented_contacts add constraint consented_contacts_note_bounds
  check (consent_note is null or length(consent_note) <= 500) not valid;
alter table public.consented_contacts add constraint consented_contacts_opt_out_source_check
  check (opt_out_source is null or opt_out_source in ('manual', 'import', 'whatsapp_keyword')) not valid;
create index if not exists consented_contacts_normalized_phone
  on public.consented_contacts(tenant_id, public.normalize_campaign_phone(phone));

revoke insert, update, delete on public.consented_contacts from anon, authenticated;

-- Valid E.164 digits without '+', the same form WhatsApp uses as wa_id.
create or replace function public.contact_phone(p_phone text)
returns text language sql immutable set search_path = '' as $$
  select case when public.normalize_campaign_phone(p_phone) ~ '^[1-9][0-9]{7,14}$'
    then public.normalize_campaign_phone(p_phone) end;
$$;

create or replace function public.clean_contact_tags(p_tags text[])
returns text[] language sql immutable set search_path = '' as $$
  select coalesce(array_agg(distinct t order by t), array[]::text[]) from (
    select left(btrim(tag), 50) as t from unnest(coalesce(p_tags, array[]::text[])) tag
  ) cleaned where t <> '';
$$;

-- CRM edits (name, email, tags) flow into the campaign audience so tag segments
-- keep working; consent fields are untouched.
create or replace function public.sync_contact_to_audience()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.consented_contacts c
    set full_name = coalesce(nullif(new.full_name, ''), c.full_name),
        email = coalesce(new.email, c.email), tags = new.tags
    where c.tenant_id = new.tenant_id
      and public.normalize_campaign_phone(c.phone) = public.normalize_campaign_phone(new.phone);
  return new;
end;
$$;
drop trigger if exists contacts_sync_audience on public.contacts;
create trigger contacts_sync_audience after insert or update of full_name, email, tags on public.contacts
  for each row execute function public.sync_contact_to_audience();

-- Creates or updates the CRM contact for a phone number (deduplicated by number).
create or replace function public.upsert_contact(
  p_tenant_id uuid, p_full_name text, p_phone text, p_email text default null, p_tags text[] default null
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_phone text := public.contact_phone(p_phone); v_name text := left(btrim(coalesce(p_full_name, '')), 120);
  v_mail text := nullif(lower(btrim(coalesce(p_email, ''))), ''); contact_id uuid;
begin
  if not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  if v_phone is null then raise exception 'Valid phone number required' using errcode = '22023'; end if;
  if v_mail is not null and (length(v_mail) > 320 or v_mail !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
    raise exception 'Invalid email' using errcode = '22023';
  end if;
  select c.id into contact_id from public.contacts c
    where c.tenant_id = p_tenant_id and public.normalize_campaign_phone(c.phone) = v_phone
    order by c.created_at limit 1 for update;
  if contact_id is null then
    insert into public.contacts(tenant_id, full_name, phone, email, tags)
      values (p_tenant_id, coalesce(nullif(v_name, ''), v_phone), v_phone, v_mail, public.clean_contact_tags(p_tags))
      returning id into contact_id;
  else
    update public.contacts set full_name = coalesce(nullif(v_name, ''), full_name),
      email = coalesce(v_mail, email),
      tags = case when p_tags is null then tags else public.clean_contact_tags(p_tags) end
      where id = contact_id;
  end if;
  return contact_id;
end;
$$;
revoke all on function public.upsert_contact(uuid, text, text, text, text[]) from public, anon;
grant execute on function public.upsert_contact(uuid, text, text, text, text[]) to authenticated;

-- Grants (with a recorded basis) or revokes marketing consent for a number.
-- Revocation keeps the row as evidence; it can only be re-granted explicitly here.
create or replace function public.set_marketing_consent(
  p_tenant_id uuid, p_phone text, p_consent boolean, p_note text default null, p_source text default 'manual'
) returns boolean language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); v_phone text := public.contact_phone(p_phone);
  note text := nullif(btrim(coalesce(p_note, '')), ''); crm public.contacts; row_id uuid;
begin
  if uid is null or not coalesce(public.user_has_permission(p_tenant_id, 'campaigns'), false) then
    raise exception 'Campaign permission required' using errcode = '42501';
  end if;
  if v_phone is null or p_consent is null then raise exception 'Valid phone and decision required' using errcode = '22023'; end if;
  if p_source is null or p_source not in ('manual', 'form', 'whatsapp') then
    raise exception 'Unsupported consent source' using errcode = '22023';
  end if;
  if p_consent and (note is null or length(note) < 3 or length(note) > 500) then
    raise exception 'Describe how consent was obtained' using errcode = '22023';
  end if;
  select * into crm from public.contacts k where k.tenant_id = p_tenant_id
    and public.normalize_campaign_phone(k.phone) = v_phone order by k.created_at limit 1;
  select cc.id into row_id from public.consented_contacts cc where cc.tenant_id = p_tenant_id
    and public.normalize_campaign_phone(cc.phone) = v_phone order by cc.consented_at desc limit 1 for update;
  if p_consent then
    if row_id is null then
      insert into public.consented_contacts(tenant_id, phone, full_name, email, tags, consent_source, consent_note, consented_by, consented_at)
        values (p_tenant_id, v_phone, crm.full_name, crm.email, coalesce(crm.tags, array[]::text[]), p_source, note, uid, now());
    else
      update public.consented_contacts set consent_source = p_source, consent_note = note, consented_by = uid,
        consented_at = now(), opted_out_at = null, opt_out_source = null,
        full_name = coalesce(crm.full_name, full_name), email = coalesce(crm.email, email), tags = coalesce(crm.tags, tags)
        where id = row_id;
    end if;
  else
    if row_id is null then
      insert into public.consented_contacts(tenant_id, phone, full_name, consent_source, consented_by, opted_out_at, opt_out_source)
        values (p_tenant_id, v_phone, crm.full_name, 'manual', uid, now(), 'manual');
    else
      update public.consented_contacts set opted_out_at = coalesce(opted_out_at, now()),
        opt_out_source = coalesce(opt_out_source, 'manual') where id = row_id;
    end if;
  end if;
  insert into public.tenant_audit_events(tenant_id, actor_id, action, details)
    values (p_tenant_id, uid, case when p_consent then 'contact.consent_granted' else 'contact.consent_revoked' end,
      jsonb_build_object('phone_suffix', right(v_phone, 4), 'source', p_source));
  return p_consent;
end;
$$;
revoke all on function public.set_marketing_consent(uuid, text, boolean, text, text) from public, anon;
grant execute on function public.set_marketing_consent(uuid, text, boolean, text, text) to authenticated;

-- Contact list with consent state. Consent fields are null for callers without the
-- campaigns permission (consent_visible = false).
create or replace function public.list_contacts(
  p_tenant_id uuid, p_search text default null, p_limit integer default 50, p_offset integer default 0
) returns table(id uuid, full_name text, phone text, email text, tags text[], last_contacted_at timestamptz,
  created_at timestamptz, consent_visible boolean, consented_at timestamptz, consent_source text, opted_out_at timestamptz)
language plpgsql stable security invoker set search_path = '' as $$
declare term text := nullif(btrim(coalesce(p_search, '')), ''); digits text;
  visible boolean := coalesce(public.user_has_permission(p_tenant_id, 'campaigns'), false);
begin
  if not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset < 0 then
    raise exception 'Invalid page' using errcode = '22023';
  end if;
  term := left(term, 100);
  digits := nullif(regexp_replace(coalesce(term, ''), '[^0-9]', '', 'g'), '');
  return query
  select c.id, c.full_name, c.phone, c.email, c.tags, c.last_contacted_at, c.created_at, visible,
    case when visible then a.consented_at end, case when visible then a.consent_source end,
    case when visible then a.opted_out_at end
  from public.contacts c
  left join lateral (
    select cc.consented_at, cc.consent_source, cc.opted_out_at from public.consented_contacts cc
    where cc.tenant_id = c.tenant_id
      and public.normalize_campaign_phone(cc.phone) = public.normalize_campaign_phone(c.phone)
    order by cc.consented_at desc limit 1
  ) a on true
  where c.tenant_id = p_tenant_id
    and (term is null or c.full_name ilike '%' || replace(replace(term, '%', '\%'), '_', '\_') || '%'
      or (digits is not null and public.normalize_campaign_phone(c.phone) like '%' || digits || '%')
      or term = any(c.tags))
  order by c.created_at desc, c.id
  limit p_limit offset p_offset;
end;
$$;
revoke all on function public.list_contacts(uuid, text, integer, integer) from public, anon;
grant execute on function public.list_contacts(uuid, text, integer, integer) to authenticated;

-- Bulk import of up to 1000 rows: {full_name, phone, email, tags[], consent}. Consent
-- rows need the campaigns permission and one shared basis note, and never re-subscribe
-- a number that opted out. Returns counts and the first 100 skipped rows.
create or replace function public.import_contacts(p_tenant_id uuid, p_rows jsonb, p_consent_note text default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare item jsonb; row_no integer := 0; v_phone text; existing uuid; consent_row public.consented_contacts;
  created integer := 0; updated integer := 0; consented integer := 0; skipped jsonb := '[]'::jsonb;
  skipped_count integer := 0; wants_consent boolean; note text := nullif(btrim(coalesce(p_consent_note, '')), '');
  v_tags text[]; seen text[] := array[]::text[];
begin
  if not coalesce(public.user_has_permission(p_tenant_id, 'inbox'), false) then
    raise exception 'Inbox permission required' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0
    or jsonb_array_length(p_rows) > 1000 or octet_length(p_rows::text) > 2097152 then
    raise exception 'Import between 1 and 1000 rows' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_rows) r where r->'consent' = 'true'::jsonb) then
    if not coalesce(public.user_has_permission(p_tenant_id, 'campaigns'), false) then
      raise exception 'Campaign permission required to import consent' using errcode = '42501';
    end if;
    if note is null or length(note) < 3 or length(note) > 500 then
      raise exception 'Describe how consent was obtained' using errcode = '22023';
    end if;
  end if;
  for item in select value from jsonb_array_elements(p_rows) loop
    row_no := row_no + 1;
    if jsonb_typeof(item) <> 'object' then
      skipped_count := skipped_count + 1;
      if skipped_count <= 100 then skipped := skipped || jsonb_build_object('row', row_no, 'reason', 'invalid_row'); end if;
      continue;
    end if;
    v_phone := public.contact_phone(item->>'phone');
    if v_phone is null then
      skipped_count := skipped_count + 1;
      if skipped_count <= 100 then skipped := skipped || jsonb_build_object('row', row_no, 'reason', 'invalid_phone'); end if;
      continue;
    end if;
    v_tags := case when jsonb_typeof(item->'tags') = 'array'
      then public.clean_contact_tags(array(select jsonb_array_elements_text(item->'tags'))) end;
    select id into existing from public.contacts where tenant_id = p_tenant_id
      and public.normalize_campaign_phone(contacts.phone) = v_phone order by contacts.created_at limit 1;
    if existing is null and not (v_phone = any(seen)) then created := created + 1; else updated := updated + 1; end if;
    seen := seen || v_phone;
    perform public.upsert_contact(p_tenant_id, item->>'full_name', v_phone,
      case when (item->>'email') ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then item->>'email' end, v_tags);
    wants_consent := item->'consent' = 'true'::jsonb;
    if wants_consent then
      select * into consent_row from public.consented_contacts cc where cc.tenant_id = p_tenant_id
        and public.normalize_campaign_phone(cc.phone) = v_phone order by cc.consented_at desc limit 1;
      if consent_row.id is not null and consent_row.opted_out_at is not null then
        skipped_count := skipped_count + 1;
        if skipped_count <= 100 then skipped := skipped || jsonb_build_object('row', row_no, 'reason', 'opted_out'); end if;
      elsif consent_row.id is null then
        perform public.import_consent(p_tenant_id, v_phone, note);
        consented := consented + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('created', created, 'updated', updated, 'consented', consented,
    'skipped_count', skipped_count, 'skipped', skipped);
end;
$$;

-- Service-side insert for import consent, so clients keep no direct consent writes.
create or replace function public.import_consent(p_tenant_id uuid, p_phone text, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare crm public.contacts;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'campaigns'), false) then
    raise exception 'Campaign permission required' using errcode = '42501';
  end if;
  select * into crm from public.contacts k where k.tenant_id = p_tenant_id
    and public.normalize_campaign_phone(k.phone) = p_phone order by k.created_at limit 1;
  insert into public.consented_contacts(tenant_id, phone, full_name, email, tags, consent_source, consent_note, consented_by, consented_at)
    values (p_tenant_id, p_phone, crm.full_name, crm.email, coalesce(crm.tags, array[]::text[]), 'import', p_note, auth.uid(), now());
end;
$$;
revoke all on function public.import_consent(uuid, text, text) from public, anon;
grant execute on function public.import_consent(uuid, text, text) to authenticated;
revoke all on function public.import_contacts(uuid, jsonb, text) from public, anon;
grant execute on function public.import_contacts(uuid, jsonb, text) to authenticated;

-- Audience matching and dispatch now exclude opted-out numbers (definitions below are
-- the previous ones plus `opted_out_at is null`).
CREATE OR REPLACE FUNCTION public.campaign_audience(p_tenant_id uuid, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS SETOF consented_contacts
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  if coalesce(auth.role(), '') <> 'service_role'
    and not coalesce(public.user_has_permission(p_tenant_id, 'campaigns'), false) then
    raise exception 'Campaign permission required' using errcode = '42501';
  end if;
  perform public.validate_campaign_audience(p_filter);
  return query
  select c.* from public.consented_contacts c
  where c.tenant_id = p_tenant_id
    and c.opted_out_at is null
    and (not (p_filter ? 'segment') or btrim(p_filter->>'segment') = any(c.tags))
    and (not (p_filter ? 'last_contacted') or c.last_contacted_at >=
      now() - make_interval(days => rtrim(p_filter->>'last_contacted', 'd')::int))
    and not exists (
      select 1 from jsonb_array_elements(coalesce(p_filter->'custom', '[]'::jsonb)) r
      where not coalesce(case r->>'field'
        when 'Etiket' then btrim(r->>'value') = any(c.tags)
        when 'Son iletisim' then
          case r->>'operator'
            when '>' then c.last_contacted_at < now() - make_interval(days => split_part(btrim(r->>'value'), ' ', 1)::int)
            when '<' then c.last_contacted_at >= now() - make_interval(days => split_part(btrim(r->>'value'), ' ', 1)::int)
            when '=' then floor(extract(epoch from (now() - c.last_contacted_at)) / 86400) = split_part(btrim(r->>'value'), ' ', 1)::int
          end
        else false end, false)
    )
  order by c.id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.start_campaign_dispatch(p_dispatch_id uuid, p_lease_token uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare j public.campaign_dispatches; snapshot jsonb; current_template jsonb;
begin
  perform public.require_campaign_worker();
  select * into j from public.campaign_dispatches where id = p_dispatch_id for update;
  if not found or j.state <> 'leased' or j.lease_token is distinct from p_lease_token
    or j.leased_until <= now() then return false; end if;
  if not exists (select 1 from public.consented_contacts c
    where c.id = j.consented_contact_id and c.tenant_id = j.tenant_id
      and public.normalize_campaign_phone(c.phone) = j.recipient_phone
      and c.opted_out_at is null) then
    update public.campaign_dispatches set state = 'cancelled', error_code = 'consent_unavailable',
      leased_until = null, updated_at = now() where id = j.id;
    return false;
  end if;
  select c.send_snapshot->'template', jsonb_build_object('name', t.name, 'language', t.language, 'components', t.components)
    into snapshot, current_template from public.campaigns c
    join public.templates t on t.id = c.template_id and t.tenant_id = c.tenant_id and upper(t.status) = 'APPROVED'
    where c.id = j.campaign_id and c.tenant_id = j.tenant_id and c.status <> 'cancelled';
  if not found or snapshot is distinct from current_template then
    update public.campaign_dispatches set state = 'failed', error_code = 'template_changed_or_unavailable',
      leased_until = null, updated_at = now() where id = j.id;
    return false;
  end if;
  update public.campaign_dispatches set state = 'sending', attempts = attempts + 1,
    dispatch_started_at = now(), leased_until = now() + interval '120 seconds', updated_at = now()
    where id = j.id;
  return true;
end;
$function$
;
