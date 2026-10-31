-- Authored only. Run against an isolated database during deferred verification.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare
  tenant_a uuid := gen_random_uuid(); tenant_b uuid := gen_random_uuid(); actor uuid := gen_random_uuid();
  conn_a uuid := gen_random_uuid(); conn_b uuid := gen_random_uuid(); legacy_id uuid := gen_random_uuid();
  unverified_id uuid := gen_random_uuid(); same_language_id uuid; count_before integer;
  metadata jsonb := '{"display_phone_number":"+90 555 000 0000","verified_name":"Fixture","token_expires_at":null}';
  credential jsonb := jsonb_build_object('key_id', 'fixture', 'ciphertext', repeat('A',24), 'iv',repeat('A',16));
  page jsonb := '[{"id":"101","name":"welcome","language":"tr","category":"UTILITY","status":"APPROVED","components":[{"type":"BODY","text":"Merhaba"}]},{"id":"102","name":"welcome","language":"en_US","category":"UTILITY","status":"PENDING","components":[{"type":"BODY","text":"Hello"}]}]';
begin
  insert into auth.users(id,email) values(actor, actor::text || '@example.invalid');
  insert into public.tenants(id,name) values(tenant_a,'Sync A'),(tenant_b,'Sync B');
  insert into public.tenant_memberships(tenant_id,user_id,role) values(tenant_a,actor,'admin'),(tenant_b,actor,'admin');
  perform public.save_whatsapp_connection(tenant_a,actor,conn_a,'800','8000',metadata,credential,true);
  perform public.save_whatsapp_connection(tenant_b,actor,conn_b,'900','9000',metadata,credential,true);
  insert into public.templates(id,tenant_id,name,category,language,status,wa_template_id) values
    (legacy_id,tenant_a,'welcome','UTILITY','tr','PENDING','101'),
    (unverified_id,tenant_a,'welcome','UTILITY','en_US','PENDING',null);
  perform public.apply_whatsapp_template_page(tenant_a,actor,conn_a,page);
  if not exists(select 1 from public.templates where id = legacy_id and waba_id = '800' and status = 'APPROVED') then
    raise exception 'Verified legacy identity was not retained';
  end if;
  if exists(select 1 from public.templates where id = unverified_id and waba_id is not null) then
    raise exception 'Legacy template account was guessed without provider ID';
  end if;
  if not exists(select 1 from public.templates where tenant_id = tenant_a and waba_id = '800' and language = 'en_US' and status = 'PENDING') then
    raise exception 'Template languages were conflated';
  end if;
  select count(*) into count_before from public.templates where tenant_id = tenant_a;
  perform public.apply_whatsapp_template_page(tenant_a,actor,conn_a,page);
  if (select count(*) from public.templates where tenant_id = tenant_a) <> count_before then
    raise exception 'Repeated sync created duplicate templates';
  end if;
  begin
    perform public.apply_whatsapp_template_page(tenant_b,actor,conn_a,page);
    raise exception 'Cross-tenant connection accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.apply_whatsapp_template_page(tenant_a,gen_random_uuid(),conn_a,page);
    raise exception 'Unauthorized actor imported templates';
  exception when insufficient_privilege then null; end;
  perform public.apply_whatsapp_template_page(tenant_b,actor,conn_b,page);
  select id into same_language_id from public.templates where tenant_id = tenant_b and waba_id = '900' and language = 'tr';
  if same_language_id is null or same_language_id = legacy_id then raise exception 'Tenant template identities merged'; end if;
end;
$$;
rollback;
