import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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
  const checkString = Array.from(params.entries()).sort(([a], [b]) => a.localeCompare(b)).map(([k,v]) => `${k}=${v}`).join("\n");
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
    const telegram = await verifyInitData(body.initData, botToken);
    if (!telegram) return json({ error: "telegram_verification_failed" }, 401);
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

    const { data: profile, error: profileError } = await db.from("rf_profiles").upsert({
      telegram_id: telegram.id, telegram_username: telegram.username, display_name: telegram.name || null, updated_at: new Date().toISOString()
    }, { onConflict: "telegram_id" }).select("id,telegram_id,telegram_username,display_name,role,miles,roblox_username").single();
    if (profileError || !profile) return json({ error: "profile_unavailable" }, 500);

    const admin = profile.role === "admin" || profile.role === "owner";
    const action = body.action;

    if (action === "create_roblox_link") {
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
      const [flights, services, orders, subscriptions, ledger, announcements, paymentMethods] = await Promise.all([
        db.from("rf_flights").select("id,title,flight_number,origin,destination,aircraft,departure_at,registration_deadline,capacity,status,description").in("status", ["scheduled","boarding"]).gte("departure_at", now).order("departure_at").limit(20),
        db.from("rf_services").select("id,code,name,description,price,currency,duration_days").eq("active", true).order("sort_order"),
        db.from("rf_orders").select("id,order_number,service_id,payment_method_id,amount,currency,status,created_at,paid_at,admin_note").eq("profile_id", profile.id).order("created_at", { ascending: false }).limit(20),
        db.from("rf_subscriptions").select("id,service_id,starts_at,ends_at,status").eq("profile_id", profile.id).eq("status","active").gt("ends_at", now).order("ends_at"),
        db.from("rf_mile_ledger").select("id,delta,reason,created_at,metadata").eq("profile_id", profile.id).order("created_at", { ascending: false }).limit(30),
        db.from("rf_notifications").select("id,title,body,sent_at,created_at").eq("status","sent").order("sent_at", { ascending: false }).limit(10),
        db.from("rf_payment_methods").select("id,label,card_number,recipient_name,instructions").eq("active", true).order("created_at")
      ]);
      const err = [flights,services,orders,subscriptions,ledger,announcements,paymentMethods].find(x=>x.error);
      if (err) return json({ error: "dashboard_load_failed" }, 500);
      let pendingOrders: unknown[] = [];
      let adminUsers: unknown[] = [];
      if (admin) {
        const [pending, users] = await Promise.all([
          db.from("rf_orders").select("id,order_number,profile_id,service_id,amount,currency,status,proof_url,user_note,created_at").eq("status","awaiting_review").order("created_at"),
          db.from("rf_profiles").select("id,telegram_id,telegram_username,display_name,role,miles,roblox_username").order("created_at",{ascending:false}).limit(100)
        ]);
        if (!pending.error) pendingOrders = pending.data || [];
        if (!users.error) adminUsers = users.data || [];
      }
      return json({ profile, flights: flights.data || [], services: services.data || [], orders: orders.data || [],
        subscriptions: subscriptions.data || [], mileLedger: ledger.data || [], announcements: announcements.data || [], paymentMethods: paymentMethods.data || [],
        admin: admin ? { pendingOrders, users: adminUsers } : null });
    }

    if (action === "create_order") {
      if (!validText(body.serviceId, 64) || !validText(body.paymentMethodId, 64)) return json({ error: "service_and_payment_method_required" }, 400);
      const [serviceResult, methodResult] = await Promise.all([
        db.from("rf_services").select("id,price,currency,active").eq("id",body.serviceId).eq("active",true).maybeSingle(),
        db.from("rf_payment_methods").select("id,active").eq("id",body.paymentMethodId).eq("active",true).maybeSingle()
      ]);
      if (!serviceResult.data || !methodResult.data) return json({ error: "service_or_payment_method_unavailable" }, 400);
      const orderNumber = "RF-" + new Date().toISOString().slice(2,10).replaceAll("-","") + "-" + crypto.randomUUID().replaceAll("-","").slice(0,6).toUpperCase();
      const created = await db.from("rf_orders").insert({ order_number: orderNumber, profile_id: profile.id, service_id: serviceResult.data.id,
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
      const updated = await db.from("rf_orders").update(patch).eq("id",body.orderId).eq("profile_id",profile.id).eq("status","awaiting_payment")
        .select("id,order_number,status,created_at").maybeSingle();
      if (updated.error) return json({ error: "order_update_failed" }, 500);
      if (!updated.data) return json({ error: "order_not_found_or_not_payable" }, 409);
      if (botToken) {
        const [admins, fullOrder] = await Promise.all([
          db.from("rf_profiles").select("telegram_id").in("role", ["admin","owner"]),
          db.from("rf_orders").select("order_number,amount,currency").eq("id", updated.data.id).single()
        ]);
        const orderInfo = fullOrder.data;
        if (admins.data && orderInfo) {
          for (const a of admins.data) {
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
        const order = await db.from("rf_orders").select("order_number,profile_id,service_id").eq("id",body.orderId).single();
        if (order.data) {
          const [recipient, service, subscription] = await Promise.all([
            db.from("rf_profiles").select("telegram_id").eq("id",order.data.profile_id).single(),
            db.from("rf_services").select("name").eq("id",order.data.service_id).single(),
            db.from("rf_subscriptions").select("ends_at").eq("source_order_id",body.orderId).maybeSingle()
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
      if(hasRole&&profile.role!=="owner")return json({error:"owner_required_to_change_roles"},403);
      if(userId===profile.id&&role==="member"&&profile.role==="owner")return json({error:"cannot_remove_own_owner_role"},409);
      const target=await db.from("rf_profiles").select("id,telegram_id,role,miles").eq("id",userId).maybeSingle();
      if(!target.data)return json({error:"user_not_found"},404);
      const patch:Record<string,unknown>={updated_at:new Date().toISOString()};
      if(hasRole)patch.role=role;
      let delta=0;
      if(body.milesDelta!==undefined){
        delta=Number(body.milesDelta);
        if(!Number.isInteger(delta)||Math.abs(delta)>1000000||target.data.miles+delta<0)return json({error:"invalid_miles_adjustment"},400);
        if(delta!==0)patch.miles=target.data.miles+delta;
      }
      const saved=await db.from("rf_profiles").update(patch).eq("id",userId).select("id,telegram_id,role,miles,display_name,telegram_username,roblox_username").single();
      if(saved.error)return json({error:"user_update_failed"},500);
      if(delta!==0)await db.from("rf_mile_ledger").insert({profile_id:userId,delta,reason:"admin_adjustment",metadata:{admin_telegram_id:telegram.id}});
      await db.from("rf_admin_audit").insert({admin_telegram_id:telegram.id,action:"user_updated",entity_type:"profile",entity_id:userId,details:{role:hasRole?role:target.data.role,milesDelta:delta}});
      return json({user:saved.data});
    }

    if (action === "admin_create_flight") {
      const f = body.flight || {};
      if (!validText(f.title,120) || !validText(f.origin,80) || !validText(f.destination,80) || !validText(f.departureAt,50) || Number.isNaN(Date.parse(f.departureAt))) return json({ error: "invalid_flight_fields" }, 400);
      const result = await db.from("rf_flights").insert({ title:f.title.trim(), flight_number:validText(f.flightNumber,20)?f.flightNumber.trim():null,
        origin:f.origin.trim(), destination:f.destination.trim(), aircraft:validText(f.aircraft,80)?f.aircraft.trim():null,
        departure_at:new Date(f.departureAt).toISOString(), registration_deadline:validText(f.registrationDeadline,50)&&!Number.isNaN(Date.parse(f.registrationDeadline))?new Date(f.registrationDeadline).toISOString():null,
        capacity:Number.isInteger(f.capacity)&&f.capacity>0?f.capacity:null, description:typeof f.description==="string"?f.description.slice(0,1000):null,
        status:f.status==="draft"?"draft":"scheduled", created_by:telegram.id }).select().single();
      if (result.error) return json({ error:"flight_creation_failed" },500);
      await db.from("rf_admin_audit").insert({admin_telegram_id:telegram.id,action:"flight_created",entity_type:"flight",entity_id:result.data.id,details:{title:result.data.title}});
      return json({ flight:result.data });
    }

    if (action === "admin_save_service") {
      const s = body.service || {};
      if (!validText(s.code,40) || !validText(s.name,100) || !Number.isFinite(Number(s.price)) || Number(s.price)<0 || !Number.isInteger(Number(s.durationDays)) || Number(s.durationDays)<1) return json({error:"invalid_service_fields"},400);
      const values={code:s.code.trim().toUpperCase(),name:s.name.trim(),description:typeof s.description==="string"?s.description.slice(0,1000):null,
        price:Number(s.price),currency:validText(s.currency,6)?s.currency.toUpperCase():"RUB",duration_days:Number(s.durationDays),active:s.active!==false,sort_order:Number.isInteger(s.sortOrder)?s.sortOrder:0,updated_at:new Date().toISOString()};
      const result=s.id?await db.from("rf_services").update(values).eq("id",s.id).select().single():await db.from("rf_services").insert(values).select().single();
      if (result.error) return json({error:"service_save_failed"},409);
      await db.from("rf_admin_audit").insert({admin_telegram_id:telegram.id,action:s.id?"service_updated":"service_created",entity_type:"service",entity_id:result.data.id,details:{code:result.data.code}});
      return json({service:result.data});
    }

    if (action === "admin_add_payment_method") {
      const p=body.paymentMethod||{};
      if(!validText(p.label,80)||!validText(p.cardNumber,80))return json({error:"invalid_payment_method"},400);
      const result=await db.from("rf_payment_methods").insert({label:p.label.trim(),card_number:p.cardNumber.trim(),recipient_name:validText(p.recipientName,120)?p.recipientName.trim():null,instructions:typeof p.instructions==="string"?p.instructions.slice(0,500):null,active:p.active!==false}).select("id,label,card_number,recipient_name,instructions,active").single();
      if(result.error)return json({error:"payment_method_save_failed"},500);
      await db.from("rf_admin_audit").insert({admin_telegram_id:telegram.id,action:"payment_method_created",entity_type:"payment_method",entity_id:result.data.id,details:{label:result.data.label}});
      return json({paymentMethod:result.data});
    }

    if (action === "admin_create_notification") {
      const n=body.notification||{};
      if(!validText(n.title,120)||!validText(n.body,2000))return json({error:"invalid_notification"},400);
      const scheduledAt=validText(n.scheduledAt,50)&&!Number.isNaN(Date.parse(n.scheduledAt))?new Date(n.scheduledAt).toISOString():null;
      const audience=["all","admins","roblox_linked","active_service"].includes(n.audience)?n.audience:"all";
      const result=await db.from("rf_notifications").insert({title:n.title.trim(),body:n.body.trim(),audience,scheduled_at:scheduledAt,status:scheduledAt?"scheduled":"draft",created_by:telegram.id}).select().single();
      if(result.error)return json({error:"notification_save_failed"},500);
      let delivery={sent:0,failed:0};
      if(!scheduledAt){
        const targets=await db.from("rf_profiles").select("telegram_id,role,roblox_user_id,id");
        if(targets.error)return json({error:"notification_targets_failed"},500);
        let selected=targets.data||[];
        if(audience==="admins")selected=selected.filter(x=>x.role==="admin"||x.role==="owner");
        if(audience==="roblox_linked")selected=selected.filter(x=>x.roblox_user_id!==null);
        if(audience==="active_service"){
          const active=await db.from("rf_subscriptions").select("profile_id").eq("status","active").gt("ends_at",new Date().toISOString());
          const ids=new Set((active.data||[]).map(x=>x.profile_id));selected=selected.filter(x=>ids.has(x.id));
        }
        if(!botToken)return json({error:"telegram_bot_not_configured",notification:result.data},503);
        for(const target of selected){
          try{
            const sent=await fetch("https://api.telegram.org/bot"+botToken+"/sendMessage",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({chat_id:target.telegram_id,text:"✈ "+n.title.trim()+"\n\n"+n.body.trim(),disable_web_page_preview:true})});
            const payload=await sent.json();if(sent.ok&&payload.ok)delivery.sent++;else delivery.failed++;
          }catch{delivery.failed++;}
        }
        await db.from("rf_notifications").update({status:delivery.failed===0?"sent":(delivery.sent>0?"sent":"failed"),sent_at:delivery.sent>0?new Date().toISOString():null}).eq("id",result.data.id);
      }
      await db.from("rf_admin_audit").insert({admin_telegram_id:telegram.id,action:"notification_created",entity_type:"notification",entity_id:result.data.id,details:{title:result.data.title,audience,delivery}});
      return json({notification:result.data,delivery});
    }

    if (action === "admin_set_roblox_places") {
      const ids = Array.isArray(body.placeIds) ? body.placeIds.map((x: unknown) => String(x).trim()).filter((x: string) => /^[0-9]{1,20}$/.test(x)).slice(0,20) : [];
      if(ids.length===0) return json({error:"at_least_one_place_id_required"},400);
      const result=await db.from("rf_settings").upsert({key:"roblox_place_ids",value:ids,updated_at:new Date().toISOString(),updated_by:telegram.id}).select().single();
      if(result.error) return json({error:"roblox_places_save_failed"},500);
      await db.from("rf_admin_audit").insert({admin_telegram_id:telegram.id,action:"roblox_places_updated",entity_type:"setting",entity_id:"roblox_place_ids",details:{placeIds:ids}});
      return json({placeIds:ids});
    }

    if (action === "admin_set_miles_rate") {
      const rate=Number(body.milesPerMinute);
      if(!Number.isInteger(rate)||rate<0||rate>10000)return json({error:"invalid_miles_rate"},400);
      const result=await db.from("rf_settings").upsert({key:"miles_per_minute",value:rate,updated_at:new Date().toISOString(),updated_by:telegram.id}).select().single();
      if(result.error)return json({error:"settings_update_failed"},500);
      await db.from("rf_admin_audit").insert({admin_telegram_id:telegram.id,action:"miles_rate_updated",entity_type:"setting",entity_id:"miles_per_minute",details:{rate}});
      return json({setting:result.data});
    }

    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    console.error("rf-api error", error instanceof Error ? error.message : "unknown");
    return json({ error: "internal_error" }, 500);
  }
});