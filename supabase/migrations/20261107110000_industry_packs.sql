-- Industry packs: one-step setup for common businesses. A pack adds its catalog
-- types, a tailored bot prompt and knowledge entries written from the owner's own
-- answers (empty answers are skipped, so the bot never quotes placeholders).
-- Re-applying updates the pack's entries; a custom bot prompt is never overwritten
-- and the bot is never switched on automatically.

create or replace function public.industry_pack_definition(p_pack text)
returns jsonb language sql immutable set search_path = '' as $$
  select case p_pack
  when 'rental' then jsonb_build_object(
    'name', 'Konaklama ve kiralama',
    'tone', 'Sıcak, misafirperver ve net',
    'prompt', 'Bu işletmenin rezervasyon asistanısın. Müşterilere konaklama seçenekleri, fiyatlar ve müsaitlik konusunda yardım et. Oda, fiyat ve müsaitlik için her zaman katalog araçlarını kullan; katalogda olmayan oda veya fiyat söyleme. Rezervasyon için giriş ve çıkış tarihlerini ve kişi sayısını sor, uygun odayı öner, ön rezervasyon yap, toplam tutarı ve ön rezervasyonun 15 dakika geçerli olduğunu söyle ve müşteriden açık onay iste. Ödeme, kapora ve iptal konularında yalnızca işletme bilgilerindeki kuralları kullan; bilgi yoksa müşteriyi bir temsilciye yönlendir. İndirim veya özel fiyat sözü verme.',
    'types', jsonb_build_array(jsonb_build_object('key', 'room', 'name', 'Oda', 'kind', 'bookable', 'booking_unit', 'night',
      'fields', jsonb_build_array(
        jsonb_build_object('key', 'beds', 'label', 'Yatak sayısı', 'type', 'number', 'filterable', true),
        jsonb_build_object('key', 'view', 'label', 'Manzara', 'type', 'select', 'options', jsonb_build_array('Deniz', 'Bahçe', 'Şehir', 'Dağ')),
        jsonb_build_object('key', 'breakfast', 'label', 'Kahvaltı dahil', 'type', 'boolean')))),
    'questions', jsonb_build_array(
      jsonb_build_object('key', 'checkin', 'title', 'Giriş ve çıkış saatleri'),
      jsonb_build_object('key', 'address', 'title', 'Adres ve ulaşım'),
      jsonb_build_object('key', 'payment', 'title', 'Ödeme ve kapora'),
      jsonb_build_object('key', 'cancellation', 'title', 'İptal ve değişiklik koşulları'),
      jsonb_build_object('key', 'amenities', 'title', 'Olanaklar ve tesis kuralları')))
  when 'auto_dealer' then jsonb_build_object(
    'name', 'Oto galeri',
    'tone', 'Güven veren, samimi ve net',
    'prompt', 'Bu oto galerinin satış danışmanısın. Araç sorularında her zaman katalog araçlarıyla ara ve yalnızca katalogdaki araçların marka, model, yıl, kilometre, yakıt, vites ve fiyat bilgilerini paylaş; stokta olmayan bir aracı varmış gibi anlatma. Müşterinin bütçesini ve tercihlerini (vites, yakıt, yıl) sorarak uygun araçları öner. Test sürüşü, takas, kredi veya geri arama taleplerini talep kaydı olarak oluştur ve ekibin müşteriyle iletişime geçeceğini söyle. Pazarlık yapma, indirim veya fiyat sözü verme; ekspertiz, garanti ve kredi şartları için yalnızca işletme bilgilerini kullan, bilgi yoksa temsilciye yönlendir.',
    'types', jsonb_build_array(jsonb_build_object('key', 'vehicle', 'name', 'Araç', 'kind', 'listing', 'booking_unit', null,
      'fields', jsonb_build_array(
        jsonb_build_object('key', 'brand', 'label', 'Marka', 'type', 'text', 'filterable', true),
        jsonb_build_object('key', 'model', 'label', 'Model', 'type', 'text', 'filterable', true),
        jsonb_build_object('key', 'year', 'label', 'Yıl', 'type', 'number', 'filterable', true),
        jsonb_build_object('key', 'km', 'label', 'Kilometre', 'type', 'number', 'filterable', true),
        jsonb_build_object('key', 'fuel', 'label', 'Yakıt', 'type', 'select', 'options', jsonb_build_array('Benzin', 'Dizel', 'LPG', 'Hibrit', 'Elektrik'), 'filterable', true),
        jsonb_build_object('key', 'gear', 'label', 'Vites', 'type', 'select', 'options', jsonb_build_array('Manuel', 'Otomatik'), 'filterable', true),
        jsonb_build_object('key', 'color', 'label', 'Renk', 'type', 'text')))),
    'questions', jsonb_build_array(
      jsonb_build_object('key', 'address', 'title', 'Adres ve çalışma saatleri'),
      jsonb_build_object('key', 'test_drive', 'title', 'Test sürüşü koşulları'),
      jsonb_build_object('key', 'financing', 'title', 'Kredi ve taksit seçenekleri'),
      jsonb_build_object('key', 'trade_in', 'title', 'Takas'),
      jsonb_build_object('key', 'warranty', 'title', 'Ekspertiz ve garanti')))
  when 'appointments' then jsonb_build_object(
    'name', 'Randevulu hizmet',
    'tone', 'Nazik, düzenli ve net',
    'prompt', 'Bu işletmenin randevu asistanısın. Müşterilere hizmetler, fiyatlar ve uygun saatler konusunda yardım et. Hizmet ve uygunluk için katalog araçlarını kullan. Randevu için gün ve saat tercihini sor, uygunluğu kontrol et, ön randevu oluştur ve müşteriden açık onay iste. Fiyat, iptal ve hazırlık konularında yalnızca işletme bilgilerini kullan. Tıbbi, hukuki veya kişiye özel tavsiye verme; bu tür sorularda müşteriyi bir uzmana veya temsilciye yönlendir.',
    'types', jsonb_build_array(jsonb_build_object('key', 'service', 'name', 'Hizmet', 'kind', 'bookable', 'booking_unit', 'hour',
      'fields', jsonb_build_array(jsonb_build_object('key', 'staff', 'label', 'Uzman', 'type', 'text')))),
    'questions', jsonb_build_array(
      jsonb_build_object('key', 'address', 'title', 'Adres ve çalışma saatleri'),
      jsonb_build_object('key', 'services', 'title', 'Hizmetler ve fiyatlar'),
      jsonb_build_object('key', 'cancellation', 'title', 'Randevu iptali ve değişiklik'),
      jsonb_build_object('key', 'preparation', 'title', 'Randevu öncesi bilgiler')))
  end;
