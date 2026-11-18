alter table public.rf_profiles drop constraint if exists rf_profiles_role_check;
alter table public.rf_profiles add constraint rf_profiles_role_check check(role in ('member','owner'));