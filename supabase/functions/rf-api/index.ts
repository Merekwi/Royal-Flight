import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Content-Type": "application/json",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
const hex = (buffer: ArrayBuffer) => Array.from(new Uint8Array(buffer)).map((b) => b.toString(16).padStart(2, "0")).join("");
async function hmac(keyBytes: Uint8Array, data: string): Promise<ArrayBuffer> {
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
}
async function verifyInitData(initData: string, botToken: string) {
  const params = new URLSearchParams(initData);
  const hash = params.get("hash");
  if (!hash) return null;
  params.delete("hash");
  const checkString = Array.from(params.entries()).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([k,v]) => `${k}=${v}`).join("\n");
  const secret = await hmac(new TextEncoder().encode("WebAppData"), botToken);
  const expected = hex(await hmac(new Uint8Array(secret), checkString));
  if (expected.length !== hash.length) return null;
  let diff = 0;
  for (let i=0;i<expected.length;i++) diff |= expected.charCodeAt(i) ^ hash.charCodeAt(i);
  if (diff !== 0) return null;
  const authDate = Number(params.get("auth_date"));
  const now = Math.floor(Date.now()/1000);
  if (!Number.isFinite(authDate) || authDate > now + 30 || now - authDate > 86400) return null;
  try {
    const user = JSON.parse(params.get("user") || "null");
    if (!user || !Number.isSafeInteger(user.id) || user.id <= 0) return null;
    return { id: String(user.id), username: typeof user.username === "string" ? user.username : null,
      name: [user.first_name,user.last_name].filter((x) => typeof x === "string" && x).join(" ").slice(0,120) };
  } catch { return null; }
}
function validText(v: unknown, max=300): v is string { return typeof v === "string" && v.trim().length > 0 && v.length <= max; }

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!botToken || !url || !key) return json({ error: "server_not_configured", message: "Не настроены секреты сервера." }, 503);

  try {
    const body = await req.json();
    if (!validText(body?.initData, 10000) || !validText(body?.action, 64)) return json({ error: "invalid_request" }, 400);
    const airlineCode = body.airlineCode;
    if (airlineCode !== "royal" && airlineCode !== "azal") return json({ error: "invalid_airline_code" }, 400);
    const telegram = await verifyInitData(body.initData, botToken);
    if (!telegram) return json({ error: "telegram_verification_failed" }, 401);
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

    const ownerSetting = await db.from("rf_settings").select("value").eq("key","owner_telegram_id").maybeSingle();
    const ownerValue = ownerSetting.data?.value;
    const isConfiguredOwner = ownerValue !== null && ownerValue !== undefined && String(ownerValue).replace(/^"|"$/g,"") === telegram.id;
    const { data: profile, error: profileError } = await db.from("rf_profiles").upsert({
      telegram_id: telegram.id, telegram_username: telegram.username,
      display_name: telegram.name || null, updated_at: new Date().toISOString(),
      ...(isConfiguredOwner ? { role: "owner" } : {})
    }, { onConflict: "telegram_id" })
      .select("id,telegram_id,telegram_username,display_name,role,miles,roblox_username").single();
    if (profileError || !profile) {
      console.error("profile_upsert_failed", profileError?.message || "profile row missing");
      return json({ error: "profile_unavailable", message: "База данных не смогла сохранить профиль Telegram." }, 503);
    }

    const staffMembership = await db.from("rf_airline_staff").select("role").eq("profile_id", profile.id).eq("airline_code", airlineCode).maybeSingle();
    if (staffMembership.error) {
      console.error("airline_staff_lookup_failed", staffMembership.error.message);
      return json({ error: "staff_access_check_failed" }, 503);
    }
    const isOwner = profile.role === "owner";
    const airlineRole = isOwner ? "owner" : (staffMembership.data?.role || "member");
    const portalProfile = { ...profile, role: airlineRole };
    const membership = await db.from("rf_airline_memberships").upsert({
      profile_id:profile.id,airline_code:airlineCode,last_active_at:new Date().toISOString()
    },{onConflict:"profile_id,airline_code"});
    if(membership.error){
      console.error("airline_membership_upsert_failed",membership.error.message);
      return json({error:"airline_membership_unavailable"},503);
    }
    const admin = isOwner || airlineRole === "admin";
    const action = body.action;

    if (action === "create_roblox_link") {
      if (airlineCode !== "royal") return json({ error: "feature_not_available_for_airline", message: "Привязка Roblox доступна только в портале Royal Flight." }, 403);
      const codeChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
      const bytes = crypto.getRandomValues(new Uint8Array(8));
      const linkCode = Array.from(bytes, b => codeChars[b % codeChars.length]).join("");
      await db.from("rf_roblox_link_codes").update({used_at:new Date().toISOString()}).eq("profile_id",profile.id).is("used_at",null);
      const created = await db.from("rf_roblox_link_codes").insert({profile_id:profile.id,code:linkCode,expires_at:new Date(Date.now()+10*60*1000).toISOString()}).select("expires_at").single();
      if(created.error) return json({error:"roblox_link_code_failed"},500);
      return json({linkCode,expiresAt:created.data.expires_at,minutesValid:10});
    }

    if (action === "dashboard") {
      const now = new Date().toISOString();
      const [flights, services, orders, subscriptions, ledger, announcements, paymentMethods, flightRegistrations] = await Promise.all([
        db.from("rf_flights").select("id,title,flight_number,origin,destination,aircraft,departure_at,registration_deadline,capacity,status,description").eq("airline_code", airlineCode).in("status", ["scheduled","boarding"]).gte("departure_at", now).order("departure_at").limit(20),
        db.from("rf_services").select("id,code,name,description,price,currency,duration_days,payment_mode,roblox_enabled,roblox_gamepass_id,robux_price").eq("airline_code", airlineCode).eq("active", true).order("sort_order"),
        db.from("rf_orders").select("id,order_number,service_id,payment_method_id,amount,currency,status,created_at,paid_at,admin_note,payment_provider,payment_reference").eq("profile_id", profile.id).eq("airline_code", airlineCode).order("created_at", { ascending: false }).limit(20),
        db.from("rf_subscriptions").select("id,service_id,starts_at,ends_at,status").eq("profile_id", profile.id).eq("airline_code", airlineCode).eq("status","active").gt("ends_at", now).order("ends_at"),
        db.from("rf_mile_ledger").select("id,delta,reason,created_at,metadata").eq("profile_id", profile.id).order("created_at", { ascending: false }).limit(30),
        db.from("rf_notifications").select("id,title,body,sent_at,created_at").eq("airline_code", airlineCode).eq("status","sent").order("sent_at", { ascending: false }).limit(10),
        db.from("rf_payment_methods").select("id,label,card_number,recipient_name,instructions").eq("airline_code", airlineCode).eq("active", true).order("created_at"),
        db.from("rf_flight_registrations").select("id,flight_id,status,created_at").eq("profile_id",profile.id).eq("airline_code",airlineCode).in("status",["registered","checked_in"])
      ]);
      const err = [flights,services,orders,subscriptions,ledger,announcements,paymentMethods,flightRegistrations].find(x=>x.error);
      if (err) {
        const detail = err.error?.message || "unknown database query error";
        const code = err.error?.code || null;
        console.error("dashboard_query_failed", { code, message: detail });
        const unavailable = /connection|timeout|unavailable|terminat/i.test(detail) || (typeof code === "string" && code.startsWith("08"));
        return json({
          error: "dashboard_load_failed",
          message: unavailable
            ? "База данных временно недоступна. Повторите загрузку через несколько секунд."
            : "Не удалось прочитать данные кабинета. Проверьте схему и права доступа к таблицам."
        }, unavailable ? 503 : 500);
      }
      let pendingOrders: unknown[] = [];
      let adminUsers: unknown[] = [];
      if (admin) {
        const [pending, users, serviceCatalog] = await Promise.all([
          db.from("rf_orders").select("id,order_number,profile_id,service_id,amount,currency,status,proof_url,user_note,created_at").eq("airline_code", airlineCode).eq("status","awaiting_review").order("created_at"),
          db.from("rf_profiles").select("id,telegram_id,telegram_username,display_name,role,miles,roblox_username").order("created_at",{ascending:false}).limit(100),
          db.from("rf_services").select("id,airline_code,code,name,description,price,currency,duration_days,active,sort_order,payment_mode,roblox_enabled,roblox_gamepass_id,robux_price").eq("airline_code",airlineCode).order("sort_order")
        ]);
        if (!pending.error) pendingOrders = pending.data || [];
        if (!users.error) adminUsers = users.data || [];
        var adminServiceCatalog = serviceCatalog.error ? [] : (serviceCatalog.data || []);
      }
      const serviceById = new Map((services.data || []).map((s) => [s.id, s]));
      const activeSubscriptions = (subscriptions.data || []).map((s) => ({ ...s, service: serviceById.get(s.service_id) || null }));
      if (admin) {
        const staff = await db.from("rf_airline_staff").select("profile_id,role").eq("airline_code", airlineCode);
        if (staff.error) return json({ error: "airline_staff_load_failed" }, 503);
        const roleByProfile = new Map((staff.data || []).map((s) => [s.profile_id, s.role]));
        adminUsers = adminUsers.map((u: any) => ({ ...u, role: u.role === "owner" ? "owner" : (roleByProfile.get(u.id) || "member") }));
      }
      return json({ airlineCode, profile: portalProfile, flights: flights.data || [], services: services.data || [], orders: orders.data || [],
        subscriptions: activeSubscriptions, flightRegistrations: flightRegistrations.data || [], mileLedger: ledger.data || [], announcements: announcements.data || [], paymentMethods: paymentMethods.data || [],
        admin: admin ? { pendingOrders, users: adminUsers, services: adminServiceCatalog } : null });
    }

    if (action === "register_flight") {
      if (!validText(body.flightId,64)) return json({error:"flight_id_required"},400);
      const result=await db.rpc("rf_register_flight",{
        p_flight_id:body.flightId,p_profile_id:profile.id,p_airline_code:airlineCode
      });
      if(result.error){
        const message=result.error.message||"";
        const known=["flight_not_found","registration_closed","flight_already_departed","registration_deadline_passed","flight_full"];
        const code=known.find(x=>message.includes(x))||"flight_registration_failed";
        return json({error:code},code==="flight_registration_failed"?500:409);
      }
      return json({registration:result.data});
    }

    if (action === "create_order") {
      if (!validText(body.serviceId, 64) || !validText(body.paymentMethodId, 64)) return json({ error: "service_and_payment_method_required" }, 400);
      const [serviceResult, methodResult] = await Promise.all([
        db.from("rf_services").select("id,price,currency,active,payment_mode").eq("id",body.serviceId).eq("airline_code", airlineCode).eq("active",true).maybeSingle(),
        db.from("rf_payment_methods").select("id,active").eq("id",body.paymentMethodId).eq("airline_code", airlineCode).eq("active",true).maybeSingle()
      ]);
      if (!serviceResult.data || !methodResult.data) return json({ error: "service_or_payment_method_unavailable" }, 400);
      if (serviceResult.data.payment_mode === "roblox_only") {
        return json({ error: "service_requires_roblox_payment", message: "Эту услугу можно оплатить только в Roblox за Robux." }, 409);
      }
      const orderPrefix = airlineCode === "azal" ? "AZAL-" : "RF-";
      const orderNumber = orderPrefix + new Date().toISOString().slice(2,10).replaceAll("-","") + "-" + crypto.randomUUID().replaceAll("-","").slice(0,6).toUpperCase();
      const created = await db.from("rf_orders").insert({ airline_code: airlineCode, order_number: orderNumber, profile_id: profile.id, service_id: serviceResult.data.id,
        payment_method_id: methodResult.data.id, amount: serviceResult.data.price, currency: serviceResult.data.currency, status: "awaiting_payment" })
        .select("id,order_number,amount,currency,status,created_at").single();
      if (created.error) return json({ error: "order_creation_failed" }, 500);
      return json({ order: created.data });
    }

    if (action === "mark_paid") {
      if (!validText(body.orderId,64)) return json({ error: "order_id_required" }, 400);
      const patch: Record<string, unknown> = { status: "awaiting_review" };
      if (typeof body.userNote === "string") patch.user_note = body.userNote.slice(0,500);
      if (typeof body.proofUrl === "string" && /^https:\/\//i.test(body.proofUrl) && body.proofUrl.length <= 1000) patch.proof_url = body.proofUrl;
      const updated = await db.from("rf_orders").update(patch).eq("id",body.orderId).eq("profile_id",profile.id).eq("airline_code", airlineCode).eq("status","awaiting_payment")
        .select("id,order_number,status,created_at").maybeSingle();
      if (updated.error) return json({ error: "order_update_failed" }, 500);
      if (!updated.data) return json({ error: "order_not_found_or_not_payable" }, 409);
      if (botToken) {
        const [admins, fullOrder] = await Promise.all([
          db.from("rf_profiles").select("telegram_id,id").eq("role","owner"),
          db.from("rf_orders").select("order_number,amount,currency").eq("id", updated.data.id).eq("airline_code", airlineCode).single()
        ]);
        const carrierStaff = await db.from("rf_airline_staff").select("profile_id").eq("airline_code", airlineCode);
        const ownerIds = (admins.data || []).map((a) => a.id);
        const recipientProfileIds = new Set([...(carrierStaff.data || []).map((s) => s.profile_id), ...ownerIds]);
        const notifyRows = await db.from("rf_profiles").select("id,telegram_id").in("id", Array.from(recipientProfileIds));
        const orderInfo = fullOrder.data;
        if (notifyRows.data && orderInfo) {
          for (const a of notifyRows.data) {
            try { await fetch("https://api.telegram.org/bot"+botToken+"/sendMessage", {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({chat_id:a.telegram_id,text:"Новая заявка на проверку оплаты\nЗаказ: "+orderInfo.order_number+"\nСумма: "+orderInfo.amount+" "+orderInfo.currency,disable_web_page_preview:true})}); } catch {}
          }
        }
      }
      return json({ order: updated.data });
    }

    if (action.startsWith("admin_") && !admin) return json({ error: "admin_required" }, 403);

    if (action === "admin_review_order") {
      if (!validText(body.orderId,64) || typeof body.paid !== "boolean") return json({ error: "invalid_review" }, 400);
      const result = await db.rpc("rf_admin_review_order", { p_order_id: body.orderId, p_admin_telegram_id: telegram.id,
        p_paid: body.paid, p_note: typeof body.note === "string" ? body.note.slice(0,500) : null });
      if (result.error) return json({ error: "review_failed", detail: result.error.message }, 409);
      if (botToken) {
        const order = await db.from("rf_orders").select("order_number,profile_id,service_id").eq("id",body.orderId).eq("airline_code", airlineCode).single();
        if (order.data) {
          const [recipient, service, subscription] = await Promise.all([
            db.from("rf_profiles").select("telegram_id").eq("id",order.data.profile_id).single(),
            db.from("rf_services").select("name").eq("id",order.data.service_id).eq("airline_code", airlineCode).single(),
            db.from("rf_subscriptions").select("ends_at").eq("source_order_id",body.orderId).eq("airline_code", airlineCode).maybeSingle()
          ]);
          if (recipient.data) {
            const statusText = body.paid ? "Оплата подтверждена. Услуга активирована." : "Оплата не подтверждена. Заявка отклонена.";
            const expiryText = subscription.data?.ends_at ? "\nДействует до: "+new Date(subscription.data.ends_at).toLocaleString("ru-RU") : "";
            try { await fetch("https://api.telegram.org/bot"+botToken+"/sendMessage", {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({chat_id:recipient.data.telegram_id,text:statusText+"\nЗаказ: "+order.data.order_number+(service.data?.name?"\nУслуга: "+service.data.name:"")+expiryText+(typeof body.note==="string"&&body.note.trim()?"\nКомментарий: "+body.note.trim().slice(0,300):""),disable_web_page_preview:true})}); } catch {}
          }
        }
      }
      return json({ result: result.data });
    }

    if (action === "admin_manage_user") {
      const userId=validText(body.profileId,64)?body.profileId:"";
      if(!userId)return json({error:"profile_id_required"},400);
      const role=body.role;
      const hasRole=role==="member"||role==="admin";
      if(hasRole&&!isOwner)return json({error:"owner_required_to_change_roles"},403);
      if(body.milesDelta!==undefined&&!isOwner)return json({error:"alliance_owner_required_to_adjust_miles"},403);
      const target=await db.from("rf_profiles").select("id,telegram_id,role,miles,display_name,telegram_username,roblox_username").eq("id",userId).maybeSingle();
      if(!target.data)return json({error:"user_not_found"},404);
      if(hasRole){
        if(role==="admin"){
          const assignment=await db.from("rf_airline_staff").upsert({profile_id:userId,airline_code:airlineCode,role:"admin",created_by:telegram.id},{onConflict:"profile_id,airline_code"}).select().single();
          if(assignment.error)return json({error:"airline_admin_assignment_failed"},500);
        }else{
          const removed=await db.from("rf_airline_staff").delete().eq("profile_id",userId).eq("airline_code",airlineCode);
          if(removed.error)return json({error:"airline_admin_removal_failed"},500);
        }
      }
      let milesResult=null;
      if(body.milesDelta!==undefined){
        const delta=Number(body.milesDelta);
        if(!Number.isSafeInteger(delta)||delta===0||Math.abs(delta)>1000000)return json({error:"invalid_miles_adjustment"},400);
        const adjusted=await db.rpc("rf_adjust_alliance_miles",{p_profile_id:userId,p_admin_telegram_id:telegram.id,p_delta:delta});
        if(adjusted.error)return json({error:"alliance_miles_adjustment_failed",detail:adjusted.error.message},409);
        milesResult=adjusted.data;
      }
      const staffForTarget=await db.from("rf_airline_staff").select("role").eq("profile_id",userId).eq("airline_code",airlineCode).maybeSingle();
      const targetRole=target.data.role==="owner"?"owner":(staffForTarget.data?.role||"member");
      await db.from("rf_admin_audit").insert({airline_code:airlineCode,admin_telegram_id:telegram.id,action:"user_updated",entity_type:"profile",entity_id:userId,details:{role:targetRole,milesDelta:body.milesDelta===undefined?0:Number(body.milesDelta)}});
      return json({user:{...target.data,role:targetRole,miles:milesResult?.miles??target.data.miles}});
    }

    if (action === "admin_create_flight") {
      const f = body.flight || {};
      if (!validText(f.title,120) || !validText(f.origin,80) || !validText(f.destination,80) || !validText(f.departureAt,50) || Number.isNaN(Date.parse(f.departureAt))) return json({ error: "invalid_flight_fields" }, 400);
      const result = await db.from("rf_flights").insert({ airline_code: airlineCode, title:f.title.trim(), flight_number:validText(f.flightNumber,20)?f.flightNumber.trim():null,
        origin:f.origin.trim(), destination:f.destination.trim(), aircraft:validText(f.aircraft,80)?f.aircraft.trim():null,
        departure_at:new Date(f.departureAt).toISOString(), registration_deadline:validText(f.registrationDeadline,50)&&!Number.isNaN(Date.parse(f.registrationDeadline))?new Date(f.registrationDeadline).toISOString():null,
        capacity:Number.isInteger(f.capacity)&&f.capacity>0?f.capacity:null, description:typeof f.description==="string"?f.description.slice(0,1000):null,
        status:f.status==="draft"?"draft":"scheduled", created_by:telegram.id }).select().single();
      if (result.error) return json({ error:"flight_creation_failed" },500);
      await db.from("rf_admin_audit").insert({airline_code:airlineCode,admin_telegram_id:telegram.id,action:"flight_created",entity_type:"flight",entity_id:result.data.id,details:{title:result.data.title}});
      return json({ flight:result.data });
    }

    if (action === "admin_save_service") {
      const s = body.service || {};
      if (!validText(s.code,40) || !validText(s.name,100) || !Number.isFinite(Number(s.price)) || Number(s.price)<0 || !Number.isInteger(Number(s.durationDays)) || Number(s.durationDays)<1) return json({error:"invalid_service_fields"},400);
      const paymentMode = ["manual_only","roblox_only","both"].includes(s.paymentMode) ? s.paymentMode : "manual_only";
      const passId = typeof s.robloxGamepassId === "string" ? s.robloxGamepassId.trim() : "";
      const robuxRaw = s.robuxPrice === null || s.robuxPrice === undefined || String(s.robuxPrice).trim() === "" ? null : Number(s.robuxPrice);
      const robloxEnabled = paymentMode !== "manual_only";
      if (passId && !/^[1-9][0-9]{0,19}$/.test(passId)) return json({error:"invalid_roblox_gamepass_id"},400);
      if (robuxRaw !== null && (!Number.isSafeInteger(robuxRaw) || robuxRaw <= 0)) return json({error:"invalid_robux_price"},400);
      if (paymentMode !== "manual_only" && (!passId || robuxRaw === null)) return json({error:"roblox_gamepass_configuration_required",message:"Для оплаты через Robux укажите Game Pass ID и цену."},400);
      const values={airline_code:airlineCode,code:s.code.trim().toUpperCase(),name:s.name.trim(),description:typeof s.description==="string"?s.description.slice(0,1000):null,
        price:Number(s.price),currency:validText(s.currency,6)?s.currency.toUpperCase():"RUB",duration_days:Number(s.durationDays),active:s.active!==false,sort_order:Number.isInteger(s.sortOrder)?s.sortOrder:0,
        payment_mode:paymentMode,roblox_enabled:robloxEnabled,roblox_gamepass_id:passId||null,robux_price:robuxRaw,updated_at:new Date().toISOString()};
      const result=s.id?await db.from("rf_services").update(values).eq("id",s.id).eq("airline_code",airlineCode).select().single():await db.from("rf_services").insert(values).select().single();
      if (result.error) {
        console.error("service_save_failed",result.error.message);
        return json({error:"service_save_failed",message:"Проверьте поля услуги и уникальность Game Pass ID."},409);
      }
      await db.from("rf_admin_audit").insert({airline_code:airlineCode,admin_telegram_id:telegram.id,action:s.id?"service_updated":"service_created",entity_type:"service",entity_id:result.data.id,details:{code:result.data.code,paymentMode,robloxEnabled,gamepassId:passId||null}});
      return json({service:result.data});
    }

    if (action === "admin_add_payment_method") {
      const p=body.paymentMethod||{};
      if(!validText(p.label,80)||!validText(p.cardNumber,80))return json({error:"invalid_payment_method"},400);
      const result=await db.from("rf_payment_methods").insert({airline_code:airlineCode,label:p.label.trim(),card_number:p.cardNumber.trim(),recipient_name:validText(p.recipientName,120)?p.recipientName.trim():null,instructions:typeof p.instructions==="string"?p.instructions.slice(0,500):null,active:p.active!==false}).select("id,label,card_number,recipient_name,instructions,active").single();
      if(result.error)return json({error:"payment_method_save_failed"},500);
      await db.from("rf_admin_audit").insert({airline_code:airlineCode,admin_telegram_id:telegram.id,action:"payment_method_created",entity_type:"payment_method",entity_id:result.data.id,details:{label:result.data.label}});
      return json({paymentMethod:result.data});
    }

    if (action === "admin_create_notification") {
      const n=body.notification||{};
      if(!validText(n.title,120)||!validText(n.body,2000))return json({error:"invalid_notification"},400);
      const scheduledAt=validText(n.scheduledAt,50)&&!Number.isNaN(Date.parse(n.scheduledAt))?new Date(n.scheduledAt).toISOString():null;
      const audience=["all","admins","roblox_linked","active_service"].includes(n.audience)?n.audience:"all";
      if(airlineCode!=="royal"&&audience==="roblox_linked")return json({error:"feature_not_available_for_airline"},403);
      const result=await db.from("rf_notifications").insert({airline_code:airlineCode,title:n.title.trim(),body:n.body.trim(),audience,scheduled_at:scheduledAt,status:scheduledAt?"scheduled":"draft",created_by:telegram.id}).select().single();
      if(result.error)return json({error:"notification_save_failed"},500);
      let delivery={sent:0,failed:0};
      if(!scheduledAt){
        const targets=await db.from("rf_profiles").select("telegram_id,role,roblox_user_id,id");
        if(targets.error)return json({error:"notification_targets_failed"},500);
        let selected=targets.data||[];
        if(audience==="all"||audience==="roblox_linked"){
          const memberships=await db.from("rf_airline_memberships").select("profile_id").eq("airline_code",airlineCode);
          if(memberships.error)return json({error:"notification_membership_lookup_failed"},503);
          const memberIds=new Set((memberships.data||[]).map(x=>x.profile_id));
          selected=selected.filter(x=>memberIds.has(x.id));
        }
        if(audience==="admins"){
          const staff=await db.from("rf_airline_staff").select("profile_id").eq("airline_code",airlineCode);
          if(staff.error)return json({error:"notification_staff_lookup_failed"},503);
          const staffIds=new Set((staff.data||[]).map(x=>x.profile_id));
          selected=selected.filter(x=>x.role==="owner"||staffIds.has(x.id));
        }
        if(audience==="roblox_linked")selected=selected.filter(x=>x.roblox_user_id!==null);
        if(audience==="active_service"){
          const active=await db.from("rf_subscriptions").select("profile_id").eq("airline_code", airlineCode).eq("status","active").gt("ends_at",new Date().toISOString());
          if(active.error)return json({error:"notification_active_service_lookup_failed"},503);
          const ids=new Set((active.data||[]).map(x=>x.profile_id));selected=selected.filter(x=>ids.has(x.id));
        }
        if(!botToken)return json({error:"telegram_bot_not_configured",notification:result.data},503);
        for(const target of selected){
          try{
            const sent=await fetch("https://api.telegram.org/bot"+botToken+"/sendMessage",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({chat_id:target.telegram_id,text:"✈ "+n.title.trim()+"\n\n"+n.body.trim(),disable_web_page_preview:true})});
            const payload=await sent.json();if(sent.ok&&payload.ok)delivery.sent++;else delivery.failed++;
          }catch{delivery.failed++;}
        }
        await db.from("rf_notifications").update({status:delivery.failed===0?"sent":(delivery.sent>0?"sent":"failed"),sent_at:delivery.sent>0?new Date().toISOString():null}).eq("id",result.data.id).eq("airline_code",airlineCode);
      }
      await db.from("rf_admin_audit").insert({airline_code:airlineCode,admin_telegram_id:telegram.id,action:"notification_created",entity_type:"notification",entity_id:result.data.id,details:{title:result.data.title,audience,delivery}});
      return json({notification:result.data,delivery});
    }

    if (action === "admin_set_roblox_places") {
      if (airlineCode !== "royal") return json({ error: "feature_not_available_for_airline" }, 403);
      const ids = Array.isArray(body.placeIds) ? body.placeIds.map((x: unknown) => String(x).trim()).filter((x: string) => /^[0-9]{1,20}$/.test(x)).slice(0,20) : [];
      if(ids.length===0) return json({error:"at_least_one_place_id_required"},400);
      const result=await db.from("rf_settings").upsert({key:"roblox_place_ids",value:ids,updated_at:new Date().toISOString(),updated_by:telegram.id}).select().single();
      if(result.error) return json({error:"roblox_places_save_failed"},500);
      await db.from("rf_admin_audit").insert({airline_code:airlineCode,admin_telegram_id:telegram.id,action:"roblox_places_updated",entity_type:"setting",entity_id:"roblox_place_ids",details:{placeIds:ids}});
      return json({placeIds:ids});
    }

    if (action === "admin_set_miles_rate") {
      if (airlineCode !== "royal") return json({ error: "feature_not_available_for_airline" }, 403);
      const rate=Number(body.milesPerMinute);
      if(!Number.isInteger(rate)||rate<0||rate>10000)return json({error:"invalid_miles_rate"},400);
      const result=await db.from("rf_settings").upsert({key:"miles_per_minute",value:rate,updated_at:new Date().toISOString(),updated_by:telegram.id}).select().single();
      if(result.error)return json({error:"settings_update_failed"},500);
      await db.from("rf_admin_audit").insert({airline_code:airlineCode,admin_telegram_id:telegram.id,action:"miles_rate_updated",entity_type:"setting",entity_id:"miles_per_minute",details:{rate}});
      return json({setting:result.data});
    }

    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    console.error("rf-api error", error instanceof Error ? error.message : "unknown");
    return json({ error: "internal_error" }, 500);
  }
});