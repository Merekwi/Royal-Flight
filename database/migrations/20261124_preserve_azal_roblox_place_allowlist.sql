-- Keep the historical shared Place allow-list for Royal Flight and AZAL.
-- Only IZhAVIA uses its own Place ID setting for its separate Roblox Experience.
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
REVOKE ALL ON FUNCTION public.rf_activate_roblox_gamepass(bigint,uuid,text,bigint,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rf_activate_roblox_gamepass(bigint,uuid,text,bigint,text)
  TO service_role;
