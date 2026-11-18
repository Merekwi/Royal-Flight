-- Royal Alliance: harden Roblox online mileage heartbeat processing.
-- The Edge Function sends one batch containing the currently connected player IDs.

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
  v_rate integer := 10;
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
    )
    values (p_roblox_user_id, p_place_id, p_job_id, p_now, p_now, 0)
    on conflict (roblox_user_id, job_id) do nothing;

    select * into v_session
    from public.rf_online_sessions
    where roblox_user_id = p_roblox_user_id and job_id = p_job_id
    for update;
  end if;

  if v_session.ended_at is not null then
    update public.rf_online_sessions
    set place_id = p_place_id,
        started_at = p_now,
        last_heartbeat_at = p_now,
        ended_at = null,
        credited_seconds = 0
    where id = v_session.id
    returning * into v_session;
    v_total := 0;
  else
    v_elapsed := greatest(
      0,
      least(90, floor(extract(epoch from (p_now - v_session.last_heartbeat_at)))::integer)
    );
    v_total := v_session.credited_seconds + v_elapsed;
    v_old_minutes := floor(v_session.credited_seconds / 60.0)::integer;
    v_new_minutes := floor(v_total / 60.0)::integer;

    select coalesce((value #>> '{}')::integer, 10)
    into v_rate
    from public.rf_settings
    where key = 'miles_per_minute';

    v_delta := (v_new_minutes - v_old_minutes) * coalesce(v_rate, 10);

    update public.rf_online_sessions
    set place_id = p_place_id,
        last_heartbeat_at = p_now,
        credited_seconds = v_total
    where id = v_session.id;

    if v_delta > 0 then
      v_source_key :=
        'roblox:' || p_roblox_user_id::text || ':' || p_job_id || ':' ||
        to_char(v_session.started_at at time zone 'UTC', 'YYYYMMDDHH24MISSUS') || ':' ||
        v_new_minutes::text;

      insert into public.rf_mile_ledger(profile_id, delta, reason, source_key, metadata)
      values (
        v_profile.id,
        v_delta,
        'roblox_online_minutes',
        v_source_key,
        jsonb_build_object(
          'place_id', p_place_id,
          'job_id', p_job_id,
          'credited_seconds', v_total,
          'miles_per_minute', coalesce(v_rate, 10)
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

  return jsonb_build_object(
    'ok', true,
    'credited_seconds', v_total,
    'miles_added', v_delta
  );
end;
$function$;

revoke all on function public.rf_roblox_heartbeat(bigint, bigint, text, timestamptz)
from public, anon, authenticated;
grant execute on function public.rf_roblox_heartbeat(bigint, bigint, text, timestamptz)
to service_role;
