import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const expectedSecret = Deno.env.get("ROBLOX_SERVER_SECRET");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!expectedSecret || !url || !serviceKey) return json({ error: "server_not_configured" }, 503);
  const suppliedSecret = req.headers.get("x-rf-server-secret") || "";
  if (suppliedSecret.length !== expectedSecret.length) return json({ error: "unauthorized" }, 401);
  let mismatch = 0;
  for (let i = 0; i < expectedSecret.length; i++) mismatch |= expectedSecret.charCodeAt(i) ^ suppliedSecret.charCodeAt(i);
  if (mismatch !== 0) return json({ error: "unauthorized" }, 401);

  try {
    const body = await req.json();
    const userId = Number(body?.robloxUserId);
    const placeId = Number(body?.placeId);
    const jobId = typeof body?.jobId === "string" ? body.jobId.slice(0, 100) : "";
    const action = body?.action;
    if (!Number.isSafeInteger(placeId) || placeId <= 0 || !jobId ||
        (action !== "heartbeat_batch" && (!Number.isSafeInteger(userId) || userId <= 0))) {
      return json({ error: "invalid_request" }, 400);
    }
    const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const setting = await db.from("rf_settings").select("value").eq("key", "roblox_place_ids").maybeSingle();
    const allowed = Array.isArray(setting.data?.value) ? setting.data.value.map((x: unknown) => String(x)) : [];
    if (!allowed.includes(String(placeId))) return json({ error: "place_not_allowed" }, 403);

    if (action === "link") {
      const code = typeof body?.code === "string" ? body.code.trim().toUpperCase() : "";
      const username = typeof body?.robloxUsername === "string" ? body.robloxUsername.trim().slice(0, 100) : "";
      if (!/^[A-HJ-NP-Z2-9]{8}$/.test(code) || !username) return json({ error: "invalid_link_request" }, 400);
      const result = await db.rpc("rf_roblox_link_account", {
        p_code: code, p_roblox_user_id: userId, p_roblox_username: username
      });
      if (result.error) {
        const message = result.error.message || "";
        if (message.includes("already_linked")) return json({ error: "roblox_account_already_linked" }, 409);
        if (message.includes("invalid_or_expired")) return json({ error: "link_code_expired" }, 409);
        return json({ error: "link_failed" }, 400);
      }
      return json({ ok: true, robloxUsername: result.data?.roblox_username });
    }

    if (action === "catalog") {
      const airlineCode = typeof body?.airlineCode === "string" ? body.airlineCode : "";
      if (!["royal","azal"].includes(airlineCode)) return json({ error: "invalid_airline_code" }, 400);
      const [profile, services] = await Promise.all([
        db.from("rf_profiles").select("display_name,roblox_username").eq("roblox_user_id", userId).maybeSingle(),
        db.from("rf_services")
          .select("id,airline_code,code,name,description,duration_days,payment_mode,roblox_gamepass_id,robux_price")
          .eq("airline_code", airlineCode).eq("active", true).in("payment_mode", ["roblox_only","both"]).eq("roblox_enabled", true)
          .order("sort_order")
      ]);
      if (services.error) return json({ error: "catalog_load_failed" }, 503);
      return json({
        ok: true,
        airlineCode,
        linked: !!profile.data,
        profile: profile.data || null,
        services: (services.data || []).filter((s: any) => s.roblox_gamepass_id && Number(s.robux_price) > 0).map((s: any) => ({
          id: s.id, airlineCode: s.airline_code, code: s.code, name: s.name,
          description: s.description, durationDays: s.duration_days,
          gamePassId: s.roblox_gamepass_id, robuxPrice: s.robux_price,
          gamePassUrl: "https://www.roblox.com/game-pass/" + s.roblox_gamepass_id
        }))
      });
    }

    if (action === "entitlements") {
      const profile = await db.from("rf_profiles").select("id").eq("roblox_user_id", userId).maybeSingle();
      if (profile.error) return json({ error: "profile_lookup_failed" }, 503);
      if (!profile.data) return json({ error: "account_not_linked" }, 403);
      const now = new Date().toISOString();
      const subscriptions = await db.from("rf_subscriptions")
        .select("id,airline_code,service_id,starts_at,ends_at,status")
        .eq("profile_id", profile.data.id).eq("status", "active").gt("ends_at", now)
        .order("ends_at");
      if (subscriptions.error) return json({ error: "entitlements_load_failed" }, 503);
      const serviceIds = [...new Set((subscriptions.data || []).map((s: any) => s.service_id))];
      const services = serviceIds.length
        ? await db.from("rf_services").select("id,airline_code,code,name").in("id", serviceIds)
        : { data: [], error: null };
      if (services.error) return json({ error: "entitlements_load_failed" }, 503);
      const serviceById = new Map((services.data || []).map((s: any) => [s.id, s]));
      return json({
        ok: true,
        entitlements: (subscriptions.data || []).map((s: any) => ({
          id: s.id, airlineCode: s.airline_code, serviceId: s.service_id,
          startsAt: s.starts_at, endsAt: s.ends_at, status: s.status,
          service: serviceById.get(s.service_id) || null
        }))
      });
    }

    if (action === "activate_gamepass") {
      const serviceId = typeof body?.serviceId === "string" ? body.serviceId : "";
      const gamePassId = typeof body?.gamePassId === "string" ? body.gamePassId : "";
      if (!serviceId || !/^[1-9][0-9]{0,19}$/.test(gamePassId) || body?.ownershipVerified !== true) {
        return json({ error: "invalid_verified_purchase" }, 400);
      }
      const activation = await db.rpc("rf_activate_roblox_gamepass", {
        p_roblox_user_id: userId,
        p_service_id: serviceId,
        p_gamepass_id: gamePassId,
        p_place_id: placeId,
        p_job_id: jobId
      });
      if (activation.error) {
        console.error("roblox_gamepass_activation_failed", activation.error.message);
        return json({ error: "gamepass_activation_failed" }, 409);
      }
      if (activation.data?.ok !== true) {
        return json({ error: activation.data?.reason || "gamepass_not_activated", result: activation.data }, 409);
      }
      return json(activation.data);
    }

    if (action === "heartbeat_batch") {
      const rawPlayers = Array.isArray(body?.players) ? body.players : null;
      if (!rawPlayers || rawPlayers.length > 100) return json({ error: "invalid_players_list" }, 400);
      const playerIds = [...new Set(rawPlayers.map((value: unknown) => Number(value)))];
      if (playerIds.some((id: number) => !Number.isSafeInteger(id) || id <= 0)) {
        return json({ error: "invalid_players_list" }, 400);
      }
      const now = new Date().toISOString();
      const results = [];
      for (const playerId of playerIds) {
        const result = await db.rpc("rf_roblox_heartbeat", {
          p_roblox_user_id: playerId, p_place_id: placeId, p_job_id: jobId, p_now: now
        });
        if (result.error) {
          console.error("roblox_batch_heartbeat_failed", playerId, result.error.message);
          results.push({ robloxUserId: playerId, ok: false, reason: "heartbeat_failed" });
        } else {
          results.push({ robloxUserId: playerId, ...(result.data || { ok: true }) });
        }
      }
      return json({
        ok: true,
        processed: results.length,
        linked: results.filter((item: any) => item.ok === true).length,
        unlinked: results.filter((item: any) => item.reason === "account_not_linked").length,
        results
      });
    }

    if (action === "heartbeat") {
      const result = await db.rpc("rf_roblox_heartbeat", {
        p_roblox_user_id: userId, p_place_id: placeId, p_job_id: jobId, p_now: new Date().toISOString()
      });
      if (result.error) return json({ error: "heartbeat_failed" }, 500);
      return json(result.data || { ok: true });
    }

    if (action === "leave") {
      const result = await db.from("rf_online_sessions").update({ ended_at: new Date().toISOString() })
        .eq("roblox_user_id", userId).eq("place_id", placeId).eq("job_id", jobId).is("ended_at", null);
      if (result.error) return json({ error: "session_close_failed" }, 500);
      return json({ ok: true });
    }

    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    console.error("roblox-api error", error instanceof Error ? error.message : "unknown");
    return json({ error: "internal_error" }, 500);
  }
});
