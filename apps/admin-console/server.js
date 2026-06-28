#!/usr/bin/env node
"use strict";

const http = require("http");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { URL } = require("url");

const PORT = Number.parseInt(process.env.ADMIN_CONSOLE_PORT || "8090", 10);
const HOST = process.env.ADMIN_CONSOLE_HOST || "127.0.0.1";
const SESSION_COOKIE = "knvox_admin_session";
const SESSION_TTL_SECONDS = Number.parseInt(process.env.ADMIN_CONSOLE_SESSION_TTL_SECONDS || "3600", 10);

const state = {
  failedLogins: new Map()
};

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function getConfig() {
  const passwordMode = process.env.ADMIN_CONSOLE_PASSWORD_SHA256 ? "sha256" : "plain-env";
  return {
    user: requiredEnv("ADMIN_CONSOLE_USER"),
    password: process.env.ADMIN_CONSOLE_PASSWORD || "",
    passwordSha256: process.env.ADMIN_CONSOLE_PASSWORD_SHA256 || "",
    passwordMode,
    secret: requiredEnv("ADMIN_CONSOLE_SESSION_SECRET"),
    billingApiUrl: process.env.BILLING_API_URL || `http://127.0.0.1:${process.env.BILLING_API_PORT || "8088"}`,
    billingApiToken: process.env.BILLING_API_TOKEN || ""
  };
}

function timingSafeEqualString(a, b) {
  const left = Buffer.from(String(a), "utf8");
  const right = Buffer.from(String(b), "utf8");
  if (left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

function hashSha256(value) {
  return crypto.createHash("sha256").update(String(value), "utf8").digest("hex");
}

function verifyPassword(input, cfg) {
  if (cfg.passwordSha256) {
    return timingSafeEqualString(hashSha256(input), cfg.passwordSha256);
  }
  if (!cfg.password) return false;
  return timingSafeEqualString(input, cfg.password);
}

function base64url(input) {
  return Buffer.from(input).toString("base64url");
}

function unbase64url(input) {
  return Buffer.from(input, "base64url").toString("utf8");
}

function sign(payload, secret) {
  return crypto.createHmac("sha256", secret).update(payload).digest("base64url");
}

function createSession(username, secret) {
  const payload = base64url(JSON.stringify({
    sub: username,
    role: "superadmin",
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS
  }));
  return `${payload}.${sign(payload, secret)}`;
}

function verifySession(token, secret) {
  if (!token || !token.includes(".")) return null;
  const [payload, signature] = token.split(".");
  const expected = sign(payload, secret);
  if (!timingSafeEqualString(signature, expected)) return null;
  let data;
  try {
    data = JSON.parse(unbase64url(payload));
  } catch {
    return null;
  }
  if (!data.exp || data.exp < Math.floor(Date.now() / 1000)) return null;
  return data;
}

function parseCookies(req) {
  const header = req.headers.cookie || "";
  return Object.fromEntries(header.split(";").map(part => {
    const idx = part.indexOf("=");
    if (idx < 0) return ["", ""];
    return [decodeURIComponent(part.slice(0, idx).trim()), decodeURIComponent(part.slice(idx + 1).trim())];
  }).filter(([k]) => k));
}

function readBody(req, maxBytes = 10000) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", chunk => {
      data += chunk;
      if (Buffer.byteLength(data) > maxBytes) {
        reject(new Error("Request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, ch => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  }[ch]));
}

function redirect(res, location) {
  res.writeHead(302, { Location: location });
  res.end();
}

function sendHtml(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "text/html; charset=utf-8",
    "X-Frame-Options": "DENY",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store"
  });
  res.end(body);
}

function sendJson(res, status, payload) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "X-Frame-Options": "DENY",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store"
  });
  res.end(JSON.stringify(payload, null, 2));
}

