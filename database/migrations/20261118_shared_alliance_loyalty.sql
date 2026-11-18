-- A single alliance member profile and miles wallet shared by every airline portal.
-- Merge any duplicate Telegram profiles before restoring one-profile-per-Telegram uniqueness.
do $$
declare
  u record;
  v_canonical uuid;
  v_duplicate uuid;
  v_roblox_conflicts integer;
begin
  for u in
    select telegram_id
    from public.rf_profiles
    group by telegram_id
    having count(*) > 1
  loop
    select id into v_canonical
    from public.rf_profiles
    where telegram_id=u.telegram_id
    order by created_at asc, id asc
    limit 1;

    select count(distinct roblox_user_id) into v_roblox_conflicts
    from public.rf_profiles
    where telegram_id=u.telegram_id and roblox_user_id is not null;
    if v_roblox_conflicts > 1 then
      raise exception 'Cannot automatically merge Telegram %: multiple Roblox accounts are linked', u.telegram_id;
    end if;

    update public.rf_profiles p
    set miles = (select coalesce(sum(x.miles),0) from public.rf_profiles x where x.telegram_id=u.telegram_id),
        role = (select x.role from public.rf_profiles x where x.telegram_id=u.telegram_id
                order by case x.role when 'owner' then 3 when 'admin' then 2 else 1 end desc, x.created_at asc limit 1),
        roblox_user_id = (select x.roblox_user_id from public.rf_profiles x where x.telegram_id=u.telegram_id and x.roblox_user_id is not null limit 1),
        roblox_username = (select x.roblox_username from public.rf_profiles x where x.telegram_id=u.telegram_id and x.roblox_user_id is not null limit 1),
        telegram_username = coalesce(p.telegram_username,(select x.telegram_username from public.rf_profiles x where x.telegram_id=u.telegram_id and x.id<>v_canonical and x.telegram_username is not null limit 1)),
        display_name = coalesce(p.display_name,(select x.display_name from public.rf_profiles x where x.telegram_id=u.telegram_id and x.id<>v_canonical and x.display_name is not null limit 1)),
        updated_at = now()
    where p.id=v_canonical;

    for v_duplicate in
      select id from public.rf_profiles
      where telegram_id=u.telegram_id and id<>v_canonical
    loop
      update public.rf_orders set profile_id=v_canonical where profile_id=v_duplicate;
      update public.rf_subscriptions set profile_id=v_canonical where profile_id=v_duplicate;
      update public.rf_mile_ledger set profile_id=v_canonical where profile_id=v_duplicate;
      update public.rf_roblox_link_codes set profile_id=v_canonical where profile_id=v_duplicate;

      -- Keep one registration for the same member and flight.
      delete from public.rf_flight_registrations d
      using public.rf_flight_registrations c
      where d.profile_id=v_duplicate
        and c.profile_id=v_canonical
        and d.flight_id=c.flight_id;
      update public.rf_flight_registrations set profile_id=v_canonical where profile_id=v_duplicate;

      delete from public.rf_profiles where id=v_duplicate;
    end loop;
  end loop;
end $$;

-- Profile identity is alliance-wide, not airline-specific.
alter table public.rf_orders drop constraint if exists rf_orders_profile_airline_fkey;
alter table public.rf_subscriptions drop constraint if exists rf_subscriptions_profile_airline_fkey;
alter table public.rf_flight_registrations drop constraint if exists rf_flight_registrations_profile_airline_fkey;
drop index if exists public.rf_profiles_telegram_airline_uidx;
drop index if exists public.rf_profiles_id_airline_uidx;
alter table public.rf_profiles drop column if exists airline_code;
alter table public.rf_profiles add constraint rf_profiles_telegram_id_key unique(telegram_id);

-- Update order review authorization: alliance admins can review orders for either airline,
-- while the order, service, subscription and payment records remain scoped to their airline.
create or replace function public.rf_admin_review_order(
  p_order_id uuid, p_admin_telegram_id bigint, p_paid boolean, p_note text default null
) returns jsonb
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare
  v_order public.rf_orders%rowtype;
  v_service public.rf_services%rowtype;
  v_start timestamptz;
  v_end timestamptz;
  v_sub_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  select * into v_order from public.rf_orders where id=p_order_id for update;
  if not found then raise exception 'order_not_found' using errcode='P0002'; end if;
  if not exists(select 1 from public.rf_profiles where telegram_id=p_admin_telegram_id and role in ('admin','owner')) then
    raise exception 'admin_required' using errcode='42501';
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

  select * into v_service from public.rf_services
    where id=v_order.service_id and airline_code=v_order.airline_code and active=true;
  if not found then raise exception 'service_unavailable_for_airline' using errcode='P0001'; end if;

  update public.rf_orders set status='paid',paid_at=now(),admin_note=nullif(trim(coalesce(p_note,'')),''),reviewed_by=p_admin_telegram_id,reviewed_at=now()
    where id=p_order_id and airline_code=v_order.airline_code;

  select greatest(now(),coalesce(max(ends_at),now())) into v_start
    from public.rf_subscriptions
    where profile_id=v_order.profile_id and service_id=v_order.service_id
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
