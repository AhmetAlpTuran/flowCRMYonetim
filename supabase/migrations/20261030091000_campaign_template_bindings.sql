-- Campaign-specific send values are separate from Meta's creation definitions.
-- Full shape and definition matching are validated again by the server at dispatch.
alter table public.campaigns
  add column template_bindings jsonb not null default '{}'::jsonb,
  add constraint campaigns_template_bindings_object check (
    jsonb_typeof(template_bindings) = 'object'
    and octet_length(template_bindings::text) <= 65536
  );

comment on column public.campaigns.template_bindings is
  'Send-time values keyed by header/body variable or button index; validated against the approved template. Never creation examples.';
