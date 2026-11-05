-- Marketing opt-out by WhatsApp keyword. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare
  stops text[] := array['STOP', 'stop', 'Stop!', 'RET', 'ret flowcrm', 'RET MARKA', 'Unsubscribe',
    'Abonelikten çıkmak istiyorum', 'beni listeden çıkarın', 'Lütfen bana mesaj göndermeyin',
    'REKLAM İSTEMİYORUM', 'kampanya istemiyorum artık', 'Listenizden çıkarın'];
  others text[] := array['iptal', 'İptal', 'Rezervasyonu iptal edebilir miyim?', 'durdur', 'Merhaba',
    'stop lambası değişimi ne kadar tutar', 'ret edildi mi başvurum', '', 'Arabanın stop lambası yanmıyor',
    'mesaj attım cevap gelmedi'];
  body text;
begin
  foreach body in array stops loop
    if not public.is_marketing_stop(body) then raise exception 'Stop phrase missed: %', body; end if;
  end loop;
  foreach body in array others loop
    if public.is_marketing_stop(body) then raise exception 'Not a stop phrase: %', body; end if;
  end loop;
end;
$$;

do $$
declare t uuid := gen_random_uuid(); t2 uuid := gen_random_uuid(); conn uuid := gen_random_uuid();
  known uuid; unknown uuid; booking uuid; job public.bot_reply_jobs;
begin
  insert into public.tenants(id, name) values (t, 'Ret'), (t2, 'Baska');
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '97101', '971011', 'x', 'active', now());
  insert into public.bot_settings(tenant_id, is_active) values (t, true);
  -- A consented contact stored in a different phone format, and the same number at another business.
  insert into public.consented_contacts(tenant_id, phone, full_name, consent_source)
    values (t, '+90 (555) 400-0001', 'Ayşe', 'manual'), (t2, '905554000001', 'Ayşe', 'manual');
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (t, conn, '905554000001', 'Ayşe', 'open') returning id into known;
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (t, conn, '905554000002', 'Mehmet', 'open') returning id into unknown;
  insert into public.conversations(tenant_id, connection_id, customer_phone, title, status)
    values (t, conn, '905554000003', 'Can', 'open') returning id into booking;

  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (t, known, conn, 'Ayşe', 'STOP', true);
  if not exists (select 1 from public.consented_contacts where tenant_id = t and phone = '+90 (555) 400-0001'
      and opted_out_at is not null and opt_out_source = 'whatsapp_keyword') then
    raise exception 'Consented contact not opted out';
  end if;
  if exists (select 1 from public.consented_contacts where tenant_id = t2 and opted_out_at is not null) then
    raise exception 'Opt-out leaked to another business';
  end if;
  if not exists (select 1 from public.tenant_audit_events where tenant_id = t and action = 'contact.opted_out') then
    raise exception 'Opt-out not audited';
  end if;

  -- A number with no consent row gets a refusal row, so imports cannot subscribe it later.
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (t, unknown, conn, 'Mehmet', 'Beni listeden çıkarın lütfen', true);
  if not exists (select 1 from public.consented_contacts where tenant_id = t and phone = '905554000002'
      and opted_out_at is not null and consent_source = 'whatsapp') then
    raise exception 'Refusal of an unknown number not kept';
  end if;
  if exists (select 1 from public.campaign_recipient_audience(t, '{}') a where public.normalize_campaign_phone(a.phone) in ('905554000001', '905554000002')) then
    raise exception 'Opted-out number still in the marketing audience';
  end if;

  -- The bot does not answer the stop message, but answers a booking "iptal".
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id)
    select t, known, id from public.messages where conversation_id = known and body = 'STOP'
    returning * into job;
  if job.state <> 'cancelled' or job.error_code <> 'marketing_opt_out' then
    raise exception 'Bot job for a stop message was not skipped: %', job.state;
  end if;
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (t, booking, conn, 'Can', 'iptal', true);
  insert into public.bot_reply_jobs(tenant_id, conversation_id, input_message_id)
    select t, booking, id from public.messages where conversation_id = booking and body = 'iptal'
    returning * into job;
  if job.state <> 'queued' or exists (select 1 from public.consented_contacts where tenant_id = t and phone = '905554000003') then
    raise exception 'A booking "iptal" was treated as a marketing opt-out';
  end if;
  -- Agent messages never opt anyone out.
  insert into public.messages(tenant_id, conversation_id, connection_id, sender, body, is_from_customer)
    values (t, booking, conn, 'Temsilci', 'STOP yazarak listeden çıkabilirsiniz', false);
  if exists (select 1 from public.consented_contacts where tenant_id = t and phone = '905554000003') then
    raise exception 'An agent message opted the customer out';
  end if;
  update public.bot_reply_jobs set state = 'cancelled' where tenant_id = t;
end;
$$;
rollback;
