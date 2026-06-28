#!/usr/bin/env node
"use strict";
const http=require("http"),path=require("path"),fs=require("fs"),crypto=require("crypto"),{execFileSync}=require("child_process");
const ROOT=process.env.KNVOX_ROOT||path.resolve(__dirname,"../.."),HOST=process.env.ADMIN_CONSOLE_HOST||"127.0.0.1",PORT=Number(process.env.ADMIN_CONSOLE_PORT||8090),U=process.env.ADMIN_USERNAME||"admin",P=process.env.ADMIN_PASSWORD||"",PH=process.env.ADMIN_PASSWORD_SHA256||"",SEC=process.env.ADMIN_SESSION_SECRET||crypto.createHash("sha256").update(String(P||PH||"local")).digest("hex"),CK="knvox_admin_session",PGU=process.env.POSTGRES_USER||"knvox",PGD=process.env.POSTGRES_DB||"knvox";
const esc=x=>String(x??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]));
const sha=x=>crypto.createHash("sha256").update(String(x||"")).digest("hex");
const eq=(a,b)=>{a=Buffer.from(String(a||""));b=Buffer.from(String(b||""));return a.length===b.length&&crypto.timingSafeEqual(a,b)};
const lit=x=>"$$"+String(x).replace(/\$\$/g,"")+"$$";
function psql(sql){return execFileSync(path.join(ROOT,"scripts","compose.sh"),["exec","-T","postgres","psql","-U",PGU,"-d",PGD,"-At","-F","\t","-c",sql],{cwd:ROOT,encoding:"utf8",timeout:20000}).trim()}
function scalar(sql,d=""){try{return (psql(sql).split("\n")[0]||d).trim()}catch(e){return d}}
function rows(sql){try{let o=psql(sql);return o?o.split("\n").filter(Boolean).map(l=>l.split("\t")):[]}catch(e){return[]}}
function has(table,col){return ["t","true","1"].includes(scalar(`SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema=$$billing$$ AND table_name=${lit(table)} AND column_name=${lit(col)});`,"f").toLowerCase())}
function sign(p){return crypto.createHmac("sha256",SEC).update(p).digest("base64url")}
function session(u){let p=Buffer.from(JSON.stringify({u,role:"superadmin",exp:Date.now()+28800000})).toString("base64url");return p+"."+sign(p)}
function readSession(req){let raw=String(req.headers.cookie||"").split(";").map(x=>x.trim()).find(x=>x.startsWith(CK+"="));if(!raw)return null;let [p,s]=decodeURIComponent(raw.slice(CK.length+1)).split(".");if(!p||!eq(s,sign(p)))return null;try{let j=JSON.parse(Buffer.from(p,"base64url").toString());return j.exp>Date.now()?j:null}catch(e){return null}}
function send(res,code,body,type="text/html; charset=utf-8",headers={}){res.writeHead(code,Object.assign({"Content-Type":type,"Cache-Control":"no-store"},headers));res.end(body)}
function redirect(res,to){send(res,302,"","text/plain",{"Location":to})}
function status(){return{pstn_enabled:scalar("SELECT value FROM billing.system_settings WHERE key=$$pstn_enabled$$;","unknown"),active_calls:Number(scalar("SELECT count(*) FROM billing.active_calls;","0")),unsafe_provider_trunks:Number(scalar("SELECT count(*) FROM billing.provider_trunks WHERE enabled=true OR sandbox_only=false;","0")),dry_run_events:Number(scalar("SELECT count(*) FROM billing.external_call_dry_run_events;","0")),execution_mode:"NO_DIAL_NO_PSTN",admin_mode:"READ_ONLY"}}
function clients(q=""){let m={};function add(code,patch){code=String(code||"").trim();if(!code)return;m[code]=Object.assign({customer_code:code,name:code,status:"observed",sip_accounts:0,dry_run_events:0},m[code]||{},patch)}
if(has("sip_accounts","customer_code"))rows("SELECT customer_code,count(*) FROM billing.sip_accounts WHERE customer_code IS NOT NULL GROUP BY customer_code LIMIT 1000;").forEach(r=>add(r[0],{sip_accounts:Number(r[1]||0)}));
if(has("external_call_dry_run_events","customer_code"))rows("SELECT customer_code,count(*) FROM billing.external_call_dry_run_events WHERE customer_code IS NOT NULL GROUP BY customer_code LIMIT 1000;").forEach(r=>add(r[0],{dry_run_events:Number(r[1]||0)}));
q=String(q||"").toLowerCase();return Object.values(m).filter(c=>!q||c.customer_code.toLowerCase().includes(q)||c.name.toLowerCase().includes(q)).sort((a,b)=>a.customer_code.localeCompare(b.customer_code))}
function layout(t,b,s){return`<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(t)} · KNVOX</title><link rel="stylesheet" href="/admin.css"></head><body><header><b>KNVOX Admin</b><nav><a href="/admin">Dashboard</a><a href="/admin/clients">Clients</a><a href="/admin/logout">Déconnexion</a>${s?`<span>${esc(s.u)}</span>`:""}</nav></header><main>${b}</main></body></html>`}
function login(err=""){return layout("Login",`<section class="box login"><h1>Connexion admin</h1>${err?`<p class="err">${esc(err)}</p>`:""}<form method="post"><input name="username" placeholder="Utilisateur" required><input name="password" type="password" placeholder="Mot de passe" required><button>Connexion</button></form><p class="muted">PSTN OFF · API DRY-RUN ONLY</p></section>`,null)}
function dashboard(s){let x=status();return layout("Dashboard",`<section class="hero"><h1>Dashboard sécurisé</h1><p>Lecture seule. Aucun appel réel, aucune activation PSTN, aucun provider activable.</p></section><section class="grid"><div class="card"><span>PSTN</span><b>${esc(x.pstn_enabled)}</b></div><div class="card"><span>Active calls</span><b>${x.active_calls}</b></div><div class="card"><span>Unsafe trunks</span><b>${x.unsafe_provider_trunks}</b></div><div class="card"><span>Dry-run events</span><b>${x.dry_run_events}</b></div></section><p><a class="btn" href="/admin/clients">Gestion clients</a></p>`,s)}

