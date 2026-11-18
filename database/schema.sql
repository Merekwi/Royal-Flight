-- Royal Flight Platform schema. Keep browser roles locked; use trusted Edge Functions.
create extension if not exists pgcrypto;
create table public.rf_profiles (id uuid primary key default gen_random_uuid(), telegram_id bigint unique not null, telegram_username text, display_name text, roblox_user_id bigint unique, roblox_username text, role text not null default 'member' check(role in ('member','owner')), miles bigint not null default 0 check(miles>=0), created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_airline_staff (id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.rf_profiles(id) on delete cascade, airline_code text not null check(airline_code in ('royal','azal')), role text not null default 'admin' check(role='admin'), created_by bigint, created_at timestamptz not null default now(), unique(profile_id,airline_code));
create table public.rf_airline_memberships (id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.rf_profiles(id) on delete cascade, airline_code text not null check(airline_code in ('royal','azal')), joined_at timestamptz not null default now(), last_active_at timestamptz not null default now(), unique(profile_id,airline_code));
create table public.rf_flights (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal')), title text not null, flight_number text, origin text not null, destination text not null, aircraft text, departure_at timestamptz not null, registration_deadline timestamptz, capacity integer check(capacity is null or capacity>0), status text not null default 'scheduled' check(status in ('draft','scheduled','boarding','departed','completed','cancelled')), description text, created_by bigint, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_flight_registrations (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal')), flight_id uuid not null references public.rf_flights(id) on delete cascade, profile_id uuid not null references public.rf_profiles(id) on delete cascade, status text not null default 'registered' check(status in ('registered','cancelled','checked_in')), created_at timestamptz not null default now(), unique(flight_id,profile_id));
create table public.rf_services (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal')), code text not null, name text not null, description text, price numeric(12,2) not null check(price>=0), currency text not null default 'RUB', duration_days integer not null check(duration_days>0), active boolean not null default true, sort_order integer not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.rf_payment_methods (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal')), label text not null, card_number text not null, recipient_name text, instructions text, active boolean not null default true, created_at timestamptz not null default now());
create table public.rf_orders (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal')), order_number text unique not null, profile_id uuid not null references public.rf_profiles(id), service_id uuid not null references public.rf_services(id), payment_method_id uuid references public.rf_payment_methods(id), amount numeric(12,2) not null check(amount>=0), currency text not null default 'RUB', status text not null default 'awaiting_payment' check(status in ('awaiting_payment','awaiting_review','paid','rejected','cancelled')), proof_url text, user_note text, admin_note text, reviewed_by bigint, reviewed_at timestamptz, created_at timestamptz not null default now(), paid_at timestamptz);
create table public.rf_subscriptions (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal')), profile_id uuid not null references public.rf_profiles(id) on delete cascade, service_id uuid not null references public.rf_services(id), source_order_id uuid not null unique references public.rf_orders(id), starts_at timestamptz not null, ends_at timestamptz not null, status text not null default 'active' check(status in ('active','expired','revoked')), created_at timestamptz not null default now(), check(ends_at>starts_at));
create table public.rf_mile_ledger (id uuid primary key default gen_random_uuid(), profile_id uuid not null references public.rf_profiles(id) on delete cascade, delta bigint not null check(delta<>0), reason text not null, source_key text unique, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create table public.rf_online_sessions (id uuid primary key default gen_random_uuid(), roblox_user_id bigint not null, place_id bigint not null, job_id text not null, started_at timestamptz not null default now(), last_heartbeat_at timestamptz not null default now(), ended_at timestamptz, credited_seconds integer not null default 0 check(credited_seconds>=0), unique(roblox_user_id,job_id));
create table public.rf_notifications (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal')), title text not null, body text not null, audience text not null default 'all' check(audience in ('all','admins','roblox_linked','active_service')), scheduled_at timestamptz, sent_at timestamptz, status text not null default 'draft' check(status in ('draft','scheduled','sent','failed')), created_by bigint, created_at timestamptz not null default now());
create table public.rf_settings (key text primary key, value jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now(), updated_by bigint);
create table public.rf_admin_audit (id uuid primary key default gen_random_uuid(), airline_code text not null default 'royal' check(airline_code in ('royal','azal')), admin_telegram_id bigint not null, action text not null, entity_type text, entity_id text, details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
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
 if p_airline_code not in ('royal','azal') then raise exception 'invalid_airline' using errcode='22023'; end if;
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
