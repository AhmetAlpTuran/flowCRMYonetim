-- Seed tenants
insert into public.tenants (id, name, brand_color, features, is_public)
values
  ('11111111-1111-1111-1111-111111111111', 'Flow CRM', '#1F4B99', array['dashboard','bot','knowledge','inbox','handoff','custom','campaigns','templates','users'], true),
  ('22222222-2222-2222-2222-222222222222', 'Atlas Destek', '#00A896', array['dashboard','inbox','handoff','campaigns','templates','users'], true),
  ('33333333-3333-3333-3333-333333333333', 'Nimbus Support', '#F2A541', array['dashboard','bot','inbox','campaigns','templates','users'], true);

-- Seed contacts (for Flow CRM)
insert into public.contacts (tenant_id, full_name, phone, email, tags, last_contacted_at)
values
  ('11111111-1111-1111-1111-111111111111', 'Acme Co.', '+905000000001', 'billing@acme.co', array['VIP','Faturalama'], now() - interval '2 days'),
  ('11111111-1111-1111-1111-111111111111', 'Maria Lopez', '+905000000002', 'maria@example.com', array['Hata','Cozuldu'], now() - interval '5 days'),
  ('11111111-1111-1111-1111-111111111111', 'Globex Support', '+905000000003', 'globex@example.com', array['Satis','Acil'], now() - interval '10 days');

-- Seed KVKK consented contacts (for campaigns)
insert into public.consented_contacts (tenant_id, full_name, phone, tags, last_contacted_at)
values
  ('11111111-1111-1111-1111-111111111111', 'Test Kullanici', '+905533440854', array['VIP'], now() - interval '1 day');

-- Seed conversations
insert into public.conversations (id, tenant_id, contact_id, title, last_message, status, tags, unread_count, updated_at)
values
  ('aaaaaaa1-aaaa-aaaa-aaaa-aaaaaaaaaaa1', '11111111-1111-1111-1111-111111111111', (select id from public.contacts where full_name = 'Acme Co.' limit 1), 'Acme Co.', 'Faturalama e-postamizi guncelleyebilir miyiz?', 'open', array['VIP','Faturalama'], 2, now() - interval '1 hour'),
  ('aaaaaaa2-aaaa-aaaa-aaaa-aaaaaaaaaaa2', '11111111-1111-1111-1111-111111111111', (select id from public.contacts where full_name = 'Maria Lopez' limit 1), 'Maria Lopez', 'Tesekkurler, bot cozdu!', 'closed', array['Hata','Cozuldu'], 0, now() - interval '6 hours'),
  ('aaaaaaa3-aaaa-aaaa-aaaa-aaaaaaaaaaa3', '11111111-1111-1111-1111-111111111111', (select id from public.contacts where full_name = 'Globex Support' limit 1), 'Globex Support', 'Satis ekibine yonlendirme gerekiyor.', 'handoff', array['Satis','Acil'], 1, now() - interval '1 day');

-- Seed messages
insert into public.messages (tenant_id, conversation_id, sender, body, is_from_customer, sent_at)
values
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaa1-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'Acme Co.', 'Faturalama e-postamizi guncelleyebilir miyiz?', true, now() - interval '2 hours'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaa1-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'Ava (Bot)', 'Tabii! Yeni adresi paylasir misiniz?', false, now() - interval '1 hour 45 minutes'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaa1-aaaa-aaaa-aaaa-aaaaaaaaaaa1', 'Acme Co.', 'billing@acme.co kullanin.', true, now() - interval '1 hour'),
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaa2-aaaa-aaaa-aaaa-aaaaaaaaaaa2', 'Maria Lopez', 'Tesekkurler, bot cozdu!', true, now() - interval '6 hours');

-- Seed templates
insert into public.templates (tenant_id, name, category, language, status, components)
values
  ('11111111-1111-1111-1111-111111111111', 'Kampanya Duyurusu', 'MARKETING', 'tr', 'Onaylandi', '{"body":"Merhaba {{1}}, yeni kampanyamiz basladi!"}'),
  ('11111111-1111-1111-1111-111111111111', 'Sepet Hatirlatma', 'MARKETING', 'tr', 'Onaylandi', '{"body":"Merhaba {{1}}, sepetinizdeki urunler sizi bekliyor."}');

-- Seed campaigns
insert into public.campaigns (tenant_id, name, audience_filter, template_id, status)
values
  ('11111111-1111-1111-1111-111111111111', 'Yaz Indirimi', '{"segment":"VIP","last_contacted":"7d"}', (select id from public.templates where name = 'Kampanya Duyurusu' limit 1), 'draft');

-- Seed bot settings
insert into public.bot_settings (tenant_id, name, tone, language, system_prompt, model, temperature, memory_hours, max_history_messages, is_active)
values
  ('11111111-1111-1111-1111-111111111111', 'Ava', 'Profesyonel ve net', 'Turkce', 'Kisa, profesyonel bir musteri temsilcisi gibi yanit ver.', 'gpt-4o-mini', 0.3, 6, 12, true);

-- Seed knowledge base
insert into public.knowledge_base (tenant_id, title, content, tags)
values
  ('11111111-1111-1111-1111-111111111111', 'Faturalama Guncelleme', 'Fatura bilgilerini guncellemek icin destek@flowcrm.com adresine e-posta gonderin.', array['Faturalama']),
  ('11111111-1111-1111-1111-111111111111', 'Iade Politikasi', 'Iade talepleri 14 gun icinde kabul edilir. Onay icin siparis numarasini isteyin.', array['Iade','VIP']),
  ('11111111-1111-1111-1111-111111111111', 'Teknik Destek', 'Teknik sorunlarda ekran goruntusu ve kullanici bilgisi isteyin.', array['Hata','Acil']);
