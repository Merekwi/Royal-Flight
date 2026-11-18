-- Royal Alliance miles: earning rate, excluded menu place, and redemption checkout.
-- The menu place is the existing Royal Flight portal place ID. All other places
-- with the trusted server tracker may continue earning miles.

alter table public.rf_orders
  drop constraint if exists rf_orders_payment_provider_check;
alter table public.rf_orders
  add constraint rf_orders_payment_provider_check
  check (payment_provider in ('manual', 'roblox_gamepass', 'miles'));

create unique index if not exists rf_orders_miles_request_uidx
  on public.rf_orders(profile_id, payment_reference)
  where payment_provider = 'miles' and payment_reference is not null;

insert into public.rf_settings(key, value, updated_at)
values ('roblox_miles_excluded_place_ids', '["101826857818257"]'::jsonb, now())
on conflict (key) do update
set value = excluded.value, updated_at = now();

update public.rf_settings
set value = '1'::jsonb, updated_at = now()
where key = 'miles_per_minute';

update public.rf_online_sessions
set ended_at = coalesce(ended_at, now()), last_heartbeat_at = now()
where place_id = 101826857818257 and ended_at is null;

create or replace function public.rf_roblox_heartbeat(
  p_roblox_user_id bigint,
  p_place_id bigint,
  p_job_id text,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_profile public.rf_profiles%rowtype;
  v_session public.rf_online_sessions%rowtype;
  v_elapsed integer := 0;
  v_total integer := 0;
  v_new_minutes integer := 0;
  v_old_minutes integer := 0;
  v_rate integer := 1;
  v_delta bigint := 0;
  v_source_key text;
  v_ledger_id uuid;
begin
  if current_user not in ('service_role', 'postgres') then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  if p_roblox_user_id is null or p_roblox_user_id <= 0
     or p_place_id is null or p_place_id <= 0
     or p_job_id is null or length(trim(p_job_id)) = 0
     or p_now is null then
    raise exception 'invalid_heartbeat' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.rf_settings
    where key = 'roblox_miles_excluded_place_ids'
      and value @> jsonb_build_array(p_place_id::text)
  ) then
    update public.rf_online_sessions
    set ended_at = coalesce(ended_at, p_now), last_heartbeat_at = p_now
    where roblox_user_id = p_roblox_user_id and job_id = p_job_id
      and place_id = p_place_id and ended_at is null;
    return jsonb_build_object(
      'ok', true, 'excluded', true, 'reason', 'mileage_disabled_in_place',
      'credited_seconds', 0, 'miles_added', 0
    );
  end if;

  select * into v_profile
  from public.rf_profiles
  where roblox_user_id = p_roblox_user_id
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'account_not_linked');
  end if;

  select * into v_session
  from public.rf_online_sessions
  where roblox_user_id = p_roblox_user_id and job_id = p_job_id
  for update;

  if not found then
    insert into public.rf_online_sessions(
      roblox_user_id, place_id, job_id, started_at, last_heartbeat_at, credited_seconds
    ) values (p_roblox_user_id, p_place_id, p_job_id, p_now, p_now, 0)
    on conflict (roblox_user_id, job_id) do nothing;
    select * into v_session
    from public.rf_online_sessions
    where roblox_user_id = p_roblox_user_id and job_id = p_job_id
    for update;
  end if;

  if v_session.ended_at is not null then
    update public.rf_online_sessions
    set place_id = p_place_id, started_at = p_now, last_heartbeat_at = p_now,
        ended_at = null, credited_seconds = 0
    where id = v_session.id
    returning * into v_session;
    v_total := 0;
  else
    v_elapsed := greatest(0, least(90,
      floor(extract(epoch from (p_now - v_session.last_heartbeat_at)))::integer));
    v_total := v_session.credited_seconds + v_elapsed;
    v_old_minutes := floor(v_session.credited_seconds / 60.0)::integer;
    v_new_minutes := floor(v_total / 60.0)::integer;

    select coalesce((value #>> '{}')::integer, 1)
    into v_rate
    from public.rf_settings
    where key = 'miles_per_minute';
    v_delta := (v_new_minutes - v_old_minutes) * coalesce(v_rate, 1);

    update public.rf_online_sessions
    set place_id = p_place_id, last_heartbeat_at = p_now, credited_seconds = v_total
    where id = v_session.id;

    if v_delta > 0 then
      v_source_key := 'roblox:' || p_roblox_user_id::text || ':' || p_job_id || ':' ||
        to_char(v_session.started_at at time zone 'UTC', 'YYYYMMDDHH24MISSUS') || ':' ||
        v_new_minutes::text;
      insert into public.rf_mile_ledger(profile_id, delta, reason, source_key, metadata)
      values (
        v_profile.id, v_delta, 'roblox_online_minutes', v_source_key,
        jsonb_build_object(
          'place_id', p_place_id, 'job_id', p_job_id,
          'credited_seconds', v_total, 'miles_per_minute', coalesce(v_rate, 1)
        )
      )
      on conflict (source_key) do nothing
      returning id into v_ledger_id;

      if v_ledger_id is not null then
        update public.rf_profiles
        set miles = miles + v_delta, updated_at = now()
        where id = v_profile.id;
      else
        v_delta := 0;
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'credited_seconds', v_total, 'miles_added', v_delta);
end;
$function$;

revoke all on function public.rf_roblox_heartbeat(bigint, bigint, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.rf_roblox_heartbeat(bigint, bigint, text, timestamptz)
  to service_role;

create or replace function public.rf_redeem_miles_for_service(
  p_profile_id uuid,
  p_airline_code text,
  p_service_id uuid,
  p_request_key uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $function$
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
  if p_profile_id is null or p_airline_code is null
     or p_airline_code not in ('royal', 'azal')
     or p_service_id is null or p_request_key is null then
    raise exception 'invalid_miles_redemption' using errcode = '22023';
  end if;

  select * into v_profile from public.rf_profiles where id = p_profile_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'profile_not_found');
  end if;

  select * into v_order
  from public.rf_orders
  where profile_id = p_profile_id and payment_provider = 'miles'
    and payment_reference = p_request_key::text;

  if found then
    select greatest(0, -delta) into v_miles_spent
    from public.rf_mile_ledger
    where source_key = 'miles_purchase:' || p_request_key::text;
    select id, ends_at into v_subscription_id, v_end
    from public.rf_subscriptions where source_order_id = v_order.id;
    return jsonb_build_object(
      'ok', true, 'already_processed', true,
      'order_id', v_order.id, 'order_number', v_order.order_number,
      'amount', v_order.amount, 'currency', v_order.currency,
      'miles_spent', coalesce(v_miles_spent, 0),
      'remaining_miles', v_profile.miles,
      'subscription_id', v_subscription_id, 'ends_at', v_end
    );
  end if;

  select * into v_service
  from public.rf_services
  where id = p_service_id and airline_code = p_airline_code and active = true
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
      'ok', false, 'reason', 'insufficient_miles',
      'required_miles', v_miles_required, 'available_miles', v_profile.miles
    );
  end if;

  v_order_number := (case when p_airline_code = 'azal' then 'AZAL-' else 'RF-' end)
    || 'M-' || to_char(now(), 'YYMMDD') || '-'
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.rf_orders(
    airline_code, order_number, profile_id, service_id, amount, currency,
    status, paid_at, payment_provider, payment_reference, user_note
  ) values (
    p_airline_code, v_order_number, p_profile_id, p_service_id,
    v_service.price, 'RUB', 'paid', now(), 'miles', p_request_key::text,
    'Оплачено милями: ' || v_miles_required::text
  ) returning * into v_order;

  update public.rf_profiles
  set miles = miles - v_miles_required, updated_at = now()
  where id = p_profile_id and miles >= v_miles_required
  returning miles into v_remaining;
  if not found then
    raise exception 'insufficient_miles' using errcode = 'P0001';
  end if;

  insert into public.rf_mile_ledger(profile_id, delta, reason, source_key, metadata)
  values (
    p_profile_id, -v_miles_required, 'service_purchase',
    'miles_purchase:' || p_request_key::text,
    jsonb_build_object(
      'order_id', v_order.id, 'service_id', v_service.id,
      'airline_code', p_airline_code, 'service_price_rub', v_service.price,
      'miles_per_rub', 10
    )
  );

  select greatest(now(), coalesce(max(ends_at), now())) into v_start
  from public.rf_subscriptions
  where profile_id = p_profile_id and service_id = p_service_id
    and airline_code = p_airline_code and status = 'active';
  v_end := v_start + make_interval(days => v_service.duration_days);

  insert into public.rf_subscriptions(
    airline_code, profile_id, service_id, source_order_id, starts_at, ends_at, status
  ) values (
    p_airline_code, p_profile_id, p_service_id, v_order.id, v_start, v_end, 'active'
  ) returning id into v_subscription_id;

  return jsonb_build_object(
    'ok', true, 'already_processed', false,
    'order_id', v_order.id, 'order_number', v_order.order_number,
    'service_name', v_service.name, 'amount', v_service.price, 'currency', 'RUB',
    'miles_spent', v_miles_required, 'remaining_miles', v_remaining,
    'subscription_id', v_subscription_id,
    'starts_at', v_start, 'ends_at', v_end, 'duration_days', v_service.duration_days
  );
end;
$function$;

revoke all on function public.rf_redeem_miles_for_service(uuid, text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.rf_redeem_miles_for_service(uuid, text, uuid, uuid)
  to service_role;
