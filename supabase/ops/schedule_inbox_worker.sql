-- Apply manually after deploying inbox-worker and configuring matching secrets.
-- This file is not an automatic migration and contains no plaintext secret values.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'project_url')
    or not exists (select 1 from vault.decrypted_secrets where name = 'inbox_worker_secret') then
    raise exception 'Configure project_url and inbox_worker_secret in Vault first';
  end if;
end;
$$;
-- Re-running setup replaces this one named schedule, not other application jobs.
select cron.unschedule(jobid) from cron.job where jobname = 'flow-inbox-worker';
select cron.schedule('flow-inbox-worker', '10 seconds', $schedule$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/inbox-worker',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'inbox_worker_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 140000
  );
$schedule$);
