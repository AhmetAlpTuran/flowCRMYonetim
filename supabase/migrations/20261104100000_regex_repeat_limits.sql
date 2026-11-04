-- PostgreSQL regular expressions reject repetition counts above 255
-- (RE_DUP_MAX), so '{1,512}' and '{1,506}' raised "invalid repetition count(s)"
-- at runtime: template sync failed for every page and accepted inbox/bot sends
-- could never be finalized. Found by the first execution of supabase/tests.
-- Same limits, expressed as an unbounded class plus an explicit length check.
-- Definitions are otherwise identical to the latest versions; grants are kept
-- by CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.apply_whatsapp_template_page(p_tenant_id uuid, p_actor_id uuid, p_connection_id uuid, p_templates jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
      or coalesce(item->>'name', '') !~ '^[a-z0-9_]+$' or length(item->>'name') > 512
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
$function$
;

CREATE OR REPLACE FUNCTION public.finish_inbox_dispatch(p_dispatch_id uuid, p_lease_token uuid, p_outcome text, p_provider_message_id text DEFAULT NULL::text, p_error_code text DEFAULT NULL::text, p_retry_after_seconds integer DEFAULT 0)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare job public.inbox_dispatches;
begin
  perform public.require_service_role();
  if p_outcome is null or p_outcome not in ('accepted', 'failed', 'retry', 'unknown') then
    raise exception 'Invalid dispatch outcome' using errcode = '22023';
  end if;
  if p_outcome = 'accepted' and (p_provider_message_id is null or p_provider_message_id !~ '^wamid\.[^[:space:]]+$' or length(p_provider_message_id) > 512) then
    raise exception 'Provider message ID required' using errcode = '22023';
  end if;
  select * into job from public.inbox_dispatches where id = p_dispatch_id for update;
  if not found or job.lease_token is distinct from p_lease_token then return false; end if;
  if job.state = 'accepted' and p_outcome = 'accepted' and job.provider_message_id = p_provider_message_id then return true; end if;
  if job.state not in ('sending', 'unknown') then return false; end if;
  update public.inbox_dispatches set
    state = case when p_outcome = 'retry' then case when attempts < 5 then 'retry_wait' else 'failed' end else p_outcome end,
    available_at = case when p_outcome = 'retry' then now() + make_interval(secs =>
      greatest(least(coalesce(p_retry_after_seconds, 0), 3600), least(3600, (30 * power(2, greatest(attempts - 1, 0)))::int)))
      else available_at end,
    provider_message_id = case when p_outcome = 'accepted' then p_provider_message_id else null end,
    accepted_at = case when p_outcome = 'accepted' then clock_timestamp() else null end,
    error_code = case when p_outcome = 'accepted' then null else left(p_error_code, 100) end,
    leased_until = null, updated_at = now() where id = job.id;
  return true;
end;
$function$
;
