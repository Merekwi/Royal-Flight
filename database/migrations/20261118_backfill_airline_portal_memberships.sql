-- Backfill portal memberships from existing carrier activity and staff assignments.
insert into public.rf_airline_memberships(profile_id,airline_code,last_active_at)
select profile_id,airline_code,now()
from (
  select profile_id,airline_code from public.rf_orders
  union
  select profile_id,airline_code from public.rf_subscriptions
  union
  select profile_id,airline_code from public.rf_flight_registrations
  union
  select profile_id,airline_code from public.rf_airline_staff
  union
  select id,'royal' from public.rf_profiles where role='owner'
  union
  select id,'azal' from public.rf_profiles where role='owner'
) existing_memberships
on conflict(profile_id,airline_code) do update set last_active_at=greatest(public.rf_airline_memberships.last_active_at,excluded.last_active_at);
