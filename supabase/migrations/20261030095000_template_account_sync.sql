-- Template identity belongs to a WhatsApp business account and language.
-- Legacy unlinked rows remain preserved; no guessed cross-account reassignment.
create unique index templates_account_identity on public.templates(tenant_id, waba_id, name, language)
  where waba_id is not null;

create or replace function public.apply_whatsapp_template_page(
  p_tenant_id uuid, p_actor_id uuid, p_connection_id uuid, p_templates jsonb
) returns integer language plpgsql security invoker set search_path = '' as $$
declare w public.whatsapp_connections; item jsonb; template_row uuid; legacy_count integer;
  account_count integer; affected integer := 0;
begin
  perform public.require_service_role();
  if p_actor_id is null or not exists (select 1 from public.tenant_memberships m
    where m.tenant_id = p_tenant_id and m.user_id = p_actor_id
      and (m.role = 'admin' or 'templates' = any(m.permissions))) then
    raise exception 'Template permission required' using errcode = '42501';
  end if;
  if p_templates is null or jsonb_typeof(p_templates) <> 'array' or jsonb_array_length(p_templates) > 100
    or octet_length(p_templates::text) > 8388608 then
    raise exception 'Invalid template page' using errcode = '22023';
  end if;
  -- Serialize page imports and connection registration for deterministic adoption.
  perform 1 from public.tenants where id = p_tenant_id for update;
  select * into w from public.whatsapp_connections where id = p_connection_id and tenant_id = p_tenant_id
    and status = 'active' and (token_expires_at is null or token_expires_at > now()) for share;
  if not found then raise exception 'Active tenant connection required' using errcode = '22023'; end if;
  select count(distinct waba_id) into account_count from public.whatsapp_connections where tenant_id = p_tenant_id;
  for item in select value from jsonb_array_elements(p_templates) loop
    if jsonb_typeof(item) <> 'object' or coalesce(item->>'id', '') !~ '^[0-9]{1,40}$'
      or coalesce(item->>'name', '') !~ '^[a-z0-9_]{1,512}$'
      or coalesce(item->>'language', '') !~ '^[a-z]{2,3}(_[A-Za-z]{2,4})?$'
      or coalesce(item->>'status', '') !~ '^[A-Z_]{1,40}$'
      or coalesce(item->>'category', '') !~ '^[A-Z_]{1,40}$'
      or jsonb_typeof(item->'components') is distinct from 'array' then
      raise exception 'Invalid template definition' using errcode = '22023';
    end if;
    select id into template_row from public.templates where tenant_id = p_tenant_id and waba_id = w.waba_id
      and name = item->>'name' and language = item->>'language' for update;
    if not found and account_count = 1 then
      select count(*) into legacy_count from public.templates where tenant_id = p_tenant_id and waba_id is null
        and name = item->>'name' and language = item->>'language'
        and wa_template_id = item->>'id';
      if legacy_count = 1 then
        select id into template_row from public.templates where tenant_id = p_tenant_id and waba_id is null
          and name = item->>'name' and language = item->>'language'
          and wa_template_id = item->>'id' for update;
      end if;
    end if;
    if template_row is null then
      insert into public.templates(tenant_id, waba_id, name, language, category, status, components, wa_template_id, status_updated_at)
        values(p_tenant_id, w.waba_id, item->>'name', item->>'language', item->>'category', item->>'status',
          item->'components', item->>'id', now());
    else
      update public.templates set waba_id = w.waba_id, category = item->>'category', status = item->>'status',
        components = item->'components', wa_template_id = item->>'id', status_updated_at = now()
        where id = template_row and tenant_id = p_tenant_id;
    end if;
    affected := affected + 1;
  end loop;
  return affected;
end;
$$;
revoke all on function public.apply_whatsapp_template_page(uuid, uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.apply_whatsapp_template_page(uuid, uuid, uuid, jsonb) to service_role;
