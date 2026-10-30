-- One filter contract for preview and dispatch. Invoker rights preserve contact RLS.
create or replace function public.validate_campaign_audience(p_filter jsonb)
returns void language plpgsql immutable security invoker set search_path = '' as $$
declare rule jsonb; field_name text; operator_name text; rule_value text;
begin
  if p_filter is null or jsonb_typeof(p_filter) <> 'object' then
    raise exception 'Audience filter must be an object' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_filter) k
    where k not in ('segment', 'last_contacted', 'custom')) then
    raise exception 'Unsupported audience filter key' using errcode = '22023';
  end if;
  if p_filter ? 'segment' and (jsonb_typeof(p_filter->'segment') <> 'string'
    or length(btrim(p_filter->>'segment')) not between 1 and 100) then
    raise exception 'Segment must be a nonempty tag' using errcode = '22023';
  end if;
  if p_filter ? 'last_contacted' and (jsonb_typeof(p_filter->'last_contacted') <> 'string'
    or (p_filter->>'last_contacted') !~ '^[1-9][0-9]{0,3}d$') then
    raise exception 'Last contacted must be 1d through 9999d' using errcode = '22023';
  end if;
  if p_filter ? 'custom' and jsonb_typeof(p_filter->'custom') <> 'array' then
    raise exception 'Custom filters must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(p_filter->'custom', '[]'::jsonb)) > 20 then
    raise exception 'At most 20 custom filters are supported' using errcode = '22023';
  end if;
  for rule in select value from jsonb_array_elements(coalesce(p_filter->'custom', '[]'::jsonb)) loop
    if jsonb_typeof(rule) <> 'object' then
      raise exception 'Custom rule must be an object' using errcode = '22023';
    end if;
    if not (rule ?& array['field', 'operator', 'value']) or exists (
      select 1 from jsonb_object_keys(rule) k where k not in ('field','operator','value')
    ) then
      raise exception 'Custom rule requires field, operator and value only' using errcode = '22023';
    end if;
    if jsonb_typeof(rule->'field') <> 'string' or jsonb_typeof(rule->'operator') <> 'string'
      or jsonb_typeof(rule->'value') <> 'string' then
      raise exception 'Custom rule values must be strings' using errcode = '22023';
    end if;
    field_name := rule->>'field'; operator_name := rule->>'operator';
    rule_value := btrim(rule->>'value');
    if length(rule_value) not between 1 and 200 then
      raise exception 'Custom value must contain 1 to 200 characters' using errcode = '22023';
    end if;
    if field_name = 'Etiket' then
      if operator_name not in ('icerir', '=') then
        raise exception 'Tag supports contains or equals only' using errcode = '22023';
      end if;
    elsif field_name = 'Son iletisim' then
      if operator_name not in ('>', '<', '=') or rule_value !~ '^[1-9][0-9]{0,3}( gun)?$' then
        raise exception 'Last contact requires a day count and >, < or =' using errcode = '22023';
      end if;
    else
      -- Country/order count are not present in the contact schema. Never ignore them.
      raise exception 'Unsupported contact field: %', field_name using errcode = '22023';
    end if;
  end loop;
end;
$$;

create or replace function public.campaign_audience(
  p_tenant_id uuid, p_filter jsonb default '{}'::jsonb
) returns setof public.consented_contacts
language plpgsql stable security invoker set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role'
    and not coalesce(public.user_has_permission(p_tenant_id, 'campaigns'), false) then
    raise exception 'Campaign permission required' using errcode = '42501';
  end if;
  perform public.validate_campaign_audience(p_filter);
  return query
  select c.* from public.consented_contacts c
  where c.tenant_id = p_tenant_id
    and (not (p_filter ? 'segment') or btrim(p_filter->>'segment') = any(c.tags))
    and (not (p_filter ? 'last_contacted') or c.last_contacted_at >=
      now() - make_interval(days => rtrim(p_filter->>'last_contacted', 'd')::int))
    and not exists (
      select 1 from jsonb_array_elements(coalesce(p_filter->'custom', '[]'::jsonb)) r
      where not coalesce(case r->>'field'
        when 'Etiket' then btrim(r->>'value') = any(c.tags)
        when 'Son iletisim' then
          case r->>'operator'
            when '>' then c.last_contacted_at < now() - make_interval(days => split_part(btrim(r->>'value'), ' ', 1)::int)
            when '<' then c.last_contacted_at >= now() - make_interval(days => split_part(btrim(r->>'value'), ' ', 1)::int)
            when '=' then floor(extract(epoch from (now() - c.last_contacted_at)) / 86400) = split_part(btrim(r->>'value'), ' ', 1)::int
          end
        else false end, false)
    )
  order by c.id;
end;
$$;

create or replace function public.count_campaign_audience(p_tenant_id uuid, p_filter jsonb default '{}'::jsonb)
returns bigint language sql stable security invoker set search_path = '' as $$
  select count(*) from public.campaign_audience(p_tenant_id, p_filter);
$$;

revoke all on function public.validate_campaign_audience(jsonb) from public, anon;
revoke all on function public.campaign_audience(uuid, jsonb) from public, anon;
revoke all on function public.count_campaign_audience(uuid, jsonb) from public, anon;
grant execute on function public.validate_campaign_audience(jsonb) to authenticated, service_role;
grant execute on function public.campaign_audience(uuid, jsonb) to authenticated, service_role;
grant execute on function public.count_campaign_audience(uuid, jsonb) to authenticated, service_role;
