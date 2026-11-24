-- Add Ижавиа as a first-class Royal Alliance airline and route its Roblox Game Pass
-- purchases through a Place running inside the Ижавиа-owned Roblox Experience.

DO $migration$
DECLARE
  item record;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('rf_admin_audit','rf_admin_audit_airline_code_check'),
    ('rf_airline_memberships','rf_airline_memberships_airline_code_check'),
    ('rf_airline_staff','rf_airline_staff_airline_code_check'),
    ('rf_career_applications','rf_career_applications_airline_code_check'),
    ('rf_career_forms','rf_career_forms_airline_code_check'),
    ('rf_flights','rf_flights_airline_code_check'),
    ('rf_notifications','rf_notifications_airline_code_check'),
    ('rf_orders','rf_orders_airline_code_check'),
    ('rf_payment_methods','rf_payment_methods_airline_code_check'),
    ('rf_roblox_entitlements','rf_roblox_entitlements_airline_code_check'),
    ('rf_services','rf_services_airline_code_check'),
    ('rf_subscriptions','rf_subscriptions_airline_code_check')
  ) AS checks(table_name,constraint_name)
  LOOP
    EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT IF EXISTS %I',item.table_name,item.constraint_name);
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (airline_code IN (''royal'',''azal'',''izavia''))',
      item.table_name,item.constraint_name
    );
  END LOOP;
END;
$migration$;

