alter table public.conversations
add column if not exists last_opened_at timestamptz,
add column if not exists last_opened_by uuid references auth.users;

alter table public.messages
add column if not exists wa_message_id text,
add column if not exists wa_status text,
add column if not exists delivered_at timestamptz,
add column if not exists read_at timestamptz;

create index if not exists idx_messages_wa_message_id
on public.messages (wa_message_id);
