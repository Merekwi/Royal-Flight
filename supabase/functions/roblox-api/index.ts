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
    if (!Number.isSafeInteger(userId) || userId <= 0 || !Number.isSafeInteger(placeId) || placeId <= 0 || !jobId) {
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
