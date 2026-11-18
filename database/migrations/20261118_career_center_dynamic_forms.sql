create table if not exists public.rf_career_forms (
  id uuid primary key default gen_random_uuid(),
  airline_code text not null check (airline_code in ('royal','azal')),
  title text not null check (char_length(trim(title)) between 3 and 120),
  department text,
  description text,
  schema jsonb not null default '{"version":1,"sections":[]}'::jsonb,
  status text not null default 'draft' check (status in ('draft','open','closed','archived')),
  closes_at timestamptz,
  published_at timestamptz,
  created_by bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, airline_code)
);
create table if not exists public.rf_career_applications (
  id uuid primary key default gen_random_uuid(),
  form_id uuid not null,
  airline_code text not null check (airline_code in ('royal','azal')),
  profile_id uuid not null references public.rf_profiles(id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  status text not null default 'submitted' check (status in ('submitted','reviewing','interview','accepted','rejected','withdrawn')),
  admin_note text,
  reviewed_by bigint,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rf_career_applications_form_airline_fkey foreign key (form_id,airline_code)
    references public.rf_career_forms(id,airline_code) on delete cascade,
  constraint rf_career_applications_once_per_form unique (form_id,profile_id)
);
create index if not exists rf_career_forms_airline_status_idx on public.rf_career_forms(airline_code,status,created_at desc);
create index if not exists rf_career_forms_open_closes_idx on public.rf_career_forms(airline_code,closes_at) where status='open';
create index if not exists rf_career_applications_airline_status_idx on public.rf_career_applications(airline_code,status,created_at desc);
create index if not exists rf_career_applications_profile_idx on public.rf_career_applications(profile_id,airline_code,created_at desc);
create index if not exists rf_career_applications_form_idx on public.rf_career_applications(form_id,airline_code,created_at desc);
alter table public.rf_career_forms enable row level security;
alter table public.rf_career_applications enable row level security;
revoke all on public.rf_career_forms from anon,authenticated;
revoke all on public.rf_career_applications from anon,authenticated;
grant select,insert,update,delete on public.rf_career_forms to service_role;
grant select,insert,update,delete on public.rf_career_applications to service_role;
