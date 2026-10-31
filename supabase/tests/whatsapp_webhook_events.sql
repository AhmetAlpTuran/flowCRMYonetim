-- Authored only. All fixture changes roll back; no external messages are sent.
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('request.jwt.claim.role','service_role',true);
do $$
declare
  tenant_a uuid:=gen_random_uuid(); tenant_b uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid();
  conn_a uuid:=gen_random_uuid(); conn_b uuid:=gen_random_uuid(); fixture_template uuid:=gen_random_uuid();
  fixture_campaign uuid:=gen_random_uuid(); job public.campaign_dispatches;
  expected jsonb; event jsonb; result jsonb;
  metadata jsonb:='{"display_phone_number":"fixture","verified_name":"fixture","token_expires_at":null}';
  credential jsonb:=jsonb_build_object('key_id','fixture','ciphertext',repeat('A',24),'iv',repeat('A',16));
begin
  insert into auth.users(id,email) values(actor,actor::text || '@example.invalid');
  insert into public.tenants(id,name) values(tenant_a,'Webhook A'),(tenant_b,'Webhook B');
  insert into public.tenant_memberships(tenant_id,user_id,role) values(tenant_a,actor,'admin'),(tenant_b,actor,'admin');
  perform public.save_whatsapp_connection(tenant_a,actor,conn_a,'501','5010',metadata,credential,true);
  perform public.save_whatsapp_connection(tenant_b,actor,conn_b,'502','5020',metadata,credential,true);
  insert into public.templates(id,tenant_id,waba_id,name,category,language,status,components)
    values(fixture_template,tenant_a,'501','fixture','UTILITY','tr','APPROVED','[{"type":"BODY","text":"Hello"}]');
  insert into public.consented_contacts(tenant_id,phone) values(tenant_a,'905550000001');
  insert into public.campaigns(id,tenant_id,name,template_id,connection_id,status)
    values(fixture_campaign,tenant_a,'Webhook fixture',fixture_template,conn_a,'draft');
  select jsonb_build_object('audience_filter',c.audience_filter,'template_id',c.template_id,
    'template_bindings',c.template_bindings,'connection_id',conn_a,
    'connection',jsonb_build_object('id',conn_a,'waba_id','501','phone_number_id','5010'),
    'template',jsonb_build_object('name',t.name,'language',t.language,'components',t.components))
    into expected from public.campaigns c join public.templates t on t.id=c.template_id where c.id=fixture_campaign;
  perform public.enqueue_campaign(fixture_campaign,actor,expected);
  select * into job from public.claim_campaign_dispatches(1,fixture_campaign);
  perform public.start_campaign_dispatch(job.id,job.lease_token);
  perform public.finish_campaign_dispatch(job.id,job.lease_token,'unknown');
  event:=jsonb_build_object('event_key',repeat('a',64),'waba_id','502','phone_number_id','5020',
    'kind','status','message_id','wamid.receipt-fixture','occurred_at',now(),
    'payload',jsonb_build_object('status','sent','recipient_phone','905550000001','callback',job.id::text || ':' || job.lease_token::text));
  perform public.ingest_whatsapp_events(jsonb_build_array(event));
  perform public.process_whatsapp_receipts(50);
  if (select state from public.campaign_dispatches where id=job.id)<>'unknown' then raise exception 'Other tenant receipt matched a dispatch'; end if;
  event:=event || jsonb_build_object('event_key',repeat('b',64),'waba_id','501','phone_number_id','5010');
  if public.ingest_whatsapp_events(jsonb_build_array(event))<>1 then raise exception 'Event not persisted'; end if;
  if public.ingest_whatsapp_events(jsonb_build_array(event))<>0 then raise exception 'Duplicate event persisted'; end if;
  perform public.process_whatsapp_receipts(50);
  if not exists(select 1 from public.campaign_dispatches where id=job.id and state='accepted' and delivery_status='sent') then
    raise exception 'Receipt did not reconcile original unknown attempt';
  end if;
  if not public.finish_campaign_dispatch(job.id,job.lease_token,'accepted','wamid.receipt-fixture') then
    raise exception 'Receipt-before-response broke idempotent late acknowledgement';
  end if;
  event:=event || jsonb_build_object('event_key',repeat('c',64),'payload',jsonb_build_object('status','failed','recipient_phone','905550000001','error_code','meta_131026'));
  perform public.ingest_whatsapp_events(jsonb_build_array(event)); perform public.process_whatsapp_receipts(50);
  result:=public.campaign_progress(fixture_campaign);
  if (result->>'delivery_failed')::int<>1 or (result->>'accepted')::int<>1 then raise exception 'Delivery failure conflated with API rejection'; end if;
  event:=event || jsonb_build_object('event_key',repeat('d',64),'payload',jsonb_build_object('status','read','recipient_phone','905550000001'));
  perform public.ingest_whatsapp_events(jsonb_build_array(event)); perform public.process_whatsapp_receipts(50);
  result:=public.campaign_progress(fixture_campaign);
  if (result->>'read')::int<>1 or (result->>'delivered')::int<>1 or (result->>'delivery_failed')::int<>0 then
    raise exception 'Read receipt did not imply delivery or clear stale failure';
  end if;
  event:=event || jsonb_build_object('event_key',repeat('e',64),'occurred_at',now()-interval '1 hour',
    'payload',jsonb_build_object('status','failed','recipient_phone','905550000001','error_code','meta_100'));
  perform public.ingest_whatsapp_events(jsonb_build_array(event)); perform public.process_whatsapp_receipts(50);
  if not exists(select 1 from public.campaign_dispatches where id=job.id and delivery_status='read' and delivery_error_code is null) then
    raise exception 'Out-of-order failure downgraded read receipt';
  end if;
  event:=event || jsonb_build_object('event_key',repeat('f',64),'waba_id','999','phone_number_id','9990');
  perform public.ingest_whatsapp_events(jsonb_build_array(event));
  if not exists(select 1 from public.whatsapp_webhook_events where event_key=repeat('f',64) and tenant_id is null and connection_id is null) then
    raise exception 'Unknown connection was routed to an arbitrary tenant';
  end if;
  perform set_config('test.webhook_actor',actor::text,true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('test.webhook_actor'))::text,true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$
begin
  begin
    perform 1 from public.whatsapp_webhook_events;
    raise exception 'Tenant administrator could read private webhook payloads';
  exception when insufficient_privilege then null; end;
  begin
    perform public.ingest_whatsapp_events('[]');
    raise exception 'Authenticated caller forged verified events';
  exception when insufficient_privilege then null; end;
end;
$$;
rollback;
