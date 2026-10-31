-- Verified webhooks are durably acknowledged before business processing.
create table public.whatsapp_webhook_events (
  event_key text primary key check(event_key ~ '^[0-9a-f]{64}$'),
  waba_id text not null check(waba_id ~ '^[0-9]{1,40}$'),
  phone_number_id text not null check(phone_number_id ~ '^[0-9]{1,40}$'),
  tenant_id uuid references public.tenants(id) on delete cascade,
  connection_id uuid,
  kind text not null check(kind in ('message','status')),
  provider_message_id text not null check(provider_message_id like 'wamid.%' and length(provider_message_id) <= 512),
  occurred_at timestamptz not null,
  payload jsonb not null check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=262144),
  state text not null default 'pending' check(state in ('pending','applied','ignored','error')),
  attempts integer not null default 0,
  available_at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error_code text,
  check((tenant_id is null) = (connection_id is null)),
  foreign key(tenant_id,connection_id) references public.whatsapp_connections(tenant_id,id) on delete cascade
);
create index whatsapp_events_pending on public.whatsapp_webhook_events(available_at,event_key) where state='pending';
create index whatsapp_events_tenant_received on public.whatsapp_webhook_events(tenant_id,received_at);
alter table public.whatsapp_webhook_events enable row level security;
revoke all on public.whatsapp_webhook_events from public,anon,authenticated;
grant all on public.whatsapp_webhook_events to service_role;

alter table public.campaign_dispatches add column delivery_status_at timestamptz;
alter table public.campaign_dispatches add column delivery_error_code text;

create or replace function public.ingest_whatsapp_events(p_events jsonb)
returns integer language plpgsql security invoker set search_path='' as $$
declare item jsonb; w public.whatsapp_connections; inserted integer := 0; affected integer;
begin
  perform public.require_service_role();
  if p_events is null or jsonb_typeof(p_events)<>'array' or jsonb_array_length(p_events)>1000
    or octet_length(p_events::text)>4194304 then
    raise exception 'Invalid event batch' using errcode='22023';
  end if;
  for item in select value from jsonb_array_elements(p_events) loop
    select * into w from public.whatsapp_connections where phone_number_id=item->>'phone_number_id' and waba_id=item->>'waba_id';
    insert into public.whatsapp_webhook_events(event_key,waba_id,phone_number_id,tenant_id,connection_id,kind,provider_message_id,occurred_at,payload)
      values(item->>'event_key',item->>'waba_id',item->>'phone_number_id',w.tenant_id,w.id,
        item->>'kind',item->>'message_id',(item->>'occurred_at')::timestamptz,item->'payload')
      on conflict(event_key) do nothing;
    get diagnostics affected=row_count;
    inserted:=inserted+affected;
  end loop;
  return inserted;
end;
$$;

-- A failed receipt is not proof of delivery. Once delivered/read is observed,
-- delayed sent/failed events cannot downgrade it. A later positive receipt wins.
create or replace function public.apply_campaign_receipt(p_event_key text)
returns boolean language plpgsql security invoker set search_path='' as $$
declare e public.whatsapp_webhook_events; j public.campaign_dispatches;
  callback_id uuid; callback_token uuid; incoming text; effective text;
