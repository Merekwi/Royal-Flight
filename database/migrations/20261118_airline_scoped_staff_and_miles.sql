-- Carrier-scoped administration, while keeping one shared Royal Alliance profile and miles wallet.
create table if not exists public.rf_airline_staff (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.rf_profiles(id) on delete cascade,
  airline_code text not null check (airline_code in ('royal','azal')),
  role text not null default 'admin' check (role in ('admin')),
  created_by bigint,
  created_at timestamptz not null default now(),
  unique(profile_id,airline_code)
);

create index if not exists rf_airline_staff_airline_role_idx
  on public.rf_airline_staff(airline_code,role,profile_id);

alter table public.rf_airline_staff enable row level security;
revoke all on public.rf_airline_staff from anon,authenticated;

-- Before AZAL joined the app, all existing non-owner administrators belonged to Royal Flight.
insert into public.rf_airline_staff(profile_id,airline_code,role)
select id,'royal','admin' from public.rf_profiles where role='admin'
on conflict(profile_id,airline_code) do nothing;

-- The base profile is an alliance identity, not a carrier-specific staff role.
update public.rf_profiles set role='member',updated_at=now() where role='admin';

create or replace function public.rf_adjust_alliance_miles(
  p_profile_id uuid, p_admin_telegram_id bigint, p_delta bigint
) returns jsonb
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare
  v_profile public.rf_profiles%rowtype;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  if p_delta is null or p_delta=0 or abs(p_delta)>1000000 then
    raise exception 'invalid_miles_adjustment' using errcode='22023';
  end if;
  if not exists(select 1 from public.rf_profiles where telegram_id=p_admin_telegram_id and role='owner') then
    raise exception 'alliance_owner_required' using errcode='42501';
  end if;
  select * into v_profile from public.rf_profiles where id=p_profile_id for update;
  if not found then raise exception 'profile_not_found' using errcode='P0002'; end if;
  if v_profile.miles+p_delta<0 then raise exception 'insufficient_miles' using errcode='22023'; end if;

  update public.rf_profiles set miles=miles+p_delta,updated_at=now()
    where id=p_profile_id returning * into v_profile;

  insert into public.rf_mile_ledger(profile_id,delta,reason,metadata)
    values(p_profile_id,p_delta,'admin_adjustment',jsonb_build_object('admin_telegram_id',p_admin_telegram_id));

  insert into public.rf_admin_audit(airline_code,admin_telegram_id,action,entity_type,entity_id,details)
    values('royal',p_admin_telegram_id,'alliance_miles_adjusted','profile',p_profile_id::text,
      jsonb_build_object('delta',p_delta,'new_balance',v_profile.miles));

  return jsonb_build_object('profile_id',v_profile.id,'miles',v_profile.miles,'delta',p_delta);
end;
$$;
revoke all on function public.rf_adjust_alliance_miles(uuid,bigint,bigint) from public,anon,authenticated;
grant execute on function public.rf_adjust_alliance_miles(uuid,bigint,bigint) to service_role;

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

  if not exists(
    select 1 from public.rf_profiles p
    where p.telegram_id=p_admin_telegram_id
      and (
        p.role='owner'
        or exists(select 1 from public.rf_airline_staff s
                  where s.profile_id=p.id and s.airline_code=v_order.airline_code and s.role='admin')
      )
  ) then
    raise exception 'admin_required_for_airline' using errcode='42501';
  end if;

  if v_order.status <> 'awaiting_review' then
    raise exception 'order_not_pending_review' using errcode='P0001';
  end if;

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
