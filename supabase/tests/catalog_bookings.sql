-- Catalog validation, booking overlap guarantee, holds, bot scoping, leads. Rolls back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare t uuid := gen_random_uuid(); other uuid := gen_random_uuid(); agent uuid := gen_random_uuid();
  outsider uuid := gen_random_uuid(); room_type uuid; car_type uuid; room uuid; room2 uuid; car uuid; car2 uuid;
  conv uuid := gen_random_uuid(); conv2 uuid := gen_random_uuid(); other_conv uuid := gen_random_uuid();
  conn uuid := gen_random_uuid(); other_conn uuid := gen_random_uuid();
  day0 timestamptz := date_trunc('day', now()) + interval '10 days 14 hours';
  hold jsonb; again jsonb; found_items jsonb; avail jsonb; lead jsonb;
begin
  insert into public.tenants(id, name) values (t, 'Catalog A'), (other, 'Catalog B');
  insert into auth.users(id, email) values (agent, 'agent-' || agent || '@example.invalid'),
    (outsider, 'outsider-' || outsider || '@example.invalid');
  insert into public.tenant_memberships(tenant_id, user_id, role, permissions) values
    (t, agent, 'user', array['catalog']), (t, outsider, 'user', array['inbox']);
  insert into public.whatsapp_connections(id, tenant_id, waba_id, phone_number_id, display_phone_number, status, verified_at)
    values (conn, t, '960000000001', '960000000002', 'fixture', 'active', now()),
           (other_conn, other, '960000000003', '960000000004', 'fixture', 'active', now());
  insert into public.conversations(id, tenant_id, title, status, connection_id, customer_phone) values
    (conv, t, 'Kiralama', 'open', conn, '905556660001'), (conv2, t, 'Diger', 'open', conn, '905556660002');
  insert into public.conversations(id, tenant_id, title, status, connection_id, customer_phone)
    values (other_conv, other, 'B', 'open', other_conn, '905556660003');

  begin
    insert into public.resource_types(tenant_id, key, name, kind, booking_unit, fields)
      values (t, 'bad', 'Bad', 'listing', null, '[{"key":"Bad Key","label":"x","type":"text"}]');
    raise exception 'Invalid field key accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.resource_types(tenant_id, key, name, kind, booking_unit) values (t, 'nounit', 'No unit', 'bookable', null);
    raise exception 'Bookable type without unit accepted';
  exception when check_violation then null;
  end;
  insert into public.resource_types(tenant_id, key, name, kind, booking_unit, fields) values
    (t, 'room', 'Oda', 'bookable', 'night', '[{"key":"beds","label":"Yatak","type":"number","filterable":true},{"key":"view","label":"Manzara","type":"select","options":["deniz","bahce"]}]')
    returning id into room_type;
  insert into public.resource_types(tenant_id, key, name, kind, fields) values
    (t, 'vehicle', 'Araç', 'listing', '[{"key":"brand","label":"Marka","type":"text"},{"key":"year","label":"Yıl","type":"number"},{"key":"km","label":"Km","type":"number"},{"key":"gear","label":"Vites","type":"select","options":["manuel","otomatik"]}]')
    returning id into car_type;
  insert into public.resources(tenant_id, type_id, name, price, capacity, attributes)
    values (t, room_type, 'Deniz Manzaralı Oda', 2500, 2, '{"beds":2,"view":"deniz"}') returning id into room;
  insert into public.resources(tenant_id, type_id, name, price, capacity, attributes)
    values (t, room_type, 'Bahçe Oda', 1800, 3, '{"beds":3,"view":"bahce"}') returning id into room2;
  insert into public.resources(tenant_id, type_id, name, price, attributes)
    values (t, car_type, '2019 Fiat Egea', 650000, '{"brand":"Fiat","year":2019,"km":82000,"gear":"manuel"}') returning id into car;
  insert into public.resources(tenant_id, type_id, name, price, attributes)
    values (t, car_type, '2021 Toyota Corolla', 1150000, '{"brand":"Toyota","year":2021,"km":40000,"gear":"otomatik"}') returning id into car2;
  begin
    insert into public.resources(tenant_id, type_id, name, attributes) values (t, room_type, 'X', '{"beds":"two"}');
    raise exception 'Wrong attribute type accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    insert into public.resources(tenant_id, type_id, name, attributes) values (t, room_type, 'X', '{"view":"dag"}');
    raise exception 'Unknown select option accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    insert into public.resources(tenant_id, type_id, name, attributes) values (t, room_type, 'X', '{"pool":true}');
    raise exception 'Unknown attribute accepted';
  exception when sqlstate '22023' then null;
  end;

  -- Bot search: type, numeric range, select value (case-insensitive), price range.
  found_items := public.bot_search_resources(t, 'vehicle', null, '{"gear":"Otomatik","year":{"min":2020}}');
  if jsonb_array_length(found_items) <> 1 or found_items->0->>'name' <> '2021 Toyota Corolla' then
    raise exception 'Vehicle filter wrong: %', found_items;
  end if;
  found_items := public.bot_search_resources(t, null, null, '{"price":{"max":2000}}');
  if jsonb_array_length(found_items) <> 1 or found_items->0->>'name' <> 'Bahçe Oda' then
    raise exception 'Price filter wrong: %', found_items;
  end if;
  if jsonb_array_length(public.bot_search_resources(other, null, null, '{}')) <> 0 then
    raise exception 'Search crossed tenants';
  end if;

  -- Holds: phone from the conversation; idempotent; overlap refused; adjacency allowed.
  hold := public.bot_create_booking_hold(t, conv, room, day0, day0 + interval '2 days', 'Ayşe', 'job1:call1');
  again := public.bot_create_booking_hold(t, conv, room, day0, day0 + interval '2 days', 'Ayşe', 'job1:call1');
  if hold->>'booking_id' <> again->>'booking_id' or hold->>'status' <> 'hold' then raise exception 'Hold not idempotent'; end if;
  if (select customer_phone from public.bookings where id = (hold->>'booking_id')::uuid) <> '905556660001' then
    raise exception 'Hold did not take the conversation phone';
  end if;
  begin
    perform public.bot_create_booking_hold(t, conv2, room, day0 + interval '1 day', day0 + interval '3 days', 'Mehmet', 'job2:call1');
    raise exception 'Overlapping hold accepted';
  exception when sqlstate 'P0015' then null;
  end;
  perform public.bot_create_booking_hold(t, conv2, room, day0 + interval '2 days', day0 + interval '4 days', 'Mehmet', 'job2:call2');
  avail := public.bot_check_availability(t, room, day0 + interval '1 day', day0 + interval '2 days');
  if (avail->>'available')::boolean then raise exception 'Held night shown as available'; end if;
  avail := public.bot_check_availability(t, room, day0 + interval '5 days', day0 + interval '6 days');
  if not (avail->>'available')::boolean then raise exception 'Free night shown as busy'; end if;
  begin
    perform public.bot_check_availability(t, car, day0, day0 + interval '1 day');
    raise exception 'Listing treated as bookable';
  exception when sqlstate 'P0002' then null;
  end;

  -- Another conversation cannot confirm this hold; the owner can; reuse of a key elsewhere fails.
  begin
    perform public.bot_set_booking_status(t, conv2, (hold->>'booking_id')::uuid, 'confirmed');
    raise exception 'Other conversation confirmed the hold';
  exception when sqlstate 'P0002' then null;
  end;
  begin
    perform public.bot_create_booking_hold(t, conv2, room, day0, day0 + interval '2 days', 'X', 'job1:call1');
    raise exception 'Request key reused across conversations';
  exception when insufficient_privilege then null;
  end;
  if public.bot_set_booking_status(t, conv, (hold->>'booking_id')::uuid, 'confirmed')->>'status' <> 'confirmed' then
    raise exception 'Owner could not confirm';
  end if;

  -- Expired holds stop blocking and cannot be confirmed.
  hold := public.bot_create_booking_hold(t, conv, room2, day0, day0 + interval '1 day', 'Ali', 'job3:call1');
  update public.bookings set hold_expires_at = now() - interval '1 second' where id = (hold->>'booking_id')::uuid;
  begin
    perform public.bot_set_booking_status(t, conv, (hold->>'booking_id')::uuid, 'confirmed');
    raise exception 'Expired hold confirmed';
  exception when sqlstate 'P0016' then null;
  end;
  perform public.bot_create_booking_hold(t, conv2, room2, day0, day0 + interval '1 day', 'Veli', 'job4:call1');

  -- Leads: idempotent, conversation phone, resource scoped to tenant.
  lead := public.bot_create_lead(t, conv, 'test_drive', car2, '{"note":"Cumartesi öğleden sonra"}', day0, 'Ayşe', 'job5:call1');
  if lead->>'lead_id' <> (public.bot_create_lead(t, conv, 'test_drive', car2, '{}', null, null, 'job5:call1'))->>'lead_id' then
    raise exception 'Lead not idempotent';
  end if;
  if (select customer_phone from public.leads where id = (lead->>'lead_id')::uuid) <> '905556660001' then
    raise exception 'Lead did not take the conversation phone';
  end if;
  begin
    perform public.bot_create_lead(t, other_conv, 'inquiry', null, '{}', null, null, 'job6:call1');
    raise exception 'Lead created for another tenant conversation';
  exception when sqlstate 'P0002' then null;
  end;

  perform set_config('test.tenant', t::text, true);
  perform set_config('test.agent', agent::text, true);
  perform set_config('test.outsider', outsider::text, true);
  perform set_config('test.room', room::text, true);
  perform set_config('test.day0', day0::text, true);
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.agent'))::text, true);
do $$
declare t uuid := current_setting('test.tenant')::uuid; room uuid := current_setting('test.room')::uuid;
  day0 timestamptz := current_setting('test.day0')::timestamptz; b uuid; b2 uuid;