INSERT INTO public.rf_settings(key,value)
VALUES ('roblox_place_ids_izavia','[]'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.rf_izavia_purchase_codes (
  code text PRIMARY KEY CHECK (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  profile_id uuid NOT NULL REFERENCES public.rf_profiles(id) ON DELETE CASCADE,
  airline_code text NOT NULL DEFAULT 'izavia' CHECK (airline_code = 'izavia'),
  service_id uuid NOT NULL,
  gamepass_id text NOT NULL CHECK (gamepass_id ~ '^[1-9][0-9]{0,19}$'),
  expires_at timestamptz NOT NULL,
  started_at timestamptz,
  started_by_roblox_user_id bigint,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (service_id,airline_code)
    REFERENCES public.rf_services(id,airline_code) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS rf_izavia_purchase_codes_profile_created_idx
  ON public.rf_izavia_purchase_codes(profile_id,created_at DESC);
CREATE INDEX IF NOT EXISTS rf_izavia_purchase_codes_open_idx
  ON public.rf_izavia_purchase_codes(expires_at) WHERE used_at IS NULL;
ALTER TABLE public.rf_izavia_purchase_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rf_izavia_purchase_codes FROM public,anon,authenticated;
GRANT ALL ON public.rf_izavia_purchase_codes TO service_role;

CREATE OR REPLACE FUNCTION public.rf_register_flight(p_flight_id uuid, p_profile_id uuid, p_airline_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_flight public.rf_flights%rowtype;
  v_existing public.rf_flight_registrations%rowtype;
  v_count integer;
  v_registration_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  if p_airline_code not in ('royal','azal','izavia') then
    raise exception 'invalid_airline' using errcode='22023';
  end if;

  select * into v_flight
  from public.rf_flights
  where id=p_flight_id and airline_code=p_airline_code
  for update;
  if not found then raise exception 'flight_not_found' using errcode='P0002'; end if;
  if v_flight.status not in ('scheduled','boarding') then
    raise exception 'registration_closed' using errcode='P0001';
  end if;
  if v_flight.departure_at<=now() then
    raise exception 'flight_already_departed' using errcode='P0001';
  end if;
  if v_flight.registration_deadline is not null and v_flight.registration_deadline<=now() then
    raise exception 'registration_deadline_passed' using errcode='P0001';
  end if;

  select * into v_existing
  from public.rf_flight_registrations
  where flight_id=p_flight_id and profile_id=p_profile_id
  for update;
  if found and v_existing.status in ('registered','checked_in') then
    return jsonb_build_object('ok',true,'already_registered',true,'registration_id',v_existing.id);
  end if;

  if v_flight.capacity is not null then
    select count(*) into v_count
    from public.rf_flight_registrations
    where flight_id=p_flight_id and airline_code=p_airline_code and status in ('registered','checked_in');
    if v_count>=v_flight.capacity then raise exception 'flight_full' using errcode='P0001'; end if;
  end if;

  if v_existing.id is not null then
    update public.rf_flight_registrations
      set status='registered',airline_code=p_airline_code,created_at=now()
      where id=v_existing.id
      returning id into v_registration_id;
  else
    insert into public.rf_flight_registrations(airline_code,flight_id,profile_id,status)
      values(p_airline_code,p_flight_id,p_profile_id,'registered')
      returning id into v_registration_id;
  end if;

  return jsonb_build_object('ok',true,'already_registered',false,'registration_id',v_registration_id);
end;
$function$
;
revoke all on function public.rf_register_flight(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.rf_register_flight(uuid,uuid,text) to service_role;

CREATE OR REPLACE FUNCTION public.rf_redeem_miles_for_service(p_profile_id uuid, p_airline_code text, p_service_id uuid, p_request_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_profile public.rf_profiles%rowtype;
  v_service public.rf_services%rowtype;
  v_order public.rf_orders%rowtype;
  v_miles_required bigint;
  v_miles_spent bigint := 0;
  v_remaining bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_subscription_id uuid;
  v_order_number text;
begin
  if current_user not in ('service_role', 'postgres') then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  if p_profile_id is null or p_airline_code not in ('royal', 'azal', 'izavia')
     or p_service_id is null or p_request_key is null then
    raise exception 'invalid_miles_redemption' using errcode = '22023';
  end if;

  select * into v_profile
  from public.rf_profiles
  where id = p_profile_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'profile_not_found');
  end if;

  -- A stable request key makes retries idempotent; the profile lock serializes
  -- simultaneous redemption attempts for the same passenger.
  select * into v_order
  from public.rf_orders
  where profile_id = p_profile_id
    and payment_provider = 'miles'
    and payment_reference = p_request_key::text;

  if found then
    select greatest(0, -delta) into v_miles_spent
    from public.rf_mile_ledger
    where source_key = 'miles_purchase:' || p_request_key::text;

    select id, ends_at into v_subscription_id, v_end
    from public.rf_subscriptions
    where source_order_id = v_order.id;

    return jsonb_build_object(
      'ok', true,
      'already_processed', true,
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'amount', v_order.amount,
      'currency', v_order.currency,
      'miles_spent', coalesce(v_miles_spent, 0),
      'remaining_miles', v_profile.miles,
      'subscription_id', v_subscription_id,
      'ends_at', v_end
    );
  end if;

  select * into v_service
  from public.rf_services
  where id = p_service_id
    and airline_code = p_airline_code
    and active = true
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'service_unavailable');
  end if;

  if upper(v_service.currency) <> 'RUB' then
    return jsonb_build_object('ok', false, 'reason', 'miles_payment_requires_rub');
  end if;

  if v_service.price <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'miles_payment_unavailable');
  end if;

  v_miles_required := ceil(v_service.price * 10)::bigint;

  if v_profile.miles < v_miles_required then
    return jsonb_build_object(
      'ok', false,
      'reason', 'insufficient_miles',
      'required_miles', v_miles_required,
      'available_miles', v_profile.miles
    );
  end if;

  v_order_number := (case when p_airline_code = 'azal' then 'AZAL-' when p_airline_code = 'izavia' then 'IZH-' else 'RF-' end)
    || 'M-' || to_char(now(), 'YYMMDD') || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.rf_orders(
    airline_code, order_number, profile_id, service_id,
    amount, currency, status, paid_at,
    payment_provider, payment_reference, user_note
  ) values (
    p_airline_code, v_order_number, p_profile_id, p_service_id,
    v_service.price, 'RUB', 'paid', now(),
    'miles', p_request_key::text,
    'Оплачено милями: ' || v_miles_required::text
  ) returning * into v_order;

  update public.rf_profiles
  set miles = miles - v_miles_required, updated_at = now()
  where id = p_profile_id
    and miles >= v_miles_required
  returning miles into v_remaining;

  if not found then
    raise exception 'insufficient_miles' using errcode = 'P0001';
  end if;

  insert into public.rf_mile_ledger(
    profile_id, delta, reason, source_key, metadata
  ) values (
    p_profile_id,
    -v_miles_required,
    'service_purchase',
    'miles_purchase:' || p_request_key::text,
    jsonb_build_object(
      'order_id', v_order.id,
      'service_id', v_service.id,
      'airline_code', p_airline_code,
      'service_price_rub', v_service.price,
      'miles_per_rub', 10
    )
  );

  select greatest(now(), coalesce(max(ends_at), now()))
  into v_start
  from public.rf_subscriptions
  where profile_id = p_profile_id
    and service_id = p_service_id
    and airline_code = p_airline_code
    and status = 'active';

  v_end := v_start + make_interval(days => v_service.duration_days);

  insert into public.rf_subscriptions(
    airline_code, profile_id, service_id, source_order_id,
    starts_at, ends_at, status
  ) values (
    p_airline_code, p_profile_id, p_service_id, v_order.id,
    v_start, v_end, 'active'
  ) returning id into v_subscription_id;

  return jsonb_build_object(
    'ok', true,
    'already_processed', false,
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'service_name', v_service.name,
    'amount', v_service.price,
    'currency', 'RUB',
    'miles_spent', v_miles_required,
    'remaining_miles', v_remaining,
    'subscription_id', v_subscription_id,
    'starts_at', v_start,
    'ends_at', v_end,
    'duration_days', v_service.duration_days
  );
end;
$function$
;
revoke all on function public.rf_redeem_miles_for_service(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.rf_redeem_miles_for_service(uuid,text,uuid,uuid) to service_role;

CREATE OR REPLACE FUNCTION public.rf_activate_roblox_gamepass(p_roblox_user_id bigint, p_service_id uuid, p_gamepass_id text, p_place_id bigint, p_job_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_profile public.rf_profiles%rowtype;
  v_service public.rf_services%rowtype;
  v_existing public.rf_roblox_entitlements%rowtype;
  v_order_id uuid;
  v_subscription_id uuid;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_order_number text;
  v_place_setting_key text;
BEGIN
  IF current_user NOT IN ('service_role', 'postgres') THEN
    RAISE EXCEPTION 'not_authorized' USING errcode = '42501';
  END IF;

  IF p_roblox_user_id IS NULL OR p_roblox_user_id <= 0
     OR p_service_id IS NULL
     OR p_gamepass_id IS NULL
     OR p_gamepass_id !~ '^[1-9][0-9]{0,19}$'
     OR p_place_id IS NULL OR p_place_id <= 0
     OR p_job_id IS NULL OR length(trim(p_job_id)) = 0 THEN
    RAISE EXCEPTION 'invalid_roblox_purchase' USING errcode = '22023';
  END IF;

  SELECT * INTO v_profile
  FROM public.rf_profiles
  WHERE roblox_user_id = p_roblox_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'account_not_linked');
  END IF;

  SELECT * INTO v_service
  FROM public.rf_services
  WHERE id = p_service_id
  FOR UPDATE;

  IF NOT FOUND OR v_service.active IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'service_unavailable');
  END IF;

  IF v_service.payment_mode NOT IN ('roblox_only', 'both')
     OR v_service.roblox_enabled IS NOT TRUE
     OR v_service.roblox_gamepass_id IS DISTINCT FROM p_gamepass_id
     OR COALESCE(v_service.robux_price, 0) <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'gamepass_not_current_or_payment_disabled');
  END IF;

  v_place_setting_key := CASE
    WHEN v_service.airline_code = 'izavia' THEN 'roblox_place_ids_izavia'
    ELSE 'roblox_place_ids'
  END;

  IF NOT EXISTS (
    SELECT 1
    FROM public.rf_settings
    WHERE key = v_place_setting_key
      AND value @> jsonb_build_array(p_place_id::text)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'place_not_allowed');
  END IF;

  SELECT * INTO v_existing
  FROM public.rf_roblox_entitlements
  WHERE profile_id = v_profile.id
    AND service_id = v_service.id
    AND gamepass_id = p_gamepass_id;

  IF FOUND THEN
    SELECT starts_at, ends_at
      INTO v_starts_at, v_ends_at
    FROM public.rf_subscriptions
    WHERE id = v_existing.subscription_id;

    RETURN jsonb_build_object(
      'ok', true,
      'alreadyActivated', true,
      'airlineCode', v_service.airline_code,
      'serviceId', v_service.id,
      'startsAt', v_starts_at,
      'endsAt', v_ends_at
    );
  END IF;

  v_order_number := CASE v_service.airline_code
    WHEN 'azal' THEN 'AZAL-'
    WHEN 'izavia' THEN 'IZH-'
    ELSE 'RF-'
  END || to_char(now(), 'YYMMDD') || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  INSERT INTO public.rf_orders (
    airline_code, order_number, profile_id, service_id,
    amount, currency, status, paid_at,
    payment_provider, payment_reference
  ) VALUES (
    v_service.airline_code, v_order_number, v_profile.id, v_service.id,
    v_service.robux_price, 'ROBUX', 'paid', now(),
    'roblox_gamepass', p_gamepass_id
  ) RETURNING id INTO v_order_id;

  SELECT greatest(now(), coalesce(max(ends_at), now()))
    INTO v_starts_at
  FROM public.rf_subscriptions
  WHERE profile_id = v_profile.id
    AND service_id = v_service.id
    AND airline_code = v_service.airline_code
    AND status = 'active';

  v_ends_at := v_starts_at + make_interval(days => v_service.duration_days);

  INSERT INTO public.rf_subscriptions (
    airline_code, profile_id, service_id, source_order_id,
    starts_at, ends_at, status
  ) VALUES (
    v_service.airline_code, v_profile.id, v_service.id, v_order_id,
    v_starts_at, v_ends_at, 'active'
  ) RETURNING id INTO v_subscription_id;

  INSERT INTO public.rf_roblox_entitlements (
    profile_id, roblox_user_id, airline_code, service_id,
    gamepass_id, order_id, subscription_id, place_id, job_id
  ) VALUES (
    v_profile.id, p_roblox_user_id, v_service.airline_code, v_service.id,
    p_gamepass_id, v_order_id, v_subscription_id, p_place_id, left(p_job_id, 100)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'alreadyActivated', false,
    'airlineCode', v_service.airline_code,
    'serviceId', v_service.id,
    'serviceName', v_service.name,
    'orderNumber', v_order_number,
    'startsAt', v_starts_at,
    'endsAt', v_ends_at,
    'durationDays', v_service.duration_days
  );
END;
$function$
;
revoke all on function public.rf_activate_roblox_gamepass(bigint,uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function public.rf_activate_roblox_gamepass(bigint,uuid,text,bigint,text) to service_role;

CREATE OR REPLACE FUNCTION public.rf_activate_izavia_purchase_code(
  p_code text,
  p_roblox_user_id bigint,
  p_gamepass_id text,
  p_place_id bigint,
  p_job_id text,
  p_ownership_verified boolean
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public,pg_temp
AS $function$
DECLARE
  v_code public.rf_izavia_purchase_codes%rowtype;
  v_service public.rf_services%rowtype;
  v_activation jsonb;
BEGIN
  IF current_user NOT IN ('service_role','postgres') THEN
    RAISE EXCEPTION 'not_authorized' USING errcode='42501';
  END IF;
  IF COALESCE(p_ownership_verified,false) IS NOT TRUE
     OR p_code IS NULL OR p_code !~ '^[A-HJ-NP-Z2-9]{8}$'
     OR p_roblox_user_id IS NULL OR p_roblox_user_id <= 0
     OR p_gamepass_id IS NULL OR p_gamepass_id !~ '^[1-9][0-9]{0,19}$'
     OR p_place_id IS NULL OR p_place_id <= 0
     OR p_job_id IS NULL OR length(trim(p_job_id))=0 THEN
    RAISE EXCEPTION 'invalid_izavia_purchase' USING errcode='22023';
  END IF;

  SELECT * INTO v_code
  FROM public.rf_izavia_purchase_codes
  WHERE code=p_code
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'purchase_code_not_found' USING errcode='P0002'; END IF;
  IF v_code.used_at IS NOT NULL THEN RAISE EXCEPTION 'purchase_code_already_used' USING errcode='P0001'; END IF;
  IF v_code.expires_at <= now() THEN RAISE EXCEPTION 'purchase_code_expired' USING errcode='P0001'; END IF;
  IF v_code.started_at IS NULL OR v_code.started_by_roblox_user_id IS DISTINCT FROM p_roblox_user_id THEN
    RAISE EXCEPTION 'purchase_code_not_started_by_player' USING errcode='42501';
  END IF;
  IF v_code.gamepass_id IS DISTINCT FROM p_gamepass_id THEN
    RAISE EXCEPTION 'purchase_gamepass_mismatch' USING errcode='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.rf_profiles
    WHERE id=v_code.profile_id AND roblox_user_id=p_roblox_user_id
  ) THEN RAISE EXCEPTION 'roblox_account_not_linked' USING errcode='42501'; END IF;

  SELECT * INTO v_service
  FROM public.rf_services
  WHERE id=v_code.service_id AND airline_code='izavia' AND active=true
    AND payment_mode IN ('roblox_only','both') AND roblox_enabled=true
    AND roblox_gamepass_id=p_gamepass_id AND COALESCE(robux_price,0)>0
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'service_or_gamepass_changed' USING errcode='P0001'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.rf_settings
    WHERE key='roblox_place_ids_izavia'
      AND value @> jsonb_build_array(p_place_id::text)
  ) THEN RAISE EXCEPTION 'izavia_place_not_allowed' USING errcode='42501'; END IF;

  v_activation := public.rf_activate_roblox_gamepass(
    p_roblox_user_id,v_code.service_id,p_gamepass_id,p_place_id,p_job_id
  );
  IF COALESCE((v_activation->>'ok')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'izavia_gamepass_activation_failed:%',COALESCE(v_activation->>'reason','unknown')
      USING errcode='P0001';
  END IF;

  UPDATE public.rf_izavia_purchase_codes SET used_at=now()
  WHERE code=p_code AND used_at IS NULL;
  RETURN v_activation || jsonb_build_object('purchaseCodeUsed',true);
END;
$function$;

REVOKE ALL ON FUNCTION public.rf_activate_izavia_purchase_code(text,bigint,text,bigint,text,boolean)
  FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rf_activate_izavia_purchase_code(text,bigint,text,bigint,text,boolean)
  TO service_role;
