-- Contacts, consent proof, opt-out exclusion and CSV import rules. All changes roll back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare tenant uuid := gen_random_uuid(); other uuid := gen_random_uuid();
  marketer uuid := gen_random_uuid(); agent uuid := gen_random_uuid();
begin
  insert into public.tenants(id, name, features) values (tenant, 'Contacts A', array['inbox','campaigns']),
    (other, 'Contacts B', array['inbox','campaigns']);
  insert into auth.users(id, email, email_confirmed_at) values
    (marketer, 'marketer-' || marketer || '@example.invalid', now()),
    (agent, 'agent-' || agent || '@example.invalid', now());
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (tenant, marketer, 'user', array['inbox', 'campaigns']),
    (tenant, agent, 'user', array['inbox']);
  insert into public.consented_contacts(tenant_id, phone, tags) values (other, '905550009999', array['VIP']);
  perform set_config('test.tenant', tenant::text, true);
  perform set_config('test.other', other::text, true);
  perform set_config('test.marketer', marketer::text, true);
  perform set_config('test.agent', agent::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);

-- An inbox-only agent manages CRM contacts but cannot touch consent.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.agent'))::text, true);
do $$
declare t uuid := current_setting('test.tenant')::uuid; first_id uuid; same_id uuid; listed record;
begin
  begin
    perform public.upsert_contact(t, 'Bad', '12');
    raise exception 'Invalid phone accepted';
  exception when sqlstate '22023' then null;
  end;
  first_id := public.upsert_contact(t, 'Ayşe Yılmaz', '+90 (555) 111 22 33', 'AYSE@example.invalid', array[' VIP ', 'VIP', '']);
  same_id := public.upsert_contact(t, '', '0090 555 111 2233', null, null);
  if first_id <> same_id then raise exception 'Same number created a duplicate contact'; end if;
  if not exists (select 1 from public.contacts where id = first_id and full_name = 'Ayşe Yılmaz'
      and phone = '905551112233' and email = 'ayse@example.invalid' and tags = array['VIP']) then
    raise exception 'Contact not normalized or name/tags lost on partial update';
  end if;
  select * into listed from public.list_contacts(t, '5551112') limit 1;
  if listed.id is distinct from first_id or listed.consent_visible then
    raise exception 'Phone search or consent visibility wrong for agent';
  end if;
  begin
    perform public.set_marketing_consent(t, '905551112233', true, 'Mağazada form');
    raise exception 'Agent granted consent';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.import_contacts(t, '[{"phone":"905551110000","consent":true}]', 'Form');
    raise exception 'Agent imported consent';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.consented_contacts(tenant_id, phone) values (t, '905551112233');
    raise exception 'Direct consent insert allowed';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- The marketer records consent with proof; tags follow CRM edits; opt-out excludes
