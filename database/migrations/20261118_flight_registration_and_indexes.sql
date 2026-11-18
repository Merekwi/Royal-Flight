-- Cover composite airline foreign keys and make flight registration a real server-side operation.
create index if not exists rf_flight_registrations_flight_airline_idx
  on public.rf_flight_registrations(flight_id,airline_code);
create index if not exists rf_orders_payment_airline_idx
  on public.rf_orders(payment_method_id,airline_code);
create index if not exists rf_orders_service_airline_idx
  on public.rf_orders(service_id,airline_code);
create index if not exists rf_subscriptions_order_airline_idx
  on public.rf_subscriptions(source_order_id,airline_code);
create index if not exists rf_subscriptions_service_airline_idx
  on public.rf_subscriptions(service_id,airline_code);

create or replace function public.rf_register_flight(
  p_flight_id uuid, p_profile_id uuid, p_airline_code text
) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp
as $$
declare
  v_flight public.rf_flights%rowtype;
  v_existing public.rf_flight_registrations%rowtype;
  v_count integer;
  v_registration_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  if p_airline_code not in ('royal','azal') then
    raise exception 'invalid_airline' using errcode='22023';
  end if;

  select * into v_flight
  from public.rf_flights
  where id=p_flight_id and airline_code=p_airline_code
  for update;
  if not found then raise exception 'flight_not_found' using errcode='P0002'; end if;
  if v_flight.status not in ('scheduled','boarding') then
    raise exception 'registration_closed' using errcode='P0001';
  end if;
  if v_flight.departure_at<=now() then
    raise exception 'flight_already_departed' using errcode='P0001';
  end if;
  if v_flight.registration_deadline is not null and v_flight.registration_deadline<=now() then
    raise exception 'registration_deadline_passed' using errcode='P0001';
  end if;

  select * into v_existing
  from public.rf_flight_registrations
  where flight_id=p_flight_id and profile_id=p_profile_id
  for update;
  if found and v_existing.status in ('registered','checked_in') then
    return jsonb_build_object('ok',true,'already_registered',true,'registration_id',v_existing.id);
  end if;

  if v_flight.capacity is not null then
    select count(*) into v_count
    from public.rf_flight_registrations
    where flight_id=p_flight_id and airline_code=p_airline_code and status in ('registered','checked_in');
    if v_count>=v_flight.capacity then raise exception 'flight_full' using errcode='P0001'; end if;
  end if;

  if v_existing.id is not null then
    update public.rf_flight_registrations
      set status='registered',airline_code=p_airline_code,created_at=now()
      where id=v_existing.id
      returning id into v_registration_id;
  else
    insert into public.rf_flight_registrations(airline_code,flight_id,profile_id,status)
      values(p_airline_code,p_flight_id,p_profile_id,'registered')
      returning id into v_registration_id;
  end if;

  return jsonb_build_object('ok',true,'already_registered',false,'registration_id',v_registration_id);
end;
$$;
revoke all on function public.rf_register_flight(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.rf_register_flight(uuid,uuid,text) to service_role;