function page(title, content, session) {
  const userBlock = session ? `<div class="user">Connecté : ${escapeHtml(session.sub)} · <a href="/logout">Déconnexion</a></div>` : "";
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} · KNVOX Admin</title>
<link rel="stylesheet" href="/static/admin.css">
</head>
<body>
<header>
  <div>
    <strong>KNVOX Admin</strong>
    <span class="badge">SAFE MODE</span>
  </div>
  ${userBlock}
</header>
<main>${content}</main>
<footer>PSTN OFF · API dry-run only · aucune activation opérateur depuis cette console</footer>
</body>
</html>`;
}

function loginPage(message = "") {
  return page("Connexion", `
<section class="card login">
  <h1>Connexion administrateur</h1>
  <p class="muted">Console sécurisée en lecture seule. Aucune action PSTN réelle n’est disponible.</p>
  ${message ? `<p class="alert">${escapeHtml(message)}</p>` : ""}
  <form method="post" action="/login">
    <label>Utilisateur<input name="username" autocomplete="username" required></label>
    <label>Mot de passe<input name="password" type="password" autocomplete="current-password" required></label>
    <button type="submit">Se connecter</button>
  </form>
</section>`, null);
}

function dashboardPage(session) {
  return page("Dashboard", `
<section class="grid">
  <div class="card">
    <h1>Dashboard sécurisé</h1>
    <p class="muted">Cette première console admin est volontairement limitée : lecture seule, contrôle sécurité, dry-run uniquement.</p>
    <div class="status safe">PSTN verrouillée OFF</div>
    <div class="status safe">Activation trunks interdite</div>
    <div class="status safe">Gateway provider active interdite</div>
  </div>
  <div class="card">
    <h2>Contrôles live</h2>
    <pre id="summary">Chargement...</pre>
    <button type="button" onclick="loadSummary()">Rafraîchir</button>
  </div>
</section>
<section class="card">
  <h2>Modules V2.3 prévus</h2>
  <div class="modules">
    <div>Clients</div>
    <div>SIP accounts</div>
    <div>Providers sandbox</div>
    <div>Billing dry-run</div>
    <div>Monitoring</div>
    <div>Audit logs</div>
  </div>