-- the number from audiences and from already-queued dispatch checks.
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.marketer'))::text, true);
do $$
declare t uuid := current_setting('test.tenant')::uuid; consent public.consented_contacts; listed record; result jsonb;
begin
  begin
    perform public.set_marketing_consent(t, '905551112233', true, null);
    raise exception 'Consent without basis accepted';
  exception when sqlstate '22023' then null;
  end;
  perform public.set_marketing_consent(t, '905551112233', true, 'Mağazada imzalı form, 2026-11-01');
  select * into consent from public.consented_contacts where tenant_id = t and phone = '905551112233';
  if consent.consent_source <> 'manual' or consent.consented_by <> auth.uid() or consent.tags <> array['VIP']
    or consent.full_name <> 'Ayşe Yılmaz' then raise exception 'Consent proof or CRM copy missing'; end if;
  if public.count_campaign_audience(t, '{"segment":"VIP"}') <> 1 then raise exception 'Consented contact not in audience'; end if;

  update public.contacts set tags = array['Gold'] where tenant_id = t and phone = '905551112233';
  if public.count_campaign_audience(t, '{"segment":"Gold"}') <> 1 then raise exception 'CRM tags did not reach the audience'; end if;

  select * into listed from public.list_contacts(t, 'Ayşe') limit 1;
  if not listed.consent_visible or listed.consented_at is null or listed.opted_out_at is not null then
    raise exception 'Marketer cannot see consent state';
  end if;

  perform public.set_marketing_consent(t, '+90 555 111 22 33', false);
  if public.count_campaign_audience(t, '{}') <> 0 then raise exception 'Opted-out number still in audience'; end if;
  if not exists (select 1 from public.consented_contacts where tenant_id = t and phone = '905551112233'
      and opted_out_at is not null and consent_note is not null) then raise exception 'Opt-out discarded the consent evidence'; end if;

  -- Import: dedupe, invalid rows, opted-out numbers are never re-subscribed.
  begin
    perform public.import_contacts(t, '[{"phone":"905551110001","consent":true}]', '');
    raise exception 'Consent import without basis accepted';
  exception when sqlstate '22023' then null;
  end;
  result := public.import_contacts(t, jsonb_build_array(
    jsonb_build_object('full_name', 'Mehmet', 'phone', '0090 555 111 0001', 'tags', jsonb_build_array('Kiralama'), 'consent', true),
    jsonb_build_object('full_name', 'Mehmet K.', 'phone', '905551110001', 'consent', true),
    jsonb_build_object('full_name', 'Geçersiz', 'phone', 'abc'),
    jsonb_build_object('full_name', 'Ayşe', 'phone', '905551112233', 'consent', true),
    jsonb_build_object('full_name', 'Zeynep', 'phone', '905551110002', 'consent', 'evet'),
    '"not an object"'::jsonb
  ), 'Web sitesi bülten formu');
  if (result->>'created')::int <> 2 or (result->>'updated')::int <> 2 or (result->>'consented')::int <> 1
    or (result->>'skipped_count')::int <> 3 then raise exception 'Import counts wrong: %', result; end if;
  if not (result->'skipped' @> '[{"row":3,"reason":"invalid_phone"},{"row":4,"reason":"opted_out"},{"row":6,"reason":"invalid_row"}]') then
    raise exception 'Import skip reasons wrong: %', result;
  end if;
  if exists (select 1 from public.consented_contacts where tenant_id = t and phone = '905551112233' and opted_out_at is null) then
    raise exception 'Import re-subscribed an opted-out number';
  end if;
  if not exists (select 1 from public.consented_contacts where tenant_id = t and phone = '905551110001'
      and consent_source = 'import' and consent_note = 'Web sitesi bülten formu') then
    raise exception 'Imported consent missing its basis';
  end if;
  if exists (select 1 from public.consented_contacts where tenant_id = t and phone = '905551110002') then
    raise exception 'Non-boolean consent value treated as consent';
  end if;
  if (select full_name from public.contacts where tenant_id = t and phone = '905551110001') <> 'Mehmet K.' then
    raise exception 'Later duplicate row did not update the contact';
  end if;
  if public.count_campaign_audience(t, '{"segment":"Kiralama"}') <> 1 then
    raise exception 'Imported consented contact not in audience';
  end if;

  -- An explicit, documented re-grant is still possible after an opt-out.
  perform public.set_marketing_consent(t, '905551112233', true, 'Müşteri WhatsApp üzerinden yeniden onay verdi', 'whatsapp');
  if public.count_campaign_audience(t, '{"segment":"Gold"}') <> 1 then raise exception 'Re-grant did not restore the audience'; end if;

  -- Another tenant's consent stays invisible.
  if exists (select 1 from public.consented_contacts where tenant_id = current_setting('test.other')::uuid) then
    raise exception 'Cross-tenant consent visible';
  end if;
  begin
    perform public.list_contacts(current_setting('test.other')::uuid);
    raise exception 'Cross-tenant contact list allowed';
  exception when insufficient_privilege then null;
  end;
end;
$$;
-- The audit log is admin-readable only, so check it as the owner.
reset role;
do $$
begin
  if (select count(*) from public.tenant_audit_events where tenant_id = current_setting('test.tenant')::uuid
      and action in ('contact.consent_granted', 'contact.consent_revoked')) <> 3 then
    raise exception 'Consent changes not audited';
  end if;
  if exists (select 1 from public.tenant_audit_events where tenant_id = current_setting('test.tenant')::uuid
      and details::text like '%905551112233%') then
    raise exception 'Audit log stores the full phone number';
  end if;
end;
$$;
rollback;
