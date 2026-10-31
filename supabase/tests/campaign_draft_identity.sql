-- Authored only; execute on an isolated migrated database in verification phase.
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('request.jwt.claim.role','service_role',true);
do $$
declare
  tenant_a uuid := gen_random_uuid(); tenant_b uuid := gen_random_uuid(); actor uuid := gen_random_uuid();
  fixture_connection uuid := gen_random_uuid(); template_id uuid := gen_random_uuid(); campaign_id uuid := gen_random_uuid();
  payload jsonb; saved jsonb; expected jsonb;
begin
  insert into auth.users(id,email) values(actor,actor::text || '@example.invalid');
  insert into public.tenants(id,name) values(tenant_a,'Draft A'),(tenant_b,'Draft B');
  insert into public.tenant_memberships(tenant_id,user_id,role) values(tenant_a,actor,'admin');
  perform public.save_whatsapp_connection(tenant_a,actor,fixture_connection,'600','6000',
    '{"display_phone_number":"fixture","verified_name":"fixture","token_expires_at":null}',
    jsonb_build_object('key_id','fixture','ciphertext',repeat('A',24),'iv',repeat('A',16)),true);
  insert into public.templates(id,tenant_id,waba_id,name,category,language,status,components)
    values(template_id,tenant_a,'600','fixture','UTILITY','tr','APPROVED','[{"type":"BODY","text":"Hello"}]');
  insert into public.consented_contacts(tenant_id,phone) values(tenant_a,'905550000001');
  perform set_config('request.jwt.claims',json_build_object('role','authenticated','sub',actor)::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  payload := jsonb_build_object('name','Draft','template_id',template_id,'connection_id',fixture_connection,'audience_filter','{}'::jsonb,'template_bindings','{}'::jsonb);
  saved := public.save_campaign_draft(tenant_a,campaign_id,0,payload);
  if (saved->>'revision')::int <> 1 then raise exception 'New draft version incorrect'; end if;
  saved := public.save_campaign_draft(tenant_a,campaign_id,0,payload);
  if (saved->>'revision')::int <> 1 then raise exception 'Repeated create changed version'; end if;
  begin
    perform public.save_campaign_draft(tenant_a,campaign_id,0,payload || '{"name":"Different"}');
    raise exception 'Stale create overwrote existing draft';
  exception when serialization_failure then null; end;
  saved := public.save_campaign_draft(tenant_a,campaign_id,1,payload || '{"name":"Updated"}');
  if (saved->>'revision')::int <> 2 then raise exception 'Edit did not advance version'; end if;
  begin
    perform public.save_campaign_draft(tenant_a,campaign_id,1,payload);
    raise exception 'Stale editor overwrote new version';
  exception when serialization_failure then null; end;
  begin
    perform public.save_campaign_draft(tenant_b,campaign_id,0,payload);
    raise exception 'Other tenant accepted';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',json_build_object('role','service_role','sub',actor)::text,true);
  perform set_config('request.jwt.claim.role','service_role',true);
  select jsonb_build_object('audience_filter',c.audience_filter,'template_id',c.template_id,
    'template_bindings',c.template_bindings,'connection_id',fixture_connection,
    'connection',jsonb_build_object('id',fixture_connection,'waba_id','600','phone_number_id','6000'),
    'template',jsonb_build_object('name',t.name,'language',t.language,'components',t.components))
    into expected from public.campaigns c join public.templates t on t.id=c.template_id where c.id=campaign_id;
  perform public.enqueue_campaign(campaign_id,actor,expected);
  begin
    perform public.save_campaign_draft(tenant_a,campaign_id,2,payload);
    raise exception 'Queued draft was edited';
  exception when object_not_in_prerequisite_state then null; end;
  perform set_config('test.draft_actor',actor::text,true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('test.draft_actor'))::text,true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$
begin
  begin
    update public.campaigns set name='Bypass version API';
    raise exception 'Direct campaign mutation bypassed versioning';
  exception when insufficient_privilege then null; end;
end;
$$;
rollback;
