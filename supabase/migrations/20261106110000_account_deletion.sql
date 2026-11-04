-- In-app account deletion (App Store guideline 5.1.1(v), KVKK erasure).
-- A user who is the only administrator of a business that still has other members
-- must hand over the admin role first. Businesses where the user is the only member
-- are deleted with all their data; other businesses keep their data and lose the
-- membership. `delete-account` removes stored files and the Auth user.

-- Without this, deleting any user who ever opened a conversation failed.
alter table public.conversations drop constraint if exists conversations_last_opened_by_fkey;
alter table public.conversations add constraint conversations_last_opened_by_fkey
  foreign key (last_opened_by) references auth.users(id) on delete set null;

create or replace function public.account_deletion_plan(p_user_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with mine as (
    select m.tenant_id, m.role, t.name,
      (select count(*) from public.tenant_memberships o where o.tenant_id = m.tenant_id and o.user_id <> p_user_id) as others,
      (select count(*) from public.tenant_memberships o where o.tenant_id = m.tenant_id and o.user_id <> p_user_id
        and o.role = 'admin') as other_admins
    from public.tenant_memberships m join public.tenants t on t.id = m.tenant_id
    where m.user_id = p_user_id
  )
  select jsonb_build_object(
    'blocked', coalesce((select jsonb_agg(jsonb_build_object('tenant_id', tenant_id, 'name', name) order by name)
      from mine where role = 'admin' and others > 0 and other_admins = 0), '[]'::jsonb),
    'delete_tenants', coalesce((select jsonb_agg(tenant_id) from mine where others = 0), '[]'::jsonb),
    'leave_tenants', coalesce((select jsonb_agg(tenant_id) from mine
      where others > 0 and not (role = 'admin' and other_admins = 0)), '[]'::jsonb));
$$;

-- The signed-in user's own plan, shown before they confirm.
create or replace function public.my_account_deletion_plan()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  return public.account_deletion_plan(auth.uid());
end;
$$;

-- Service-only. Re-checks the plan in the same transaction, deletes sole-member
-- businesses and audits departures. The caller then deletes the Auth user, which
-- cascades memberships and the profile and nulls actor references.
create or replace function public.delete_account_data(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare plan jsonb; tenant uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  -- Serialize with membership changes in the affected businesses.
  perform 1 from public.tenants t join public.tenant_memberships m on m.tenant_id = t.id
    where m.user_id = p_user_id order by t.id for update of t;
  plan := public.account_deletion_plan(p_user_id);
  if jsonb_array_length(plan->'blocked') > 0 then
    raise exception 'Transfer the administrator role first' using errcode = 'P0014';
  end if;
  for tenant in select jsonb_array_elements_text(plan->'leave_tenants')::uuid loop
    insert into public.tenant_audit_events(tenant_id, actor_id, action, details)
      values (tenant, null, 'member.account_deleted', '{}'::jsonb);
  end loop;
  delete from public.tenants where id in (select jsonb_array_elements_text(plan->'delete_tenants')::uuid);
  return plan;
end;
$$;

revoke all on function public.account_deletion_plan(uuid) from public, anon, authenticated;
revoke all on function public.my_account_deletion_plan() from public, anon;
revoke all on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.my_account_deletion_plan() to authenticated;
grant execute on function public.account_deletion_plan(uuid) to service_role;
grant execute on function public.delete_account_data(uuid) to service_role;
