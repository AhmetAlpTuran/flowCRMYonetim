-- Marketing opt-out by WhatsApp keyword (law 6563: recipients must be able to refuse
-- commercial messages easily and free of charge).
--
-- A customer text such as "STOP", "RET" or "beni listeden çıkarın" opts the number out of
-- the business's marketing (consented_contacts.opted_out_at, source whatsapp_keyword);
-- queued campaign dispatches to it are then cancelled at send time as for any opt-out.
-- The bot does not answer that message (an agent sees it). A bare "iptal" is NOT a stop
-- word: customers use it for bookings. Re-subscribing needs a recorded consent
-- (set_marketing_consent), never a keyword.

create function public.is_marketing_stop(p_body text)
returns boolean language sql immutable set search_path = '' as $$
  with folded as (
    select btrim(regexp_replace(regexp_replace(lower(public.knowledge_fold(left(coalesce(p_body, ''), 200))),
      '[^a-z0-9]+', ' ', 'g'), ' +', ' ', 'g')) as text
  )
  select length(text) between 1 and 80 and (
    -- "STOP", "RET", "stop flow", "RET MARKA" (a stop word first, at most three words)
    text ~ '^(stop|ret|unsubscribe)( [a-z0-9]+){0,2}$'
    -- or an explicit refusal phrase in a short message
    or text ~ '(^| )(abonelikten cik|aboneligimi iptal|listeden cik|listenizden cik|mesaj istemiyorum|mesaj gondermeyin|mesaj atmayin|reklam istemiyorum|kampanya istemiyorum|pazarlama istemiyorum|ileti istemiyorum)'
  ) from folded;
$$;

create function public.apply_keyword_opt_out()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_phone text; v_name text; updated integer;
begin
  if not new.is_from_customer or new.message_type is distinct from 'text' or not public.is_marketing_stop(new.body) then
    return new;
  end if;
  select c.customer_phone, c.title into v_phone, v_name from public.conversations c
    where c.tenant_id = new.tenant_id and c.id = new.conversation_id;
  if coalesce(v_phone, '') = '' then return new; end if;
  update public.consented_contacts set opted_out_at = coalesce(opted_out_at, now()),
    opt_out_source = coalesce(opt_out_source, 'whatsapp_keyword')
    where tenant_id = new.tenant_id
      and public.normalize_campaign_phone(phone) = public.normalize_campaign_phone(v_phone);
  get diagnostics updated = row_count;
  if updated = 0 then
    -- Keep the refusal so a later import cannot re-subscribe the number.
    insert into public.consented_contacts(tenant_id, phone, full_name, consent_source, opted_out_at, opt_out_source)
      values (new.tenant_id, public.normalize_campaign_phone(v_phone), left(v_name, 200), 'whatsapp', now(), 'whatsapp_keyword')
      on conflict (tenant_id, phone) do update set opted_out_at = coalesce(consented_contacts.opted_out_at, now()),
        opt_out_source = coalesce(consented_contacts.opt_out_source, 'whatsapp_keyword');
  end if;
  insert into public.tenant_audit_events(tenant_id, action, resource_id, details)
    values (new.tenant_id, 'contact.opted_out', new.conversation_id,
      jsonb_build_object('source', 'whatsapp_keyword', 'message_id', new.id));
  return new;
end;
$$;
create trigger messages_keyword_opt_out after insert on public.messages
  for each row execute function public.apply_keyword_opt_out();

create function public.skip_bot_for_opt_out()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.messages m where m.tenant_id = new.tenant_id and m.id = new.input_message_id
      and m.message_type = 'text' and public.is_marketing_stop(m.body)) then
    new.state := 'cancelled';
    new.error_code := 'marketing_opt_out';
  end if;
  return new;
end;
$$;
create trigger bot_reply_jobs_skip_opt_out before insert on public.bot_reply_jobs
  for each row execute function public.skip_bot_for_opt_out();

revoke all on function public.apply_keyword_opt_out() from public, anon, authenticated;
revoke all on function public.skip_bot_for_opt_out() from public, anon, authenticated;
