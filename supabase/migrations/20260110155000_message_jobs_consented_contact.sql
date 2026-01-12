alter table public.message_jobs
add column if not exists consented_contact_id uuid
  references public.consented_contacts on delete set null;

create index if not exists idx_message_jobs_consented_contact
on public.message_jobs (consented_contact_id);