function sipAccounts(q=""){
  let cols=["id","customer_code","username","extension","enabled","created_at","updated_at"].filter(c=>has("sip_accounts",c));
  if(!cols.length)return[];
  let sql="SELECT "+cols.map(c=>String.fromCharCode(34)+c+String.fromCharCode(34)).join(",")+" FROM billing.sip_accounts ORDER BY 1 LIMIT 1000;";
  let data=rows(sql);
  q=String(q||"").toLowerCase();
  return data.map(r=>{
    let o={};
    cols.forEach((c,i)=>o[c]=r[i]??"");
    return {
      id:o.id||"",
      customer_code:o.customer_code||"",
      username:o.username||"",
      extension:o.extension||"",
      enabled:o.enabled||"",
      created_at:o.created_at||"",
      updated_at:o.updated_at||"",
      raw:o
    };
  }).filter(a=>!q||JSON.stringify(a).toLowerCase().includes(q));
}
function sipAccountsPage(s,u){
  let q=u.searchParams.get("q")||"";
  let list=sipAccounts(q);
  let trs=list.map(a=>`<tr><td>${esc(a.id)}</td><td>${esc(a.customer_code)}</td><td>${esc(a.username)}</td><td>${esc(a.extension)}</td><td><span class="pill">${esc(a.enabled)}</span></td><td>${esc(a.created_at)}</td><td>${esc(a.updated_at)}</td></tr>`).join("");
  return layout("SIP Accounts",`<section class="hero"><h1>SIP Accounts</h1><p>Comptes SIP en lecture seule. Aucune création, modification, suppression ou activation PSTN.</p></section><form class="search"><input name="q" value="${esc(q)}" placeholder="Recherche SIP, client, extension"><button>Rechercher</button><a class="btn secondary" href="/admin/sip-accounts">Reset</a></form><section class="box"><h2>Comptes SIP détectés (${list.length})</h2><table><thead><tr><th>ID</th><th>Client</th><th>Username</th><th>Extension</th><th>Enabled</th><th>Créé</th><th>MAJ</th></tr></thead><tbody>${trs||`<tr><td colspan="7">Aucun compte SIP détecté</td></tr>`}</tbody></table></section>`,s);
}


