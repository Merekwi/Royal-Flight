-- Royal Flight Platform schema. Keep browser roles locked; use trusted Edge Functions.
create extension if not exists pgcrypto;
create table public.rf_profiles (id uuid primary key default gen_random_uuid(), telegram_id bigint unique not null, telegram_username text, display_name text, roblox_user_id bigint unique, roblox_username text, role text not null default 'member' check(role in ('member','owner')), miles bigint not null default 0 check(miles>=0), created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_airline_staff (id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.rf_profiles(id) on delete cascade, airline_code text not null check(airline_code in ('royal','azal','izavia')), role text not null default 'admin' check(role='admin'), created_by bigint, created_at timestamptz not null default now(), unique(profile_id,airline_code));
create table public.rf_airline_memberships (id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.rf_profiles(id) on delete cascade, airline_code text not null check(airline_code in ('royal','azal','izavia')), joined_at timestamptz not null default now(), last_active_at timestamptz not null default now(), unique(profile_id,airline_code));
create table public.rf_flights (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal','izavia')), title text not null, flight_number text, origin text not null, destination text not null, aircraft text, departure_at timestamptz not null, registration_deadline timestamptz, capacity integer check(capacity is null or capacity>0), status text not null default 'scheduled' check(status in ('draft','scheduled','boarding','departed','completed','cancelled')), description text, created_by bigint, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_flight_registrations (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal','izavia')), flight_id uuid not null references public.rf_flights(id) on delete cascade, profile_id uuid not null references public.rf_profiles(id) on delete cascade, status text not null default 'registered' check(status in ('registered','cancelled','checked_in')), created_at timestamptz not null default now(), unique(flight_id,profile_id));
create table public.rf_services (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal','izavia')), code text not null, name text not null, description text, price numeric(12,2) not null check(price>=0), currency text not null default 'RUB', duration_days integer not null check(duration_days>0), active boolean not null default true, sort_order integer not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_payment_methods (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal','izavia')), label text not null, card_number text not null, recipient_name text, instructions text, active boolean not null default true, created_at timestamptz not null default now());
create table public.rf_orders (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal','izavia')), order_number text unique not null, profile_id uuid not null references public.rf_profiles(id), service_id uuid not null references public.rf_services(id), payment_method_id uuid references public.rf_payment_methods(id), amount numeric(12,2) not null check(amount>=0), currency text not null default 'RUB', status text not null default 'awaiting_payment' check(status in ('awaiting_payment','awaiting_review','paid','rejected','cancelled')), proof_url text, user_note text, admin_note text, reviewed_by bigint, reviewed_at timestamptz, created_at timestamptz not null default now(), paid_at timestamptz);
create table public.rf_subscriptions (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal','izavia')), profile_id uuid not null references public.rf_profiles(id) on delete cascade, service_id uuid not null references public.rf_services(id), source_order_id uuid not null unique references public.rf_orders(id), starts_at timestamptz not null, ends_at timestamptz not null, status text not null default 'active' check(status in ('active','expired','revoked')), created_at timestamptz not null default now(), check(ends_at>starts_at));
create table public.rf_mile_ledger (id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.rf_profiles(id) on delete cascade, delta bigint not null check(delta<>0), reason text not null, source_key text unique, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create table public.rf_online_sessions (id uuid primary key default gen_random_uuid(), roblox_user_id bigint not null, place_id bigint not null, job_id text not null, started_at timestamptz not null default now(), last_heartbeat_at timestamptz not null default now(), ended_at timestamptz, credited_seconds integer not null default 0 check(credited_seconds>=0), unique(roblox_user_id,job_id));
create table public.rf_notifications (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal','izavia')), title text not null, body text not null, audience text not null default 'all' check(audience in ('all','admins','roblox_linked','active_service')), scheduled_at timestamptz, sent_at timestamptz, status text not null default 'draft' check(status in ('draft','scheduled','sent','failed')), created_by bigint, created_at timestamptz not null default now());
create table public.rf_settings (key text primary key, value jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now(), updated_by bigint);
create table public.rf_admin_audit (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal','izavia')), admin_telegram_id bigint not null, action text not null, entity_type text, entity_id text, details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
alter table public.rf_services drop constraint if exists rf_services_code_key;
create unique index rf_services_airline_code_uidx on public.rf_services(airline_code,code);
create index rf_flights_departure_idx on public.rf_flights(airline_code,departure_at);
create index rf_airline_memberships_airline_active_idx on public.rf_airline_memberships(airline_code,last_active_at desc,profile_id);
create index rf_flight_registrations_flight_airline_idx on public.rf_flight_registrations(flight_id,airline_code);
create index rf_orders_payment_airline_idx on public.rf_orders(payment_method_id,airline_code);
create index rf_orders_service_airline_idx on public.rf_orders(service_id,airline_code);
create index rf_subscriptions_order_airline_idx on public.rf_subscriptions(source_order_id,airline_code);
create index rf_subscriptions_service_airline_idx on public.rf_subscriptions(service_id,airline_code);
create index rf_airline_staff_airline_role_idx on public.rf_airline_staff(airline_code,role,profile_id);
create index rf_orders_status_created_idx on public.rf_orders(airline_code,status,created_at desc);
create index rf_subscriptions_profile_ends_idx on public.rf_subscriptions(airline_code,profile_id,ends_at desc);
create index rf_mile_ledger_profile_created_idx on public.rf_mile_ledger(profile_id,created_at desc);
create index rf_online_sessions_active_idx on public.rf_online_sessions(roblox_user_id,last_heartbeat_at desc) where ended_at is null;
create unique index rf_flights_id_airline_uidx on public.rf_flights(id,airline_code);
create unique index rf_services_id_airline_uidx on public.rf_services(id,airline_code);
create unique index rf_payment_methods_id_airline_uidx on public.rf_payment_methods(id,airline_code);
create unique index rf_orders_id_airline_uidx on public.rf_orders(id,airline_code);
alter table public.rf_orders add constraint rf_orders_service_airline_fkey foreign key(service_id,airline_code) references public.rf_services(id,airline_code);
alter table public.rf_orders add constraint rf_orders_payment_airline_fkey foreign key(payment_method_id,airline_code) references public.rf_payment_methods(id,airline_code);
alter table public.rf_subscriptions add constraint rf_subscriptions_service_airline_fkey foreign key(service_id,airline_code) references public.rf_services(id,airline_code);
alter table public.rf_subscriptions add constraint rf_subscriptions_order_airline_fkey foreign key(source_order_id,airline_code) references public.rf_orders(id,airline_code);
alter table public.rf_flight_registrations add constraint rf_flight_registrations_flight_airline_fkey foreign key(flight_id,airline_code) references public.rf_flights(id,airline_code);
do $$ declare t text; begin foreach t in array array['rf_profiles','rf_airline_staff','rf_airline_memberships','rf_flights','rf_flight_registrations','rf_services','rf_payment_methods','rf_orders','rf_subscriptions','rf_mile_ledger','rf_online_sessions','rf_notifications','rf_settings','rf_admin_audit'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from anon, authenticated',t); end loop; end $$;
insert into public.rf_settings(key,value) values('miles_per_minute','1'::jsonb),('roblox_place_ids','[]'::jsonb),('roblox_place_ids_izavia','[]'::jsonb),('roblox_miles_excluded_place_ids','["101826857818257"]'::jsonb),('owner_telegram_id','null'::jsonb) on conflict(key) do nothing;

-- Atomic admin decision: rejects duplicate reviews and extends an existing service period.
create or replace function public.rf_admin_review_order(
  p_order_id uuid, p_admin_telegram_id bigint, p_paid boolean, p_note text default null
) returns jsonb
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare v_order public.rf_orders%rowtype; v_service public.rf_services%rowtype;
  v_start timestamptz; v_end timestamptz; v_sub_id uuid;
begin
  if current_user not in ('service_role','postgres') then raise exception 'not_authorized' using errcode='42501'; end if;
  select * into v_order from public.rf_orders where id=p_order_id for update;
  if not found then raise exception 'order_not_found' using errcode='P0002'; end if;
  if not exists(
    select 1 from public.rf_profiles p
    where p.telegram_id=p_admin_telegram_id and (
      p.role='owner' or exists(select 1 from public.rf_airline_staff s where s.profile_id=p.id and s.airline_code=v_order.airline_code and s.role='admin')
    )
  ) then
    raise exception 'admin_required_for_airline' using errcode='42501';
  end if;
  if v_order.status <> 'awaiting_review' then raise exception 'order_not_pending_review' using errcode='P0001'; end if;
  if not p_paid then
    update public.rf_orders set status='rejected',admin_note=nullif(trim(coalesce(p_note,'')),''),reviewed_by=p_admin_telegram_id,reviewed_at=now()
      where id=p_order_id and airline_code=v_order.airline_code;
    insert into public.rf_admin_audit(airline_code,admin_telegram_id,action,entity_type,entity_id,details)
      values(v_order.airline_code,p_admin_telegram_id,'order_rejected','order',p_order_id::text,
        jsonb_build_object('order_number',v_order.order_number,'note',p_note));
    return jsonb_build_object('status','rejected','order_number',v_order.order_number,'airline_code',v_order.airline_code);
  end if;
  select * into v_service from public.rf_services where id=v_order.service_id and airline_code=v_order.airline_code and active=true;
  if not found then raise exception 'service_unavailable_for_airline' using errcode='P0001'; end if;
  update public.rf_orders set status='paid',paid_at=now(),admin_note=nullif(trim(coalesce(p_note,'')),''),reviewed_by=p_admin_telegram_id,reviewed_at=now()
    where id=p_order_id and airline_code=v_order.airline_code;
  select greatest(now(),coalesce(max(ends_at),now())) into v_start
    from public.rf_subscriptions where profile_id=v_order.profile_id and service_id=v_order.service_id
      and airline_code=v_order.airline_code and status='active';
  v_end:=v_start+make_interval(days=>v_service.duration_days);
  insert into public.rf_subscriptions(airline_code,profile_id,service_id,source_order_id,starts_at,ends_at,status)
    values(v_order.airline_code,v_order.profile_id,v_order.service_id,v_order.id,v_start,v_end,'active') returning id into v_sub_id;
  insert into public.rf_admin_audit(airline_code,admin_telegram_id,action,entity_type,entity_id,details)
    values(v_order.airline_code,p_admin_telegram_id,'order_paid_and_service_activated','order',p_order_id::text,
      jsonb_build_object('order_number',v_order.order_number,'subscription_id',v_sub_id,'starts_at',v_start,'ends_at',v_end));
  return jsonb_build_object('status','paid','order_number',v_order.order_number,'airline_code',v_order.airline_code,
    'subscription_id',v_sub_id,'starts_at',v_start,'ends_at',v_end);
end;
$$;
revoke all on function public.rf_admin_review_order(uuid,bigint,boolean,text) from public,anon,authenticated;
grant execute on function public.rf_admin_review_order(uuid,bigint,boolean,text) to service_role;


create or replace function public.rf_adjust_alliance_miles(p_profile_id uuid,p_admin_telegram_id bigint,p_delta bigint)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_profile public.rf_profiles%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_delta is null or p_delta=0 or abs(p_delta)>1000000 then raise exception 'invalid_miles_adjustment' using errcode='22023'; end if;
 if not exists(select 1 from public.rf_profiles where telegram_id=p_admin_telegram_id and role='owner') then raise exception 'alliance_owner_required' using errcode='42501'; end if;
 select * into v_profile from public.rf_profiles where id=p_profile_id for update;
 if not found then raise exception 'profile_not_found' using errcode='P0002'; end if;
 if v_profile.miles+p_delta<0 then raise exception 'insufficient_miles' using errcode='22023'; end if;
 update public.rf_profiles set miles=miles+p_delta,updated_at=now() where id=p_profile_id returning * into v_profile;
 insert into public.rf_mile_ledger(profile_id,delta,reason,metadata) values(p_profile_id,p_delta,'admin_adjustment',jsonb_build_object('admin_telegram_id',p_admin_telegram_id));
 insert into public.rf_admin_audit(airline_code,admin_telegram_id,action,entity_type,entity_id,details)
 values('royal',p_admin_telegram_id,'alliance_miles_adjusted','profile',p_profile_id::text,jsonb_build_object('delta',p_delta,'new_balance',v_profile.miles));
 return jsonb_build_object('profile_id',v_profile.id,'miles',v_profile.miles,'delta',p_delta);
end $$;
revoke all on function public.rf_adjust_alliance_miles(uuid,bigint,bigint) from public,anon,authenticated;
grant execute on function public.rf_adjust_alliance_miles(uuid,bigint,bigint) to service_role;

create or replace function public.rf_register_flight(p_flight_id uuid,p_profile_id uuid,p_airline_code text)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_flight public.rf_flights%rowtype; v_existing public.rf_flight_registrations%rowtype; v_count integer; v_registration_id uuid;
begin
 if current_user not in ('service_role','postgres') then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_airline_code not in ('royal','azal','izavia') then raise exception 'invalid_airline' using errcode='22023'; end if;
 select * into v_flight from public.rf_flights where id=p_flight_id and airline_code=p_airline_code for update;
 if not found then raise exception 'flight_not_found' using errcode='P0002'; end if;
 if v_flight.status not in ('scheduled','boarding') then raise exception 'registration_closed' using errcode='P0001'; end if;
 if v_flight.departure_at<=now() then raise exception 'flight_already_departed' using errcode='P0001'; end if;
 if v_flight.registration_deadline is not null and v_flight.registration_deadline<=now() then raise exception 'registration_deadline_passed' using errcode='P0001'; end if;
 select * into v_existing from public.rf_flight_registrations where flight_id=p_flight_id and profile_id=p_profile_id for update;
 if found and v_existing.status in ('registered','checked_in') then return jsonb_build_object('ok',true,'already_registered',true,'registration_id',v_existing.id); end if;
 if v_flight.capacity is not null then
  select count(*) into v_count from public.rf_flight_registrations where flight_id=p_flight_id and airline_code=p_airline_code and status in ('registered','checked_in');
  if v_count>=v_flight.capacity then raise exception 'flight_full' using errcode='P0001'; end if;
 end if;
 if v_existing.id is not null then
  update public.rf_flight_registrations set status='registered',airline_code=p_airline_code,created_at=now() where id=v_existing.id returning id into v_registration_id;
 else
  insert into public.rf_flight_registrations(airline_code,flight_id,profile_id,status) values(p_airline_code,p_flight_id,p_profile_id,'registered') returning id into v_registration_id;
 end if;
 return jsonb_build_object('ok',true,'already_registered',false,'registration_id',v_registration_id);
end $$;
revoke all on function public.rf_register_flight(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.rf_register_flight(uuid,uuid,text) to service_role;
-- Roblox account linking and verified online-time mileage.
create table if not exists public.rf_roblox_link_codes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.rf_profiles(id) on delete cascade,
  code text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists rf_roblox_link_codes_expiry_idx on public.rf_roblox_link_codes(expires_at);
alter table public.rf_roblox_link_codes enable row level security;
revoke all on public.rf_roblox_link_codes from anon, authenticated;

create or replace function public.rf_roblox_link_account(p_code text,p_roblox_user_id bigint,p_roblox_username text)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_code public.rf_roblox_link_codes%rowtype; v_profile public.rf_profiles%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_roblox_user_id is null or p_roblox_user_id<=0 or length(trim(coalesce(p_roblox_username,'')))=0 then raise exception 'invalid_roblox_identity'; end if;
 select * into v_code from public.rf_roblox_link_codes where code=upper(trim(p_code)) and used_at is null and expires_at>now() for update;
 if not found then raise exception 'link_code_invalid_or_expired'; end if;
 if exists(select 1 from public.rf_profiles where roblox_user_id=p_roblox_user_id and id<>v_code.profile_id) then raise exception 'roblox_account_already_linked'; end if;
 update public.rf_profiles set roblox_user_id=p_roblox_user_id,roblox_username=left(trim(p_roblox_username),100),updated_at=now() where id=v_code.profile_id returning * into v_profile;
 update public.rf_roblox_link_codes set used_at=now() where id=v_code.id;
 update public.rf_roblox_link_codes set used_at=now() where profile_id=v_code.profile_id and used_at is null;
 return jsonb_build_object('ok',true,'telegram_id',v_profile.telegram_id,'roblox_user_id',v_profile.roblox_user_id,'roblox_username',v_profile.roblox_username);
end $$;
revoke all on function public.rf_roblox_link_account(text,bigint,text) from public,anon,authenticated;
grant execute on function public.rf_roblox_link_account(text,bigint,text) to service_role;

create or replace function public.rf_roblox_heartbeat(p_roblox_user_id bigint,p_place_id bigint,p_job_id text,p_now timestamptz default now())
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_profile public.rf_profiles%rowtype; v_session public.rf_online_sessions%rowtype;
 v_elapsed integer:=0; v_total integer:=0; v_new_minutes integer:=0; v_old_minutes integer:=0; v_rate integer:=0; v_delta bigint:=0;
begin
 if current_user not in ('service_role','postgres') then raise exception 'not_authorized' using errcode='42501'; end if;
 select * into v_profile from public.rf_profiles where roblox_user_id=p_roblox_user_id;
 if not found then return jsonb_build_object('ok',false,'reason','account_not_linked'); end if;
 select * into v_session from public.rf_online_sessions where roblox_user_id=p_roblox_user_id and job_id=p_job_id for update;
 if not found then
   insert into public.rf_online_sessions(roblox_user_id,place_id,job_id,started_at,last_heartbeat_at,credited_seconds)
   values(p_roblox_user_id,p_place_id,p_job_id,p_now,p_now,0) returning * into v_session;
 else
   if v_session.ended_at is not null then
     update public.rf_online_sessions set place_id=p_place_id,started_at=p_now,last_heartbeat_at=p_now,ended_at=null,credited_seconds=0 where id=v_session.id returning * into v_session;
   else
     v_elapsed:=greatest(0,least(90,floor(extract(epoch from (p_now-v_session.last_heartbeat_at)))::integer));
     v_total:=v_session.credited_seconds+v_elapsed;
     v_old_minutes:=floor(v_session.credited_seconds/60.0)::integer;
     v_new_minutes:=floor(v_total/60.0)::integer;
     select coalesce((value #>> '{}')::integer,10) into v_rate from public.rf_settings where key='miles_per_minute';
     v_delta:=(v_new_minutes-v_old_minutes)*coalesce(v_rate,10);
     update public.rf_online_sessions set place_id=p_place_id,last_heartbeat_at=p_now,credited_seconds=v_total where id=v_session.id;
     if v_delta>0 then
       update public.rf_profiles set miles=miles+v_delta,updated_at=now() where id=v_profile.id;
       insert into public.rf_mile_ledger(profile_id,delta,reason,source_key,metadata)
       values(v_profile.id,v_delta,'roblox_online_minutes','roblox:'||p_roblox_user_id||':'||p_job_id||':'||v_new_minutes::text,
         jsonb_build_object('place_id',p_place_id,'job_id',p_job_id,'credited_seconds',v_total,'miles_per_minute',coalesce(v_rate,10)));
     end if;
   end if;
 end if;
 return jsonb_build_object('ok',true,'credited_seconds',coalesce(v_session.credited_seconds,0),'miles_added',v_delta);
end $$;
revoke all on function public.rf_roblox_heartbeat(bigint,bigint,text,timestamptz) from public,anon,authenticated;
grant execute on function public.rf_roblox_heartbeat(bigint,bigint,text,timestamptz) to service_role;

-- Cover frequently queried foreign keys.
create index if not exists rf_flight_registrations_profile_idx on public.rf_flight_registrations(profile_id);
create index if not exists rf_orders_payment_method_idx on public.rf_orders(payment_method_id);
create index if not exists rf_orders_profile_idx on public.rf_orders(profile_id);
create index if not exists rf_orders_service_idx on public.rf_orders(service_id);
create index if not exists rf_roblox_link_codes_profile_idx on public.rf_roblox_link_codes(profile_id);
create index if not exists rf_subscriptions_service_idx on public.rf_subscriptions(service_id);


-- Subsequent Roblox Game Pass subscription and service payment-mode schema.
-- Kept here as well as in ordered migrations for a current full-schema reference.
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
  airline_code text not null check (airline_code in ('royal', 'azal', 'izavia')),
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

create table if not exists public.rf_izavia_purchase_codes (
  code text primary key check (code ~ '^[A-HJ-NP-Z2-9]{8}
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
  v_place_setting_key text;
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

  v_place_setting_key := case
    when v_service.airline_code = 'izavia' then 'roblox_place_ids_izavia'
    else 'roblox_place_ids'
  end;

  if not exists (
    select 1
    from public.rf_settings
    where key = v_place_setting_key
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

  v_order_number := (case when v_service.airline_code = 'azal' then 'AZAL-' when v_service.airline_code = 'izavia' then 'IZH-' else 'RF-' end)
    || 'RBX-' || to_char(now(), 'YYMMDD') || '-'
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
  v_place_setting_key text;
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

  v_place_setting_key := case
    when v_service.airline_code = 'izavia' then 'roblox_place_ids_izavia'
    else 'roblox_place_ids'
  end;

  if not exists (
    select 1
    from public.rf_settings
    where key = v_place_setting_key
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

  v_order_number := (case when v_service.airline_code = 'azal' then 'AZAL-' when v_service.airline_code = 'izavia' then 'IZH-' else 'RF-' end)
    || 'RBX-' || to_char(now(), 'YYMMDD') || '-'
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



-- Current Alliance Miles behavior, kept in sync with the ordered migration.
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
     or p_airline_code not in ('royal', 'azal', 'izavia')
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

  v_order_number := (case when p_airline_code = 'azal' then 'AZAL-' when p_airline_code = 'izavia' then 'IZH-' else 'RF-' end)
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

),
  profile_id uuid not null references public.rf_profiles(id) on delete cascade,
  airline_code text not null default 'izavia' check (airline_code = 'izavia'),
  service_id uuid not null,
  gamepass_id text not null check (gamepass_id ~ '^[1-9][0-9]{0,19}
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
  v_place_setting_key text;
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

  v_place_setting_key := case
    when v_service.airline_code = 'izavia' then 'roblox_place_ids_izavia'
    else 'roblox_place_ids'
  end;

  if not exists (
    select 1
    from public.rf_settings
    where key = v_place_setting_key
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

  v_order_number := (case when v_service.airline_code = 'azal' then 'AZAL-' when v_service.airline_code = 'izavia' then 'IZH-' else 'RF-' end)
    || 'RBX-' || to_char(now(), 'YYMMDD') || '-'
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
  v_place_setting_key text;
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

  v_place_setting_key := case
    when v_service.airline_code = 'izavia' then 'roblox_place_ids_izavia'
    else 'roblox_place_ids'
  end;

  if not exists (
    select 1
    from public.rf_settings
    where key = v_place_setting_key
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

  v_order_number := (case when v_service.airline_code = 'azal' then 'AZAL-' when v_service.airline_code = 'izavia' then 'IZH-' else 'RF-' end)
    || 'RBX-' || to_char(now(), 'YYMMDD') || '-'
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



-- Current Alliance Miles behavior, kept in sync with the ordered migration.
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
     or p_airline_code not in ('royal', 'azal', 'izavia')
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

  v_order_number := (case when p_airline_code = 'azal' then 'AZAL-' when p_airline_code = 'izavia' then 'IZH-' else 'RF-' end)
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

),
  expires_at timestamptz not null,
  started_at timestamptz,
  started_by_roblox_user_id bigint,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (service_id, airline_code) references public.rf_services(id, airline_code) on delete cascade
);
create index if not exists rf_izavia_purchase_codes_profile_created_idx
  on public.rf_izavia_purchase_codes(profile_id, created_at desc);
create index if not exists rf_izavia_purchase_codes_open_idx
  on public.rf_izavia_purchase_codes(expires_at) where used_at is null;
alter table public.rf_izavia_purchase_codes enable row level security;
revoke all on public.rf_izavia_purchase_codes from public, anon, authenticated;
grant all on public.rf_izavia_purchase_codes to service_role;

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
  v_place_setting_key text;
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

  v_place_setting_key := case
    when v_service.airline_code = 'izavia' then 'roblox_place_ids_izavia'
    else 'roblox_place_ids'
  end;

  if not exists (
    select 1
    from public.rf_settings
    where key = v_place_setting_key
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

  v_order_number := (case when v_service.airline_code = 'azal' then 'AZAL-' when v_service.airline_code = 'izavia' then 'IZH-' else 'RF-' end)
    || 'RBX-' || to_char(now(), 'YYMMDD') || '-'
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
  v_place_setting_key text;
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

  v_place_setting_key := case
    when v_service.airline_code = 'izavia' then 'roblox_place_ids_izavia'
    else 'roblox_place_ids'
  end;

  if not exists (
    select 1
    from public.rf_settings
    where key = v_place_setting_key
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

  v_order_number := (case when v_service.airline_code = 'azal' then 'AZAL-' when v_service.airline_code = 'izavia' then 'IZH-' else 'RF-' end)
    || 'RBX-' || to_char(now(), 'YYMMDD') || '-'
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



-- Current Alliance Miles behavior, kept in sync with the ordered migration.
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
     or p_airline_code not in ('royal', 'azal', 'izavia')
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

  v_order_number := (case when p_airline_code = 'azal' then 'AZAL-' when p_airline_code = 'izavia' then 'IZH-' else 'RF-' end)
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

create or replace function public.rf_activate_izavia_purchase_code(
  p_code text, p_roblox_user_id bigint, p_gamepass_id text,
  p_place_id bigint, p_job_id text, p_ownership_verified boolean
) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp
as $function$
declare
  v_code public.rf_izavia_purchase_codes%rowtype;
  v_service public.rf_services%rowtype;
  v_activation jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  if coalesce(p_ownership_verified,false) is not true
     or p_code is null or p_code !~ '^[A-HJ-NP-Z2-9]{8}$'
     or p_roblox_user_id is null or p_roblox_user_id <= 0
     or p_gamepass_id is null or p_gamepass_id !~ '^[1-9][0-9]{0,19}$'
     or p_place_id is null or p_place_id <= 0
     or p_job_id is null or length(trim(p_job_id))=0 then
    raise exception 'invalid_izavia_purchase' using errcode='22023';
  end if;

  select * into v_code from public.rf_izavia_purchase_codes where code=p_code for update;
  if not found then raise exception 'purchase_code_not_found' using errcode='P0002'; end if;
  if v_code.used_at is not null then raise exception 'purchase_code_already_used' using errcode='P0001'; end if;
  if v_code.expires_at <= now() then raise exception 'purchase_code_expired' using errcode='P0001'; end if;
  if v_code.started_at is null or v_code.started_by_roblox_user_id is distinct from p_roblox_user_id then
    raise exception 'purchase_code_not_started_by_player' using errcode='42501';
  end if;
  if v_code.gamepass_id is distinct from p_gamepass_id then raise exception 'purchase_gamepass_mismatch' using errcode='42501'; end if;
  if not exists(select 1 from public.rf_profiles where id=v_code.profile_id and roblox_user_id=p_roblox_user_id) then
    raise exception 'roblox_account_not_linked' using errcode='42501';
  end if;

  select * into v_service from public.rf_services
  where id=v_code.service_id and airline_code='izavia' and active=true
    and payment_mode in ('roblox_only','both') and roblox_enabled=true
    and roblox_gamepass_id=p_gamepass_id and coalesce(robux_price,0)>0
  for update;
  if not found then raise exception 'service_or_gamepass_changed' using errcode='P0001'; end if;
  if not exists(select 1 from public.rf_settings where key='roblox_place_ids_izavia'
    and value @> jsonb_build_array(p_place_id::text)) then
    raise exception 'izavia_place_not_allowed' using errcode='42501';
  end if;

  v_activation := public.rf_activate_roblox_gamepass(p_roblox_user_id,v_code.service_id,p_gamepass_id,p_place_id,p_job_id);
  if coalesce((v_activation->>'ok')::boolean,false) is not true then
    raise exception 'izavia_gamepass_activation_failed:%',coalesce(v_activation->>'reason','unknown') using errcode='P0001';
  end if;
  update public.rf_izavia_purchase_codes set used_at=now() where code=p_code and used_at is null;
  return v_activation || jsonb_build_object('purchaseCodeUsed',true);
end;
$function$;

revoke all on function public.rf_activate_izavia_purchase_code(text,bigint,text,bigint,text,boolean)
  from public, anon, authenticated;
grant execute on function public.rf_activate_izavia_purchase_code(text,bigint,text,bigint,text,boolean)
  to service_role;
