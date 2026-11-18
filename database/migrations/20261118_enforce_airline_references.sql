-- Enforce same-airline references in PostgreSQL, not only in application queries.
alter table public.rf_flight_registrations
  add column if not exists airline_code text not null default 'royal';

create unique index if not exists rf_profiles_id_airline_uidx on public.rf_profiles(id,airline_code);
create unique index if not exists rf_flights_id_airline_uidx on public.rf_flights(id,airline_code);
create unique index if not exists rf_services_id_airline_uidx on public.rf_services(id,airline_code);
create unique index if not exists rf_payment_methods_id_airline_uidx on public.rf_payment_methods(id,airline_code);
create unique index if not exists rf_orders_id_airline_uidx on public.rf_orders(id,airline_code);

do $$
begin
  if not exists(select 1 from pg_constraint where conname='rf_orders_profile_airline_fkey' and conrelid='public.rf_orders'::regclass) then
    alter table public.rf_orders add constraint rf_orders_profile_airline_fkey
      foreign key(profile_id,airline_code) references public.rf_profiles(id,airline_code) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='rf_orders_service_airline_fkey' and conrelid='public.rf_orders'::regclass) then
    alter table public.rf_orders add constraint rf_orders_service_airline_fkey
      foreign key(service_id,airline_code) references public.rf_services(id,airline_code) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='rf_orders_payment_airline_fkey' and conrelid='public.rf_orders'::regclass) then
    alter table public.rf_orders add constraint rf_orders_payment_airline_fkey
      foreign key(payment_method_id,airline_code) references public.rf_payment_methods(id,airline_code) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='rf_subscriptions_profile_airline_fkey' and conrelid='public.rf_subscriptions'::regclass) then
    alter table public.rf_subscriptions add constraint rf_subscriptions_profile_airline_fkey
      foreign key(profile_id,airline_code) references public.rf_profiles(id,airline_code) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='rf_subscriptions_service_airline_fkey' and conrelid='public.rf_subscriptions'::regclass) then
    alter table public.rf_subscriptions add constraint rf_subscriptions_service_airline_fkey
      foreign key(service_id,airline_code) references public.rf_services(id,airline_code) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='rf_subscriptions_order_airline_fkey' and conrelid='public.rf_subscriptions'::regclass) then
    alter table public.rf_subscriptions add constraint rf_subscriptions_order_airline_fkey
      foreign key(source_order_id,airline_code) references public.rf_orders(id,airline_code) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='rf_flight_registrations_flight_airline_fkey' and conrelid='public.rf_flight_registrations'::regclass) then
    alter table public.rf_flight_registrations add constraint rf_flight_registrations_flight_airline_fkey
      foreign key(flight_id,airline_code) references public.rf_flights(id,airline_code) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='rf_flight_registrations_profile_airline_fkey' and conrelid='public.rf_flight_registrations'::regclass) then
    alter table public.rf_flight_registrations add constraint rf_flight_registrations_profile_airline_fkey
      foreign key(profile_id,airline_code) references public.rf_profiles(id,airline_code) not valid;
  end if;
end $$;

alter table public.rf_orders validate constraint rf_orders_profile_airline_fkey;
alter table public.rf_orders validate constraint rf_orders_service_airline_fkey;
alter table public.rf_orders validate constraint rf_orders_payment_airline_fkey;
alter table public.rf_subscriptions validate constraint rf_subscriptions_profile_airline_fkey;
alter table public.rf_subscriptions validate constraint rf_subscriptions_service_airline_fkey;
alter table public.rf_subscriptions validate constraint rf_subscriptions_order_airline_fkey;
alter table public.rf_flight_registrations validate constraint rf_flight_registrations_flight_airline_fkey;
alter table public.rf_flight_registrations validate constraint rf_flight_registrations_profile_airline_fkey;