function tableColumns(table){
  return rows("SELECT column_name FROM information_schema.columns WHERE table_schema=$$billing$$ AND table_name="+lit(table)+" ORDER BY ordinal_position;").map(r=>r[0]);
}
function providerTrunks(q=""){
  let deny=/(password|secret|token|private|auth_key|api_key)/i;
  let preferred=["id","provider_code","code","name","enabled","sandbox_only","credential_ref","host","proxy","prefix","rate_per_minute","cost_per_minute","margin_per_minute","created_at","updated_at"];
  let all=tableColumns("provider_trunks").filter(c=>!deny.test(c));
  let cols=preferred.filter(c=>all.includes(c));
  all.forEach(c=>{if(!cols.includes(c))cols.push(c)});
  if(!cols.length)return[];
  let sql="SELECT "+cols.map(c=>String.fromCharCode(34)+c+String.fromCharCode(34)).join(",")+" FROM billing.provider_trunks ORDER BY 1 LIMIT 1000;";
  let data=rows(sql);
  q=String(q||"").toLowerCase();
  return data.map(r=>{
    let o={};
    cols.forEach((c,i)=>o[c]=r[i]??"");
    return {
      id:o.id||"",
      provider_code:o.provider_code||o.code||o.name||o.id||"",
      enabled:o.enabled||"",
      sandbox_only:o.sandbox_only||"",
      credential_ref:o.credential_ref||"",
      host:o.host||o.proxy||"",
      margin_per_minute:o.margin_per_minute||"",
      created_at:o.created_at||"",
      updated_at:o.updated_at||"",
      raw:o
    };
  }).filter(a=>!q||JSON.stringify(a).toLowerCase().includes(q));
}
function providersPage(s,u){
  let q=u.searchParams.get("q")||"";
  let list=providerTrunks(q);
  let trs=list.map(a=>`<tr><td>${esc(a.id)}</td><td>${esc(a.provider_code)}</td><td><span class="pill">${esc(a.enabled)}</span></td><td><span class="pill">${esc(a.sandbox_only)}</span></td><td>${esc(a.credential_ref)}</td><td>${esc(a.host)}</td><td>${esc(a.margin_per_minute)}</td><td>${esc(a.updated_at)}</td></tr>`).join("");
  return layout("Providers",`<section class="hero"><h1>Providers / Trunks</h1><p>Lecture seule. Aucun trunk activable, aucune gateway XML générée, PSTN OFF.</p></section><form class="search"><input name="q" value="${esc(q)}" placeholder="Recherche provider, trunk, credential_ref"><button>Rechercher</button><a class="btn secondary" href="/admin/providers">Reset</a></form><section class="box"><h2>Providers détectés (${list.length})</h2><table><thead><tr><th>ID</th><th>Provider</th><th>Enabled</th><th>Sandbox</th><th>Credential ref</th><th>Host</th><th>Marge/min</th><th>MAJ</th></tr></thead><tbody>${trs||`<tr><td colspan="8">Aucun provider détecté</td></tr>`}</tbody></table></section>`,s);
}


