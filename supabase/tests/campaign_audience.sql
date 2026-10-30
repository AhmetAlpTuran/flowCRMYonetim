-- Run manually on an isolated migrated development DB during the verification phase.
-- Requires database-owner privileges to create fixtures. All changes roll back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare
  tenant_a uuid := gen_random_uuid();
  tenant_b uuid := gen_random_uuid();
  actual bigint;
begin
  insert into public.tenants(id, name) values (tenant_a, 'Audience test A'), (tenant_b, 'Audience test B');
  insert into public.consented_contacts(tenant_id, phone, tags, last_contacted_at)
  values (tenant_a, '10000000001', array['VIP'], now() - interval '2 days'),
         (tenant_a, '10000000002', array['VIP'], null),
         (tenant_a, '10000000003', array['Other'], now() - interval '20 days'),
         (tenant_b, '10000000004', array['VIP'], now());

  select public.count_campaign_audience(tenant_a, '{}') into actual;
  if actual <> 3 then raise exception 'Tenant scope mismatch: %', actual; end if;
  select public.count_campaign_audience(tenant_a, '{"last_contacted":"7d"}') into actual;
  if actual <> 1 then raise exception 'Recency/null handling mismatch: %', actual; end if;
  select public.count_campaign_audience(tenant_a,
    '{"segment":"VIP","custom":[{"field":"Son iletisim","operator":"<","value":"7 gun"}]}') into actual;
  if actual <> 1 then raise exception 'Combined filter mismatch'; end if;
  select count(*) from public.campaign_audience(tenant_a,
    '{"segment":"VIP","custom":[{"field":"Son iletisim","operator":"<","value":"7 gun"}]}') into actual;
  if actual <> 1 then raise exception 'Preview/dispatch mismatch'; end if;

  begin
    perform public.count_campaign_audience(tenant_a,
      '{"custom":[{"field":"Ulke","operator":"=","value":"TR"}]}');
    raise exception 'Unsupported field was silently accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.count_campaign_audience(tenant_a, '{"last_contacted":"invalid"}');
    raise exception 'Malformed date filter was accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.count_campaign_audience(tenant_a, '{"custom":null}');
    raise exception 'Null rules were accepted';
  exception when invalid_parameter_value then null; end;
end;
$$;
-- A regular caller with no memberships cannot use the function to read a tenant.
set local role authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000001"}', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.count_campaign_audience('00000000-0000-0000-0000-000000000002', '{}');
    raise exception 'Unauthorized audience request accepted';
  exception when insufficient_privilege then null; end;
end;
$$;
rollback;