begin
  perform public.require_service_role();
  select * into e from public.whatsapp_webhook_events where event_key=p_event_key;
  if not found or e.kind<>'status' or e.tenant_id is null then return false; end if;
  incoming:=e.payload->>'status';
  if incoming is null or incoming not in ('sent','delivered','read','failed') then
    raise exception 'Invalid receipt state' using errcode='22023';
  end if;
  if e.payload->>'callback' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    callback_id:=split_part(e.payload->>'callback',':',1)::uuid;
    callback_token:=split_part(e.payload->>'callback',':',2)::uuid;
  end if;
  select d.* into j from public.campaign_dispatches d
    join public.campaigns c on c.id=d.campaign_id and c.tenant_id=d.tenant_id
    where d.tenant_id=e.tenant_id and c.connection_id=e.connection_id
      and d.recipient_phone=e.payload->>'recipient_phone'
      and (d.provider_message_id=e.provider_message_id or
        (d.id=callback_id and d.lease_token=callback_token and d.state in ('sending','unknown') and d.provider_message_id is null))
    order by (d.provider_message_id=e.provider_message_id) desc nulls last limit 1 for update of d;
  if not found then return false; end if;
  effective:=case
    when j.delivery_status='read' or incoming='read' then 'read'
    when j.delivery_status='delivered' or incoming='delivered' then 'delivered'
    when j.delivery_status='failed' or incoming='failed' then 'failed'
    else 'sent' end;
  update public.campaign_dispatches set state='accepted',provider_message_id=e.provider_message_id,
    accepted_at=coalesce(accepted_at,e.occurred_at),leased_until=null,
    error_code=null,error_detail=null,delivery_status=effective,
    delivery_status_at=case when effective=incoming then greatest(delivery_status_at,e.occurred_at) else delivery_status_at end,
    delivered_at=case when incoming='delivered' then least(delivered_at,e.occurred_at) else delivered_at end,
    read_at=case when incoming='read' then least(read_at,e.occurred_at) else read_at end,
    delivery_error_code=case when effective='failed' then coalesce(e.payload->>'error_code',delivery_error_code)
      else null end, updated_at=now() where id=j.id;
  update public.consented_contacts set last_contacted_at=greatest(last_contacted_at,e.occurred_at)
    where id=j.consented_contact_id and tenant_id=j.tenant_id and public.normalize_campaign_phone(phone)=j.recipient_phone;
  return true;
end;
$$;

create or replace function public.process_whatsapp_receipts(p_limit integer default 50)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare e public.whatsapp_webhook_events; w public.whatsapp_connections; applied integer:=0; deferred integer:=0; failures integer:=0;
begin
  perform public.require_service_role();
  if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid batch limit' using errcode='22023'; end if;
  for e in select * from public.whatsapp_webhook_events where kind='status' and state='pending' and available_at<=now()
    order by available_at,event_key limit p_limit for update skip locked loop
    begin
      if e.connection_id is null then
        select * into w from public.whatsapp_connections where phone_number_id=e.phone_number_id and waba_id=e.waba_id;
        if found then
          update public.whatsapp_webhook_events set tenant_id=w.tenant_id,connection_id=w.id where event_key=e.event_key;
        end if;
      end if;
      if public.apply_campaign_receipt(e.event_key) then
        update public.whatsapp_webhook_events set state='applied',processed_at=now(),error_code=null,attempts=attempts+1 where event_key=e.event_key;
        applied:=applied+1;
      else
        update public.whatsapp_webhook_events set state=case when received_at<now()-interval '7 days' then 'error' else 'pending' end,
          error_code='receipt_unmatched',available_at=now()+interval '5 minutes',attempts=attempts+1 where event_key=e.event_key;
        deferred:=deferred+1;
      end if;
    exception when others then
      -- Roll back only this event's application. Never persist raw database/provider errors.
      update public.whatsapp_webhook_events set state=case when attempts>=19 then 'error' else 'pending' end,
        error_code='receipt_processing_failed',attempts=attempts+1,available_at=now()+interval '5 minutes' where event_key=e.event_key;
      failures:=failures+1;
    end;
  end loop;
  return jsonb_build_object('applied',applied,'deferred',deferred,'failed',failures);
end;
$$;

revoke all on function public.ingest_whatsapp_events(jsonb) from public,anon,authenticated;
revoke all on function public.apply_campaign_receipt(text) from public,anon,authenticated;
revoke all on function public.process_whatsapp_receipts(integer) from public,anon,authenticated;
grant execute on function public.ingest_whatsapp_events(jsonb) to service_role;
grant execute on function public.apply_campaign_receipt(text) to service_role;
grant execute on function public.process_whatsapp_receipts(integer) to service_role;
