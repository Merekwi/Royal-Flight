-- Separate Royal Flight and AZAL passenger portals without moving or deleting existing records.
-- Existing rows inherit 'royal'; new AZAL data is stored under 'azal'.

alter table public.rf_profiles add column if not exists airline_code text not null default 'royal';
alter table public.rf_flights add column if not exists airline_code text not null default 'royal';
alter table public.rf_services add column if not exists airline_code text not null default 'royal';
alter table public.rf_payment_methods add column if not exists airline_code text not null default 'royal';
alter table public.rf_orders add column if not exists airline_code text not null default 'royal';
alter table public.rf_subscriptions add column if not exists airline_code text not null default 'royal';
alter table public.rf_notifications add column if not exists airline_code text not null default 'royal';
alter table public.rf_admin_audit add column if not exists airline_code text not null default 'royal';

alter table public.rf_profiles drop constraint if exists rf_profiles_telegram_id_key;
alter table public.rf_services drop constraint if exists rf_services_code_key;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='rf_profiles_airline_code_check' and conrelid='public.rf_profiles'::regclass) then
    alter table public.rf_profiles add constraint rf_profiles_airline_code_check check (airline_code in ('royal','azal'));
  end if;
  if not exists (select 1 from pg_constraint where conname='rf_flights_airline_code_check' and conrelid='public.rf_flights'::regclass) then
    alter table public.rf_flights add constraint rf_flights_airline_code_check check (airline_code in ('royal','azal'));
  end if;
  if not exists (select 1 from pg_constraint where conname='rf_services_airline_code_check' and conrelid='public.rf_services'::regclass) then
    alter table public.rf_services add constraint rf_services_airline_code_check check (airline_code in ('royal','azal'));
  end if;
  if not exists (select 1 from pg_constraint where conname='rf_payment_methods_airline_code_check' and conrelid='public.rf_payment_methods'::regclass) then
    alter table public.rf_payment_methods add constraint rf_payment_methods_airline_code_check check (airline_code in ('royal','azal'));
  end if;
  if not exists (select 1 from pg_constraint where conname='rf_orders_airline_code_check' and conrelid='public.rf_orders'::regclass) then
    alter table public.rf_orders add constraint rf_orders_airline_code_check check (airline_code in ('royal','azal'));
  end if;
  if not exists (select 1 from pg_constraint where conname='rf_subscriptions_airline_code_check' and conrelid='public.rf_subscriptions'::regclass) then
    alter table public.rf_subscriptions add constraint rf_subscriptions_airline_code_check check (airline_code in ('royal','azal'));
  end if;
  if not exists (select 1 from pg_constraint where conname='rf_notifications_airline_code_check' and conrelid='public.rf_notifications'::regclass) then
    alter table public.rf_notifications add constraint rf_notifications_airline_code_check check (airline_code in ('royal','azal'));
  end if;
  if not exists (select 1 from pg_constraint where conname='rf_admin_audit_airline_code_check' and conrelid='public.rf_admin_audit'::regclass) then
    alter table public.rf_admin_audit add constraint rf_admin_audit_airline_code_check check (airline_code in ('royal','azal'));
  end if;
end $$;

create unique index if not exists rf_profiles_telegram_airline_uidx on public.rf_profiles(telegram_id,airline_code);
create unique index if not exists rf_services_airline_code_uidx on public.rf_services(airline_code,code);
create index if not exists rf_flights_airline_departure_idx on public.rf_flights(airline_code,departure_at);
create index if not exists rf_services_airline_active_sort_idx on public.rf_services(airline_code,active,sort_order);
create index if not exists rf_payment_methods_airline_active_idx on public.rf_payment_methods(airline_code,active);
create index if not exists rf_orders_airline_status_created_idx on public.rf_orders(airline_code,status,created_at desc);
create index if not exists rf_notifications_airline_status_created_idx on public.rf_notifications(airline_code,status,created_at desc);
create index if not exists rf_admin_audit_airline_created_idx on public.rf_admin_audit(airline_code,created_at desc);

create or replace function public.rf_admin_review_order(
  p_order_id uuid, p_admin_telegram_id bigint, p_paid boolean, p_note text default null
) returns jsonb
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare
  v_order public.rf_orders%rowtype;
  v_service public.rf_services%rowtype;
  v_admin_airline text;
  v_start timestamptz;
  v_end timestamptz;
  v_sub_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  select * into v_order from public.rf_orders where id=p_order_id for update;
  if not found then raise exception 'order_not_found' using errcode='P0002'; end if;
  select airline_code into v_admin_airline from public.rf_profiles
    where telegram_id=p_admin_telegram_id and airline_code=v_order.airline_code and role in ('admin','owner')
    limit 1;
  if not found then raise exception 'admin_required_for_airline' using errcode='42501'; end if;
  if v_order.status <> 'awaiting_review' then raise exception 'order_not_pending_review' using errcode='P0001'; end if;

  if not p_paid then
    update public.rf_orders set status='rejected',admin_note=nullif(trim(coalesce(p_note,'')),''),reviewed_by=p_admin_telegram_id,reviewed_at=now()
      where id=p_order_id and airline_code=v_order.airline_code;
    insert into public.rf_admin_audit(airline_code,admin_telegram_id,action,entity_type,entity_id,details)
      values(v_order.airline_code,p_admin_telegram_id,'order_rejected','order',p_order_id::text,
        jsonb_build_object('order_number',v_order.order_number,'note',p_note));
    return jsonb_build_object('status','rejected','order_number',v_order.order_number,'airline_code',v_order.airline_code);
  end if;

  select * into v_service from public.rf_services
    where id=v_order.service_id and airline_code=v_order.airline_code and active=true;
  if not found then raise exception 'service_unavailable_for_airline' using errcode='P0001'; end if;

  update public.rf_orders set status='paid',paid_at=now(),admin_note=nullif(trim(coalesce(p_note,'')),''),
    reviewed_by=p_admin_telegram_id,reviewed_at=now()
    where id=p_order_id and airline_code=v_order.airline_code;

  select greatest(now(),coalesce(max(ends_at),now())) into v_start
    from public.rf_subscriptions
    where profile_id=v_order.profile_id and service_id=v_order.service_id
      and airline_code=v_order.airline_code and status='active';

  v_end:=v_start+make_interval(days=>v_service.duration_days);
  insert into public.rf_subscriptions(airline_code,profile_id,service_id,source_order_id,starts_at,ends_at,status)
    values(v_order.airline_code,v_order.profile_id,v_order.service_id,v_order.id,v_start,v_end,'active')
    returning id into v_sub_id;

  insert into public.rf_admin_audit(airline_code,admin_telegram_id,action,entity_type,entity_id,details)
    values(v_order.airline_code,p_admin_telegram_id,'order_paid_and_service_activated','order',p_order_id::text,
      jsonb_build_object('order_number',v_order.order_number,'subscription_id',v_sub_id,'starts_at',v_start,'ends_at',v_end));

  return jsonb_build_object('status','paid','order_number',v_order.order_number,'airline_code',v_order.airline_code,
    'subscription_id',v_sub_id,'starts_at',v_start,'ends_at',v_end);
end;
$$;
revoke all on function public.rf_admin_review_order(uuid,bigint,boolean,text) from public,anon,authenticated;
grant execute on function public.rf_admin_review_order(uuid,bigint,boolean,text) to service_role;