</section>
<script>
async function loadSummary() {
  const out = document.getElementById("summary");
  out.textContent = "Chargement...";
  try {
    const res = await fetch("/api/summary", { cache: "no-store" });
    const data = await res.json();
    out.textContent = JSON.stringify(data, null, 2);
  } catch (err) {
    out.textContent = "Erreur: " + err.message;
  }
}
loadSummary();
setInterval(loadSummary, 30000);
</script>`, session);
}

function getClientIp(req) {
  return String(req.headers["x-forwarded-for"] || req.socket.remoteAddress || "unknown").split(",")[0].trim();
}

function loginAllowed(ip) {
  const now = Date.now();
  const item = state.failedLogins.get(ip) || { count: 0, first: now };
  if (now - item.first > 15 * 60 * 1000) {
    state.failedLogins.set(ip, { count: 0, first: now });
    return true;
  }
  return item.count < 10;
}

function recordLoginFailure(ip) {
  const now = Date.now();
  const item = state.failedLogins.get(ip) || { count: 0, first: now };
  if (now - item.first > 15 * 60 * 1000) {
    state.failedLogins.set(ip, { count: 1, first: now });
  } else {
    item.count += 1;
    state.failedLogins.set(ip, item);
  }
}

function clearLoginFailures(ip) {
  state.failedLogins.delete(ip);
}

async function dryRunProbe(cfg) {
  if (!cfg.billingApiToken) {
    return { ok: false, reason: "BILLING_API_TOKEN not configured for admin console runtime" };
  }
  if (typeof fetch !== "function") {
    return { ok: false, reason: "Node fetch API unavailable; use Node 18+" };
  }
  try {
    const endpoint = new URL("/api/v1/external-call/dry-run", cfg.billingApiUrl).toString();
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-KNVOX-API-Key": cfg.billingApiToken
      },
      body: JSON.stringify({ customer_code: "TEST1000", src: "1000", dst: "33612345678" })
    });
    const body = await response.json().catch(() => ({}));
    const safe = response.ok &&
      body.dry_run === true &&
      body.call_was_placed === false &&
      body.execution_mode === "NO_DIAL_NO_PSTN";
    return {
      ok: safe,
      http_status: response.status,
      dry_run: body.dry_run === true,
      call_was_placed: body.call_was_placed === true,
      execution_mode: body.execution_mode || null
    };
  } catch (err) {
    return { ok: false, reason: err.message };
  }
}

function getSession(req, cfg) {
  const cookies = parseCookies(req);
  return verifySession(cookies[SESSION_COOKIE], cfg.secret);
}

async function handle(req, res, cfg) {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const session = getSession(req, cfg);

  if (url.pathname === "/static/admin.css") {
    const cssPath = path.join(__dirname, "public", "admin.css");
    res.writeHead(200, { "Content-Type": "text/css; charset=utf-8", "Cache-Control": "no-store" });
    res.end(fs.readFileSync(cssPath, "utf8"));
    return;
  }

  if (url.pathname === "/login" && req.method === "GET") {
    sendHtml(res, 200, loginPage());
    return;
  }

  if (url.pathname === "/login" && req.method === "POST") {
    const ip = getClientIp(req);
    if (!loginAllowed(ip)) {
      sendHtml(res, 429, loginPage("Trop de tentatives. Réessayez plus tard."));
      return;
    }
    const body = await readBody(req);
    const params = new URLSearchParams(body);
    const username = params.get("username") || "";
    const password = params.get("password") || "";
    if (timingSafeEqualString(username, cfg.user) && verifyPassword(password, cfg)) {
      clearLoginFailures(ip);
      const token = createSession(username, cfg.secret);
      res.writeHead(302, {
        Location: "/dashboard",
        "Set-Cookie": `${SESSION_COOKIE}=${encodeURIComponent(token)}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_TTL_SECONDS}`
      });
      res.end();
      return;
    }
    recordLoginFailure(ip);
    sendHtml(res, 401, loginPage("Identifiants invalides."));
    return;
  }

  if (url.pathname === "/logout") {
    res.writeHead(302, {
      Location: "/login",
      "Set-Cookie": `${SESSION_COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`
    });
    res.end();
    return;
  }

  if (!session) {
    redirect(res, "/login");
    return;
  }

  if (url.pathname === "/" || url.pathname === "/dashboard") {
    sendHtml(res, 200, dashboardPage(session));
    return;
  }

  if (url.pathname === "/api/summary") {
    const probe = await dryRunProbe(cfg);
    sendJson(res, 200, {
      mode: "SAFE_ADMIN_READ_ONLY",
      generated_at: new Date().toISOString(),
      user: session.sub,
      billing_api_url_configured: Boolean(cfg.billingApiUrl),
      billing_api_token_configured: Boolean(cfg.billingApiToken),
      pstn_activation_available: false,
      provider_activation_available: false,
      gateway_generation_available: false,
      required_execution_mode: "NO_DIAL_NO_PSTN",
      dry_run_probe: probe,
      safety: {
        pstn_must_remain_off: true,
        active_calls_must_remain_zero: true,
        providers_must_remain_sandbox_off: true,
        no_active_provider_gateway_xml: true
      }
    });
    return;
  }

  sendJson(res, 404, { error: "not_found" });
}

function main() {
  const cfg = getConfig();
  if (cfg.secret.length < 32) {
    throw new Error("ADMIN_CONSOLE_SESSION_SECRET must be at least 32 characters");
  }
  const server = http.createServer((req, res) => {
    handle(req, res, cfg).catch(err => {
      sendJson(res, 500, { error: "internal_error", message: err.message });
    });
  });
  server.listen(PORT, HOST, () => {
    console.log(`KNVOX Admin Console listening on http://${HOST}:${PORT}`);
    console.log("SAFE MODE: read-only, PSTN activation disabled, provider activation disabled");
  });
}

if (require.main === module) {
  main();
}
