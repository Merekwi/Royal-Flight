-- Royal Flight Platform schema. Keep browser roles locked; use trusted Edge Functions.
create extension if not exists pgcrypto;
create table public.rf_profiles (id uuid primary key default gen_random_uuid(), telegram_id bigint unique not null, telegram_username text, display_name text, roblox_user_id bigint unique, roblox_username text, role text not null default 'member' check(role in ('member','admin','owner')), miles bigint not null default 0 check(miles>=0), created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_flights (id uuid primary key default gen_random_uuid(), title text not null, flight_number text, origin text not null, destination text not null, aircraft text, departure_at timestamptz not null, registration_deadline timestamptz, capacity integer check(capacity is null or capacity>0), status text not null default 'scheduled' check(status in ('draft','scheduled','boarding','departed','completed','cancelled')), description text, created_by bigint, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_flight_registrations (id uuid primary key default gen_random_uuid(), flight_id uuid not null references public.rf_flights(id) on delete cascade, profile_id uuid not null references public.rf_profiles(id) on delete cascade, status text not null default 'registered' check(status in ('registered','cancelled','checked_in')), created_at timestamptz not null default now(), unique(flight_id,profile_id));
create table public.rf_services (id uuid primary key default gen_random_uuid(), code text unique not null, name text not null, description text, price numeric(12,2) not null check(price>=0), currency text not null default 'RUB', duration_days integer not null check(duration_days>0), active boolean not null default true, sort_order integer not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_payment_methods (id uuid primary key default gen_random_uuid(), label text not null, card_number text not null, recipient_name text, instructions text, active boolean not null default true, created_at timestamptz not null default now());
create table public.rf_orders (id uuid primary key default gen_random_uuid(), order_number text unique not null, profile_id uuid not null references public.rf_profiles(id), service_id uuid not null references public.rf_services(id), payment_method_id uuid references public.rf_payment_methods(id), amount numeric(12,2) not null check(amount>=0), currency text not null default 'RUB', status text not null default 'awaiting_payment' check(status in ('awaiting_payment','awaiting_review','paid','rejected','cancelled')), proof_url text, user_note text, admin_note text, reviewed_by bigint, reviewed_at timestamptz, created_at timestamptz not null default now(), paid_at timestamptz);
create table public.rf_subscriptions (id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.rf_profiles(id) on delete cascade, service_id uuid not null references public.rf_services(id), source_order_id uuid not null unique references public.rf_orders(id), starts_at timestamptz not null, ends_at timestamptz not null, status text not null default 'active' check(status in ('active','expired','revoked')), created_at timestamptz not null default now(), check(ends_at>starts_at));
create table public.rf_mile_ledger (id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.rf_profiles(id) on delete cascade, delta bigint not null check(delta<>0), reason text not null, source_key text unique, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create table public.rf_online_sessions (id uuid primary key default gen_random_uuid(), roblox_user_id bigint not null, place_id bigint not null, job_id text not null, started_at timestamptz not null default now(), last_heartbeat_at timestamptz not null default now(), ended_at timestamptz, credited_seconds integer not null default 0 check(credited_seconds>=0), unique(roblox_user_id,job_id));
create table public.rf_notifications (id uuid primary key default gen_random_uuid(), title text not null, body text not null, audience text not null default 'all' check(audience in ('all','admins','roblox_linked','active_service')), scheduled_at timestamptz, sent_at timestamptz, status text not null default 'draft' check(status in ('draft','scheduled','sent','failed')), created_by bigint, created_at timestamptz not null default now());
create table public.rf_settings (key text primary key, value jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now(), updated_by bigint);
create table public.rf_admin_audit (id uuid primary key default gen_random_uuid(), admin_telegram_id bigint not null, action text not null, entity_type text, entity_id text, details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create index rf_flights_departure_idx on public.rf_flights(departure_at);
create index rf_orders_status_created_idx on public.rf_orders(status,created_at desc);
create index rf_subscriptions_profile_ends_idx on public.rf_subscriptions(profile_id,ends_at desc);
create index rf_mile_ledger_profile_created_idx on public.rf_mile_ledger(profile_id,created_at desc);
create index rf_online_sessions_active_idx on public.rf_online_sessions(roblox_user_id,last_heartbeat_at desc) where ended_at is null;
do $$ declare t text; begin foreach t in array array['rf_profiles','rf_flights','rf_flight_registrations','rf_services','rf_payment_methods','rf_orders','rf_subscriptions','rf_mile_ledger','rf_online_sessions','rf_notifications','rf_settings','rf_admin_audit'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from anon, authenticated',t); end loop; end $$;
insert into public.rf_settings(key,value) values('miles_per_minute','10'::jsonb),('roblox_place_ids','[]'::jsonb),('owner_telegram_id','null'::jsonb) on conflict(key) do nothing;

-- Atomic admin decision: rejects duplicate reviews and extends an existing service period.
create or replace function public.rf_admin_review_order(
  p_order_id uuid, p_admin_telegram_id bigint, p_paid boolean, p_note text default null
) returns jsonb
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare v_order public.rf_orders%rowtype; v_service public.rf_services%rowtype;
  v_start timestamptz; v_end timestamptz; v_sub_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  if not exists(select 1 from public.rf_profiles where telegram_id=p_admin_telegram_id and role in ('admin','owner')) then
    raise exception 'admin_required' using errcode='42501';
  end if;
  select * into v_order from public.rf_orders where id=p_order_id for update;
  if not found then raise exception 'order_not_found' using errcode='P0002'; end if;
  if v_order.status <> 'awaiting_review' then raise exception 'order_not_pending_review' using errcode='P0001'; end if;
  if not p_paid then
    update public.rf_orders set status='rejected',admin_note=nullif(trim(coalesce(p_note,'')),''),reviewed_by=p_admin_telegram_id,reviewed_at=now() where id=p_order_id;
    insert into public.rf_admin_audit(admin_telegram_id,action,entity_type,entity_id,details)
    values(p_admin_telegram_id,'order_rejected','order',p_order_id::text,jsonb_build_object('order_number',v_order.order_number,'note',p_note));
    return jsonb_build_object('status','rejected','order_number',v_order.order_number);
  end if;
  select * into v_service from public.rf_services where id=v_order.service_id and active=true;
  if not found then raise exception 'service_unavailable' using errcode='P0001'; end if;
  update public.rf_orders set status='paid',paid_at=now(),admin_note=nullif(trim(coalesce(p_note,'')),''),reviewed_by=p_admin_telegram_id,reviewed_at=now() where id=p_order_id;
  select greatest(now(),coalesce(max(ends_at),now())) into v_start from public.rf_subscriptions
    where profile_id=v_order.profile_id and service_id=v_order.service_id and status='active';
  v_end:=v_start+make_interval(days=>v_service.duration_days);
  insert into public.rf_subscriptions(profile_id,service_id,source_order_id,starts_at,ends_at,status)
    values(v_order.profile_id,v_order.service_id,v_order.id,v_start,v_end,'active') returning id into v_sub_id;
  insert into public.rf_admin_audit(admin_telegram_id,action,entity_type,entity_id,details)
    values(p_admin_telegram_id,'order_paid_and_service_activated','order',p_order_id::text,
      jsonb_build_object('order_number',v_order.order_number,'subscription_id',v_sub_id,'starts_at',v_start,'ends_at',v_end));
  return jsonb_build_object('status','paid','order_number',v_order.order_number,'subscription_id',v_sub_id,'starts_at',v_start,'ends_at',v_end);
end;
$$;
revoke all on function public.rf_admin_review_order(uuid,bigint,boolean,text) from public,anon,authenticated;
grant execute on function public.rf_admin_review_order(uuid,bigint,boolean,text) to service_role;