$$;

-- Lets the app show each pack's questions without duplicating them.
create or replace function public.industry_packs()
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_agg(jsonb_build_object('key', k, 'name', d->'name', 'questions', d->'questions') order by o)
  from (values ('rental', 1), ('auto_dealer', 2), ('appointments', 3)) as p(k, o),
    lateral (select public.industry_pack_definition(k) as d) x;
$$;

create or replace function public.apply_industry_pack(p_tenant_id uuid, p_pack text, p_answers jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_def jsonb := public.industry_pack_definition(p_pack);
  v_answers jsonb := coalesce(p_answers, '{}');
  v_type jsonb; v_question jsonb; v_text text; v_existing uuid;
  v_settings public.bot_settings;
  v_types_added integer := 0; v_added integer := 0; v_updated integer := 0; v_prompt_applied boolean := false;
  v_default_prompt constant text := 'Kisa, profesyonel bir musteri temsilcisi gibi yanit ver.';
begin
  if auth.uid() is null or not public.is_tenant_admin(p_tenant_id) then
    raise exception 'Tenant administrator required' using errcode = '42501';
  end if;
  if v_def is null then raise exception 'Unknown industry pack' using errcode = '22023'; end if;
  if jsonb_typeof(v_answers) <> 'object' or octet_length(v_answers::text) > 32768 then
    raise exception 'Answers must be an object' using errcode = '22023';
  end if;

  for v_type in select value from jsonb_array_elements(v_def->'types') loop
    if not exists (select 1 from public.resource_types where tenant_id = p_tenant_id and key = v_type->>'key') then
      insert into public.resource_types(tenant_id, key, name, kind, booking_unit, fields)
        values (p_tenant_id, v_type->>'key', v_type->>'name', v_type->>'kind', v_type->>'booking_unit', v_type->'fields');
      v_types_added := v_types_added + 1;
    end if;
  end loop;

  for v_question in select value from jsonb_array_elements(v_def->'questions') loop
    v_text := left(btrim(coalesce(v_answers->>(v_question->>'key'), '')), 4000);
    continue when v_text = '';
    select id into v_existing from public.knowledge_base
      where tenant_id = p_tenant_id and title = v_question->>'title' order by created_at limit 1;
    if v_existing is null then
      insert into public.knowledge_base(tenant_id, title, content, tags)
        values (p_tenant_id, v_question->>'title', v_text, array['paket:' || p_pack]);
      v_added := v_added + 1;
    else
      update public.knowledge_base set content = v_text, updated_at = now()
        where id = v_existing and content is distinct from v_text;
      if found then v_updated := v_updated + 1; end if;
    end if;
  end loop;

  select * into v_settings from public.bot_settings where tenant_id = p_tenant_id for update;
  if not found then
    insert into public.bot_settings(tenant_id, tone, system_prompt, is_active)
      values (p_tenant_id, v_def->>'tone', v_def->>'prompt', false);
    v_prompt_applied := true;
  elsif v_settings.system_prompt = v_default_prompt
    or v_settings.system_prompt in (select public.industry_pack_definition(k)->>'prompt'
      from unnest(array['rental', 'auto_dealer', 'appointments']) k) then
    update public.bot_settings set tone = v_def->>'tone', system_prompt = v_def->>'prompt', updated_at = now()
      where tenant_id = p_tenant_id and system_prompt is distinct from v_def->>'prompt';
    v_prompt_applied := true;
  end if;

  insert into public.tenant_audit_events(tenant_id, actor_id, action, details)
    values (p_tenant_id, auth.uid(), 'industry_pack.applied', jsonb_build_object('pack', p_pack));
  return jsonb_build_object('types_added', v_types_added, 'knowledge_added', v_added,
    'knowledge_updated', v_updated, 'prompt_applied', v_prompt_applied,
    'bot_active', coalesce((select is_active from public.bot_settings where tenant_id = p_tenant_id), false));
end;
$$;

revoke all on function public.industry_pack_definition(text) from public, anon;
revoke all on function public.apply_industry_pack(uuid, text, jsonb) from public, anon;
grant execute on function public.industry_packs() to authenticated;
grant execute on function public.apply_industry_pack(uuid, text, jsonb) to authenticated;
