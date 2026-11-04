-- Manual deployment step after media-worker and matching secret configuration.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
do $$
begin
  if not exists(select 1 from vault.decrypted_secrets where name='project_url')
    or not exists(select 1 from vault.decrypted_secrets where name='media_worker_secret') then
    raise exception 'Configure project_url and media_worker_secret in Vault first';
  end if;
end;
$$;
select cron.unschedule(jobid) from cron.job where jobname='flow-media-worker';
select cron.schedule('flow-media-worker','30 seconds',$schedule$
  select net.http_post(
    url:=(select decrypted_secret from vault.decrypted_secrets where name='project_url') || '/functions/v1/media-worker',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='media_worker_secret')),
    body:='{}'::jsonb,timeout_milliseconds:=120000);
$schedule$);
