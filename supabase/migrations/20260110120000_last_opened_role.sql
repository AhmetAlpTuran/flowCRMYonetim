alter table public.conversations
add column if not exists last_opened_role text;
