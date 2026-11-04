-- Authored only. Run in an isolated migrated database during verification.
begin;
do $$
declare actor uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values(actor, 'old-' || actor::text || '@example.invalid');
  if not exists(select 1 from public.user_profiles where id = actor and email = 'old-' || actor::text || '@example.invalid') then
    raise exception 'Auth insert did not create the profile';
  end if;
  update public.user_profiles set display_name = 'Preserved name' where id = actor;
  update auth.users set email = 'new-' || actor::text || '@example.invalid' where id = actor;
  if not exists(select 1 from public.user_profiles where id = actor and display_name = 'Preserved name'
    and email = 'new-' || actor::text || '@example.invalid') then raise exception 'Email sync lost profile data'; end if;
  perform set_config('test.profile_actor', actor::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.profile_actor'))::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  update public.user_profiles set display_name = 'My name' where id = auth.uid();
  if not exists(select 1 from public.user_profiles where id = auth.uid() and display_name = 'My name') then
    raise exception 'Own display name is no longer editable';
  end if;
  begin
    update public.user_profiles set email = 'forged@example.invalid' where id = auth.uid();
    raise exception 'Client forged profile email';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.user_profiles(id, email) values(auth.uid(), 'forged@example.invalid');
    raise exception 'Client inserted an Auth-owned profile';
  exception when insufficient_privilege then null; end;
end;
$$;
rollback;
