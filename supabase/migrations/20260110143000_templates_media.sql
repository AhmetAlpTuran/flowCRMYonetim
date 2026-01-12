alter table public.templates
add column if not exists wa_template_id text,
add column if not exists status_updated_at timestamptz;
