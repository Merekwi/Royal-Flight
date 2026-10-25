import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmac(keyBytes: Uint8Array, data: string): Promise<ArrayBuffer> {
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
}

async function verifyTelegramInitData(initData: string, botToken: string): Promise<Record<string, string> | null> {
  const params = new URLSearchParams(initData);
  const receivedHash = params.get("hash");
  if (!receivedHash) return null;
  params.delete("hash");
  const pairs = Array.from(params.entries()).sort(([a], [b]) => a.localeCompare(b));
  const checkString = pairs.map(([key, value]) => `${key}=${value}`).join("\n");
  const secret = await hmac(new TextEncoder().encode("WebAppData"), botToken);
  const calculatedHash = hex(await hmac(new Uint8Array(secret), checkString));
  if (calculatedHash.length !== receivedHash.length) return null;
  let diff = 0;
  for (let i = 0; i < calculatedHash.length; i++) diff |= calculatedHash.charCodeAt(i) ^ receivedHash.charCodeAt(i);
  if (diff !== 0) return null;

  const authDate = Number(params.get("auth_date"));
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(authDate) || authDate > now + 30 || now - authDate > 86400) return null;
  const userRaw = params.get("user");
  if (!userRaw) return null;
  try {
    const user = JSON.parse(userRaw);
    if (!user || !Number.isSafeInteger(user.id) || user.id <= 0) return null;
    return {
      telegram_id: String(user.id),
      telegram_username: typeof user.username === "string" ? user.username : "",
      display_name: [user.first_name, user.last_name].filter((v) => typeof v === "string" && v.length).join(" ").slice(0, 120),
    };
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!botToken || !supabaseUrl || !serviceKey) {
    return new Response(JSON.stringify({ error: "server_not_configured", message: "Настройте серверные секреты Telegram и Supabase." }), { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }

  try {
    const body = await req.json();
    if (typeof body?.initData !== "string" || body.initData.length > 10000) {
      return new Response(JSON.stringify({ error: "invalid_init_data" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const verified = await verifyTelegramInitData(body.initData, botToken);
    if (!verified) return new Response(JSON.stringify({ error: "telegram_verification_failed" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const ownerSetting = await db.from("rf_settings").select("value").eq("key","owner_telegram_id").maybeSingle();
    const ownerValue = ownerSetting.data?.value;
    const isConfiguredOwner = ownerValue !== null && ownerValue !== undefined && String(ownerValue).replace(/^"|"$/g,"") === verified.telegram_id;
    const profilePatch = {
      telegram_id: verified.telegram_id,
      telegram_username: verified.telegram_username || null,
      display_name: verified.display_name || null,
      updated_at: new Date().toISOString(),
      ...(isConfiguredOwner ? { role: "owner" } : {}),
    };
    const { data, error } = await db.from("rf_profiles").upsert(profilePatch, { onConflict: "telegram_id" })
      .select("id,telegram_id,telegram_username,display_name,role,miles,roblox_username").single();

    if (error || !data) {
      console.error("profile_upsert_failed", error?.message);
      return new Response(JSON.stringify({ error: "profile_upsert_failed" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    return new Response(JSON.stringify({ profile: data }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" } });
  } catch {
    return new Response(JSON.stringify({ error: "bad_request" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});