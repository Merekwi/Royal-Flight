create index if not exists rf_roblox_entitlements_order_airline_idx
  on public.rf_roblox_entitlements (order_id, airline_code);

create index if not exists rf_roblox_entitlements_service_airline_idx
  on public.rf_roblox_entitlements (service_id, airline_code);

create index if not exists rf_roblox_entitlements_subscription_idx
  on public.rf_roblox_entitlements (subscription_id);