function billingTableExists(table){
  return ["t","true","1"].includes(scalar("SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema=$$billing$$ AND table_name="+lit(table)+");","f").toLowerCase());
}
function safeBillingColumns(table){
  let deny=/(password|secret|token|private|auth_key|api_key|authorization|credential|encrypted)/i;
  return rows("SELECT column_name FROM information_schema.columns WHERE table_schema=$$billing$$ AND table_name="+lit(table)+" ORDER BY ordinal_position;").map(r=>r[0]).filter(c=>!deny.test(c));
}
function maskBillingValue(k,v){
  let x=String(v??"");
  if(/(dst|destination|phone|number|ani|dnis|caller|callee)/i.test(String(k||"")) && x.length>6)return x.slice(0,3)+"****"+x.slice(-2);
  return x;
}
function billingSummary(){
  return {
    pstn_enabled: scalar("SELECT value FROM billing.system_settings WHERE key=$$pstn_enabled$$;","unknown"),
    active_calls: Number(scalar("SELECT count(*) FROM billing.active_calls;","0")),
    provider_trunks: Number(scalar("SELECT count(*) FROM billing.provider_trunks;","0")),
    unsafe_provider_trunks: Number(scalar("SELECT count(*) FROM billing.provider_trunks WHERE enabled=true OR sandbox_only=false;","0")),
    sip_accounts: Number(scalar("SELECT count(*) FROM billing.sip_accounts;","0")),
    dry_run_events: Number(scalar("SELECT count(*) FROM billing.external_call_dry_run_events;","0")),
    cdr_tables_detected: ["cdr","cdrs","call_detail_records","call_records"].filter(t=>billingTableExists(t)),
    execution_mode: "NO_DIAL_NO_PSTN",
    admin_mode: "READ_ONLY"
  };
}
function dryRunBillingEvents(q=""){
  if(!billingTableExists("external_call_dry_run_events"))return[];
  let preferred=["id","customer_code","src","dst","destination","provider_code","execution_mode","dry_run","call_was_placed","route_status","margin_per_minute","created_at","updated_at"];
  let all=safeBillingColumns("external_call_dry_run_events");
  let cols=preferred.filter(c=>all.includes(c));
  all.forEach(c=>{if(!cols.includes(c))cols.push(c)});
  if(!cols.length)return[];
  let order=cols.includes("created_at")?String.fromCharCode(34)+"created_at"+String.fromCharCode(34)+" DESC":(cols.includes("id")?String.fromCharCode(34)+"id"+String.fromCharCode(34)+" DESC":"1 DESC");
  let sql="SELECT "+cols.map(c=>String.fromCharCode(34)+c+String.fromCharCode(34)).join(",")+" FROM billing.external_call_dry_run_events ORDER BY "+order+" LIMIT 500;";
  let data=rows(sql);
  q=String(q||"").toLowerCase();
  return data.map(r=>{
    let o={};
    cols.forEach((c,i)=>o[c]=maskBillingValue(c,r[i]??""));
    return {
      id:o.id||"",
      customer_code:o.customer_code||"",
      src:o.src||"",
      dst:o.dst||o.destination||"",
      provider_code:o.provider_code||"",
      execution_mode:o.execution_mode||"NO_DIAL_NO_PSTN",
      dry_run:o.dry_run||"",
      call_was_placed:o.call_was_placed||"",
      route_status:o.route_status||"",
      margin_per_minute:o.margin_per_minute||"",
      created_at:o.created_at||"",
      raw:o
    };
  }).filter(a=>!q||JSON.stringify(a).toLowerCase().includes(q));
}
function billingPage(s,u){
  let q=u.searchParams.get("q")||"";
  let summary=billingSummary();
  let list=dryRunBillingEvents(q);
  let trs=list.map(a=>`<tr><td>${esc(a.id)}</td><td>${esc(a.customer_code)}</td><td>${esc(a.src)}</td><td>${esc(a.dst)}</td><td>${esc(a.provider_code)}</td><td>${esc(a.execution_mode)}</td><td><span class="pill">${esc(a.dry_run)}</span></td><td><span class="pill">${esc(a.call_was_placed)}</span></td><td>${esc(a.route_status)}</td><td>${esc(a.created_at)}</td></tr>`).join("");
  return layout("Billing / CDR",`<section class="hero"><h1>Billing / CDR / Dry-run Events</h1><p>Lecture seule. Aucune facturation réelle, aucun appel réel, PSTN OFF.</p></section><section class="grid"><div class="card"><span>PSTN</span><b>${esc(summary.pstn_enabled)}</b></div><div class="card"><span>Active calls</span><b>${summary.active_calls}</b></div><div class="card"><span>Dry-run events</span><b>${summary.dry_run_events}</b></div><div class="card"><span>Unsafe trunks</span><b>${summary.unsafe_provider_trunks}</b></div></section><form class="search"><input name="q" value="${esc(q)}" placeholder="Recherche client, src, dst, provider"><button>Rechercher</button><a class="btn secondary" href="/admin/billing">Reset</a></form><section class="box"><h2>Événements dry-run (${list.length})</h2><table><thead><tr><th>ID</th><th>Client</th><th>SRC</th><th>DST masqué</th><th>Provider</th><th>Mode</th><th>Dry-run</th><th>Call placed</th><th>Route</th><th>Date</th></tr></thead><tbody>${trs||`<tr><td colspan="10">Aucun événement dry-run détecté</td></tr>`}</tbody></table></section>`,s);
}

