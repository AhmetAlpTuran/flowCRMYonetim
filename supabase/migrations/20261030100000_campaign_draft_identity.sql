-- Stable client IDs and optimistic versions make lost save replies safe to retry.
alter table public.campaigns add column revision bigint not null default 0 check (revision >= 0);

create or replace function public.save_campaign_draft(
  p_tenant_id uuid, p_campaign_id uuid, p_expected_revision bigint, p_draft jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.campaigns; current_draft jsonb; name_value text; template_value uuid; connection_value uuid;
begin
  if auth.uid() is null or not coalesce(public.user_has_permission(p_tenant_id, 'campaigns'), false) then
    raise exception 'Campaign permission required' using errcode = '42501';
  end if;
  if p_campaign_id is null or p_expected_revision is null or p_expected_revision < 0
    or p_draft is null or jsonb_typeof(p_draft) <> 'object'
    or octet_length(p_draft::text) > 131072
    or p_draft - array['name','template_id','connection_id','audience_filter','template_bindings'] <> '{}'::jsonb then
    raise exception 'Invalid campaign draft' using errcode = '22023';
  end if;
  name_value := btrim(p_draft->>'name');
  template_value := (p_draft->>'template_id')::uuid;
  connection_value := (p_draft->>'connection_id')::uuid;
  if name_value is null or length(name_value) not between 1 and 200 or template_value is null or connection_value is null
    or jsonb_typeof(p_draft->'name') is distinct from 'string'
    or jsonb_typeof(p_draft->'template_bindings') is distinct from 'object'
    or jsonb_typeof(p_draft->'audience_filter') is distinct from 'object' then
    raise exception 'Campaign name, connection, template and values required' using errcode = '22023';
  end if;
  p_draft := p_draft || jsonb_build_object('name',name_value,'template_id',template_value,'connection_id',connection_value);
  perform public.validate_campaign_audience(p_draft->'audience_filter');
  if not exists(select 1 from public.templates t join public.whatsapp_connections w
    on w.waba_id = t.waba_id and w.tenant_id = t.tenant_id
    where t.id = template_value and t.tenant_id = p_tenant_id and w.id = connection_value) then
    raise exception 'Template and connection must belong to the same tenant account' using errcode = '22023';
  end if;
  -- Concurrent creates of the same ID serialize on the unique primary key.
  if p_expected_revision = 0 then
    insert into public.campaigns(id,tenant_id,name,template_id,connection_id,audience_filter,template_bindings,status,revision)
      values(p_campaign_id,p_tenant_id,name_value,template_value,connection_value,
        p_draft->'audience_filter',p_draft->'template_bindings','draft',1)
      on conflict(id) do nothing;
  end if;
  select * into c from public.campaigns where id = p_campaign_id and tenant_id = p_tenant_id for update;
  if not found then raise exception 'Campaign unavailable' using errcode = '42501'; end if;
  current_draft := jsonb_build_object('name',c.name,'template_id',c.template_id,'connection_id',c.connection_id,
    'audience_filter',c.audience_filter,'template_bindings',c.template_bindings);
  if current_draft = p_draft then return to_jsonb(c); end if;
  if c.queued_at is not null or c.status <> 'draft' then
    raise exception 'Campaign already submitted; refresh its status' using errcode = '55000';
  end if;
  if c.revision <> p_expected_revision then
    raise exception 'Campaign changed; reload before editing' using errcode = '40001';
  end if;
  update public.campaigns set name = name_value, template_id = template_value, connection_id = connection_value,
    audience_filter = p_draft->'audience_filter', template_bindings = p_draft->'template_bindings', revision = revision + 1
    where id = c.id and tenant_id = p_tenant_id returning * into c;
  return to_jsonb(c);
end;
$$;
revoke all on function public.save_campaign_draft(uuid,uuid,bigint,jsonb) from public, anon;
grant execute on function public.save_campaign_draft(uuid,uuid,bigint,jsonb) to authenticated;
-- All client writes now go through the permission-checked, versioned draft API.
revoke all on public.campaigns from anon, authenticated;
grant select on public.campaigns to authenticated;
