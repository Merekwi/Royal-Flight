-- Record which carrier portals an alliance member has opened.
-- This is membership metadata only; the profile and miles wallet stay global.
create table if not exists public.rf_airline_memberships (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.rf_profiles(id) on delete cascade,
  airline_code text not null check(airline_code in ('royal','azal')),
  joined_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  unique(profile_id,airline_code)
);
create index if not exists rf_airline_memberships_airline_active_idx
  on public.rf_airline_memberships(airline_code,last_active_at desc,profile_id);
alter table public.rf_airline_memberships enable row level security;
revoke all on public.rf_airline_memberships from anon,authenticated;