begin
  if (select count(*) from public.bookings where tenant_id = t) < 3 then raise exception 'Agent cannot read bookings'; end if;
  begin
    insert into public.bookings(tenant_id, resource_id, period, status, source)
      values (t, room, tstzrange(day0 + interval '20 days', day0 + interval '21 days'), 'confirmed', 'agent');
    raise exception 'Direct booking insert allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.create_booking(t, room, day0 + interval '1 day', day0 + interval '2 days', 'X');
    raise exception 'Agent overlapped a confirmed booking';
  exception when sqlstate 'P0015' then null;
  end;
  b := public.create_booking(t, room, day0 + interval '10 days', day0 + interval '12 days', 'Telefon rezervasyonu',
    '0555 666 00 09', null, 'agent-req-1');
  b2 := public.create_booking(t, room, day0 + interval '10 days', day0 + interval '12 days', 'Telefon rezervasyonu',
    '0555 666 00 09', null, 'agent-req-1');
  if b <> b2 then raise exception 'Agent booking retry duplicated'; end if;
  if (select customer_phone from public.bookings where id = b) <> '905556660009' then raise exception 'Agent phone not normalized'; end if;
  if public.set_booking_status(t, b, 'cancelled') <> 'cancelled' then raise exception 'Cancel failed'; end if;
  perform public.create_booking(t, room, day0 + interval '10 days', day0 + interval '11 days', 'Yeni');
  begin
    perform public.bot_search_resources(t);
    raise exception 'Client called a bot function';
  exception when insufficient_privilege then null;
  end;
end;
$$;
select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', current_setting('test.outsider'))::text, true);
do $$
begin
  if exists (select 1 from public.resources where tenant_id = current_setting('test.tenant')::uuid)
    or exists (select 1 from public.bookings where tenant_id = current_setting('test.tenant')::uuid) then
    raise exception 'Member without catalog permission sees catalog data';
  end if;
  begin
    perform public.create_booking(current_setting('test.tenant')::uuid, current_setting('test.room')::uuid, now() + interval '30 days', now() + interval '31 days');
    raise exception 'Member without catalog permission booked';
  exception when insufficient_privilege then null;
  end;
end;
$$;
rollback;
