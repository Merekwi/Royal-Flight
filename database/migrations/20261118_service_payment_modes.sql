-- Per-service accepted payment methods.
-- Existing services remain manual-only by default.
alter table public.rf_services
  add column if not exists payment_mode text not null default 'manual_only';

alter table public.rf_services
  add constraint rf_services_payment_mode_check
    check (payment_mode in ('manual_only', 'roblox_only', 'both')),
  add constraint rf_services_payment_mode_roblox_check
    check (
      payment_mode = 'manual_only'
      or (
        roblox_enabled is true
        and roblox_gamepass_id is not null
        and robux_price is not null
        and robux_price > 0
      )
    );

comment on column public.rf_services.payment_mode is
  'Accepted payment channels: manual_only (existing non-Robux payment methods), roblox_only (Game Pass only), or both. Current passenger subscriptions are unaffected by changes.';

create or replace function public.rf_activate_roblox_gamepass(
  p_roblox_user_id bigint,
  p_service_id uuid,
  p_gamepass_id text,
  p_place_id bigint,
  p_job_id text
)
returns jsonb
language plpgsql
set search_path to public, pg_temp
as $function$
declare
  v_profile public.rf_profiles%rowtype;
  v_service public.rf_services%rowtype;
  v_existing public.rf_roblox_entitlements%rowtype;
  v_order_id uuid;
  v_subscription_id uuid;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_order_number text;
begin
  if current_user not in ('service_role', 'postgres') then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  if p_roblox_user_id is null or p_roblox_user_id <= 0
     or p_service_id is null
     or p_gamepass_id is null
     or p_gamepass_id !~ '^[1-9][0-9]{0,19}$'
     or p_place_id is null or p_place_id <= 0
     or p_job_id is null or length(trim(p_job_id)) = 0 then
    raise exception 'invalid_roblox_purchase' using errcode = '22023';
  end if;

  select * into v_profile
  from public.rf_profiles
  where roblox_user_id = p_roblox_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'account_not_linked');
  end if;

  select * into v_service
  from public.rf_services
  where id = p_service_id
  for update;

  if not found or v_service.active is not true then
    return jsonb_build_object('ok', false, 'reason', 'service_unavailable');
  end if;

  if v_service.payment_mode not in ('roblox_only', 'both')
     or v_service.roblox_enabled is not true
     or v_service.roblox_gamepass_id is distinct from p_gamepass_id
     or coalesce(v_service.robux_price, 0) <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'gamepass_not_current_or_payment_disabled');
  end if;

  if not exists (
    select 1
    from public.rf_settings
    where key = 'roblox_place_ids'
      and value @> jsonb_build_array(p_place_id::text)
  ) then
    return jsonb_build_object('ok', false, 'reason', 'place_not_allowed');
  end if;

  select * into v_existing
  from public.rf_roblox_entitlements
  where profile_id = v_profile.id
    and service_id = v_service.id
    and gamepass_id = p_gamepass_id;

  if found then
    select starts_at, ends_at
      into v_starts_at, v_ends_at
    from public.rf_subscriptions
    where id = v_existing.subscription_id;

    return jsonb_build_object(
      'ok', true,
      'alreadyActivated', true,
      'airlineCode', v_service.airline_code,
      'serviceId', v_service.id,
      'startsAt', v_starts_at,
      'endsAt', v_ends_at
    );
  end if;

  v_order_number := 'RBX-' || to_char(now(), 'YYMMDD') || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.rf_orders (
    airline_code, order_number, profile_id, service_id,
    amount, currency, status, paid_at,
    payment_provider, payment_reference
  ) values (
    v_service.airline_code, v_order_number, v_profile.id, v_service.id,
    v_service.robux_price, 'ROBUX', 'paid', now(),
    'roblox_gamepass', p_gamepass_id
  ) returning id into v_order_id;

  select greatest(now(), coalesce(max(ends_at), now()))
    into v_starts_at
  from public.rf_subscriptions
  where profile_id = v_profile.id
    and service_id = v_service.id
    and airline_code = v_service.airline_code
    and status = 'active';

  v_ends_at := v_starts_at + make_interval(days => v_service.duration_days);

  insert into public.rf_subscriptions (
    airline_code, profile_id, service_id, source_order_id,
    starts_at, ends_at, status
  ) values (
    v_service.airline_code, v_profile.id, v_service.id, v_order_id,
    v_starts_at, v_ends_at, 'active'
  ) returning id into v_subscription_id;

  insert into public.rf_roblox_entitlements (
    profile_id, roblox_user_id, airline_code, service_id,
    gamepass_id, order_id, subscription_id, place_id, job_id
  ) values (
    v_profile.id, p_roblox_user_id, v_service.airline_code, v_service.id,
    p_gamepass_id, v_order_id, v_subscription_id, p_place_id, left(p_job_id, 100)
  );

  return jsonb_build_object(
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
end;
$function$;
