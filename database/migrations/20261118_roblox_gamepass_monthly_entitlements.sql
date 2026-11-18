-- Monthly Roblox Game Pass renewal support.
-- Rotating rf_services.roblox_gamepass_id MUST NOT alter existing rf_subscriptions.
alter table public.rf_services
  add column if not exists roblox_enabled boolean not null default false,
  add column if not exists roblox_gamepass_id text,
  add column if not exists robux_price integer;

alter table public.rf_services
  add constraint rf_services_roblox_gamepass_id_format
    check (roblox_gamepass_id is null or roblox_gamepass_id ~ '^[1-9][0-9]{0,19}$'),
  add constraint rf_services_robux_price_check
    check (robux_price is null or robux_price > 0),
  add constraint rf_services_roblox_configuration_check
    check (not roblox_enabled or (roblox_gamepass_id is not null and robux_price is not null));

create unique index rf_services_roblox_gamepass_id_key
  on public.rf_services (roblox_gamepass_id)
  where roblox_gamepass_id is not null;

alter table public.rf_orders
  add column if not exists payment_provider text not null default 'manual',
  add column if not exists payment_reference text;

alter table public.rf_orders
  add constraint rf_orders_payment_provider_check
    check (payment_provider in ('manual', 'roblox_gamepass'));

create table if not exists public.rf_roblox_entitlements (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.rf_profiles(id) on delete cascade,
  roblox_user_id bigint not null,
  airline_code text not null check (airline_code in ('royal', 'azal')),
  service_id uuid not null,
  gamepass_id text not null,
  order_id uuid not null unique,
  subscription_id uuid not null references public.rf_subscriptions(id),
  place_id bigint not null,
  job_id text not null,
  verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint rf_roblox_entitlements_gamepass_format
    check (gamepass_id ~ '^[1-9][0-9]{0,19}$'),
  constraint rf_roblox_entitlements_service_airline_fkey
    foreign key (service_id, airline_code)
    references public.rf_services(id, airline_code),
  constraint rf_roblox_entitlements_order_airline_fkey
    foreign key (order_id, airline_code)
    references public.rf_orders(id, airline_code),
  constraint rf_roblox_entitlements_profile_service_gamepass_key
    unique (profile_id, service_id, gamepass_id)
);

create index rf_roblox_entitlements_user_idx
  on public.rf_roblox_entitlements (roblox_user_id, airline_code);

create index rf_subscriptions_active_entitlement_idx
  on public.rf_subscriptions (profile_id, service_id, airline_code, ends_at desc)
  where status = 'active';

alter table public.rf_roblox_entitlements enable row level security;
revoke all on public.rf_roblox_entitlements from public, anon, authenticated;
grant all on public.rf_roblox_entitlements to service_role;

comment on column public.rf_services.roblox_gamepass_id is
  'Current Game Pass ID offered for future renewals only. Changing it never changes existing subscriptions.';
comment on column public.rf_services.roblox_enabled is
  'Enables the current Game Pass as a way to renew a subscription. Existing entitlements are independent of this flag.';
comment on column public.rf_subscriptions.ends_at is
  'Passenger-specific entitlement expiry. Game Pass rotation must never modify this value.';

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

  -- Serialize purchases for one linked passenger before checking idempotency
  -- or extending their existing expiry.
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

  if v_service.roblox_enabled is not true
     or v_service.roblox_gamepass_id is distinct from p_gamepass_id
     or coalesce(v_service.robux_price, 0) <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'gamepass_not_current');
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

  -- A renewal begins after the passenger's current expiry if it is still active.
  -- If the passenger has no active period left, the new period starts now.
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

revoke all on function public.rf_activate_roblox_gamepass(bigint, uuid, text, bigint, text)
  from public, anon, authenticated;
grant execute on function public.rf_activate_roblox_gamepass(bigint, uuid, text, bigint, text)
  to service_role;