function clientsPage(s,u){let q=u.searchParams.get("q")||"",list=clients(q),trs=list.map(c=>`<tr><td>${esc(c.customer_code)}</td><td>${esc(c.name)}</td><td><span class="pill">${esc(c.status)}</span></td><td>${c.sip_accounts}</td><td>${c.dry_run_events}</td><td><a href="/admin/clients/${encodeURIComponent(c.customer_code)}">Ouvrir</a></td></tr>`).join("");return layout("Clients",`<section class="hero"><h1>Gestion clients</h1><p>Liste, recherche et fiche client en lecture seule.</p></section><form class="search"><input name="q" value="${esc(q)}" placeholder="Recherche client"><button>Rechercher</button><a class="btn secondary" href="/admin/clients">Reset</a></form><section class="box"><h2>Clients détectés (${list.length})</h2><table><thead><tr><th>Code client</th><th>Nom</th><th>Statut</th><th>SIP</th><th>Dry-run</th><th>Action</th></tr></thead><tbody>${trs||`<tr><td colspan="6">Aucun client détecté</td></tr>`}</tbody></table></section>`,s)}
function clientPage(s,code){let c=clients("").find(x=>x.customer_code===code)||{customer_code:code,name:code,status:"unknown",sip_accounts:0,dry_run_events:0};return layout("Fiche client",`<section class="hero"><h1>Fiche client ${esc(code)}</h1><p>Lecture seule. Aucune modification client, SIP, provider ou PSTN.</p><a class="btn secondary" href="/admin/clients">Retour</a></section><section class="box"><div class="kv"><span>Code</span><b>${esc(c.customer_code)}</b></div><div class="kv"><span>Nom</span><b>${esc(c.name)}</b></div><div class="kv"><span>Statut</span><b>${esc(c.status)}</b></div><div class="kv"><span>Comptes SIP</span><b>${c.sip_accounts}</b></div><div class="kv"><span>Événements dry-run</span><b>${c.dry_run_events}</b></div><p><span class="safe">PSTN OFF</span> <span class="safe">NO_DIAL_NO_PSTN</span> <span class="safe">READ_ONLY</span></p></section>`,s)}
function body(req){return new Promise(r=>{let d="";req.on("data",c=>d+=c);req.on("end",()=>r(d))})}
http.createServer(async(req,res)=>{let u=new URL(req.url,"http://x");try{if(u.pathname==="/admin.css")return send(res,200,fs.readFileSync(path.join(__dirname,"public/admin.css")),"text/css");if(u.pathname==="/")return redirect(res,"/admin");if(u.pathname==="/admin/login"){if(req.method==="POST"){let f=new URLSearchParams(await body(req)),ok=eq(f.get("username"),U)&&(P?eq(f.get("password"),P):eq(sha(f.get("password")),PH));if(!ok)return send(res,401,login("Identifiants invalides"));return send(res,302,"","text/plain",{"Set-Cookie":`${CK}=${encodeURIComponent(session(U))}; HttpOnly; SameSite=Lax; Path=/; Max-Age=28800`,"Location":"/admin"})}return send(res,200,login())}if(u.pathname==="/admin/logout")return send(res,302,"","text/plain",{"Set-Cookie":`${CK}=; Path=/; Max-Age=0`,"Location":"/admin/login"});let s=readSession(req);if(!s)return redirect(res,"/admin/login");if(u.pathname==="/admin")return send(res,200,dashboard(s));if(u.pathname==="/admin/clients")return send(res,200,clientsPage(s,u));if(u.pathname==="/admin/sip-accounts")return send(res,200,sipAccountsPage(s,u));if(u.pathname==="/admin/providers")return send(res,200,providersPage(s,u));if(u.pathname==="/admin/billing")return send(res,200,billingPage(s,u));if(u.pathname.startsWith("/admin/clients/"))return send(res,200,clientPage(s,decodeURIComponent(u.pathname.replace("/admin/clients/",""))));if(u.pathname==="/api/admin/status")return send(res,200,JSON.stringify(status(),null,2),"application/json");if(u.pathname==="/api/admin/clients")return send(res,200,JSON.stringify({clients:clients(u.searchParams.get("q")||"")},null,2),"application/json");if(u.pathname==="/api/admin/sip-accounts")return send(res,200,JSON.stringify({sip_accounts:sipAccounts(u.searchParams.get("q")||"")},null,2),"application/json");if(u.pathname==="/api/admin/providers")return send(res,200,JSON.stringify({providers:providerTrunks(u.searchParams.get("q")||"")},null,2),"application/json");if(u.pathname==="/api/admin/billing")return send(res,200,JSON.stringify({summary:billingSummary(),dry_run_events:dryRunBillingEvents(u.searchParams.get("q")||"")},null,2),"application/json");if(u.pathname==="/api/admin/billing/summary")return send(res,200,JSON.stringify(billingSummary(),null,2),"application/json");if(u.pathname==="/api/admin/billing/dry-run-events")return send(res,200,JSON.stringify({dry_run_events:dryRunBillingEvents(u.searchParams.get("q")||"")},null,2),"application/json");return send(res,404,"404")}catch(e){send(res,500,JSON.stringify({error:"admin_console_error",message:String(e.message||e)}),"application/json")}}).listen(PORT,HOST,()=>console.log(`KNVOX admin listening http://${HOST}:${PORT} READ_ONLY PSTN_OFF`));
