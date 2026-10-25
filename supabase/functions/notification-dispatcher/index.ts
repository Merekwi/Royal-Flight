import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"Content-Type":"application/json"}});

Deno.serve(async(req)=>{
  if(req.method!=="POST")return json({error:"method_not_allowed"},405);
  const secret=Deno.env.get("NOTIFICATION_CRON_SECRET");
  const botToken=Deno.env.get("TELEGRAM_BOT_TOKEN");
  const url=Deno.env.get("SUPABASE_URL");
  const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!secret||!botToken||!url||!key)return json({error:"server_not_configured"},503);
  const supplied=req.headers.get("x-cron-secret")||"";
  if(supplied.length!==secret.length)return json({error:"unauthorized"},401);
  let diff=0;for(let i=0;i<secret.length;i++)diff|=secret.charCodeAt(i)^supplied.charCodeAt(i);
  if(diff!==0)return json({error:"unauthorized"},401);
  try{
    const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
    const now=new Date().toISOString();
    const due=await db.from("rf_notifications").select("id,title,body,audience,created_by").eq("status","scheduled").lte("scheduled_at",now).order("scheduled_at").limit(20);
    if(due.error)return json({error:"scheduled_notifications_load_failed"},500);
    let sentCount=0,failedCount=0,processed=0;
    for(const notification of due.data||[]){
      const claimed=await db.from("rf_notifications").update({status:"failed"}).eq("id",notification.id).eq("status","scheduled").select("id").maybeSingle();
      if(claimed.error||!claimed.data)continue;
      const profiles=await db.from("rf_profiles").select("id,telegram_id,role,roblox_user_id");
      if(profiles.error){failedCount++;continue;}
      let recipients=profiles.data||[];
      if(notification.audience==="admins")recipients=recipients.filter(p=>p.role==="admin"||p.role==="owner");
      if(notification.audience==="roblox_linked")recipients=recipients.filter(p=>p.roblox_user_id!==null);
      if(notification.audience==="active_service"){
        const active=await db.from("rf_subscriptions").select("profile_id").eq("status","active").gt("ends_at",now);
        const activeIds=new Set((active.data||[]).map(x=>x.profile_id));
        recipients=recipients.filter(p=>activeIds.has(p.id));
      }
      let ok=0,bad=0;
      for(const recipient of recipients){
        try{
          const response=await fetch("https://api.telegram.org/bot"+botToken+"/sendMessage",{
            method:"POST",headers:{"Content-Type":"application/json"},
            body:JSON.stringify({chat_id:recipient.telegram_id,text:"✈ "+notification.title+"\n\n"+notification.body,disable_web_page_preview:true})
          });
          const result=await response.json();
          if(response.ok&&result.ok)ok++;else bad++;
        }catch{bad++;}
      }
      const finalStatus=bad===0?"sent":(ok>0?"sent":"failed");
      await db.from("rf_notifications").update({status:finalStatus,sent_at:ok>0?new Date().toISOString():null}).eq("id",notification.id);
      await db.from("rf_admin_audit").insert({admin_telegram_id:notification.created_by||0,action:"scheduled_notification_dispatched",entity_type:"notification",entity_id:notification.id,details:{sent:ok,failed:bad,audience:notification.audience}});
      sentCount+=ok;failedCount+=bad;processed++;
    }
    return json({ok:true,processed,sent:sentCount,failed:failedCount});
  }catch(error){
    console.error("notification-dispatcher error",error instanceof Error?error.message:"unknown");
    return json({error:"internal_error"},500);
  }
});
