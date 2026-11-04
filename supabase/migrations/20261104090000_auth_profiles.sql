-- Profile availability is owned by Auth transactions, independently of client routing.
create function public.sync_auth_user_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.user_profiles(id, email) values(new.id, new.email)
    on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
revoke all on function public.sync_auth_user_profile() from public, anon, authenticated;
create trigger sync_auth_user_profile after insert or update of email on auth.users
  for each row execute function public.sync_auth_user_profile();

-- Preserve existing names. Auth owns the email used for display in team screens.
insert into public.user_profiles(id, email, created_at)
  select id, email, coalesce(created_at, now()) from auth.users
  on conflict (id) do update set email = excluded.email;

revoke all on public.user_profiles from public, anon, authenticated;
grant select, update(display_name) on public.user_profiles to authenticated;
grant all on public.user_profiles to service_role;
