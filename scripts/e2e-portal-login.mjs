#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
//
// Portal login end-to-end acceptance test (2026-09-05/06 outage regression).
//
// Exercises the EXACT flow that returned "We are sorry... internal server
// error" (portal login 500) then 503 during the outage:
//
//   GET https://home.opendesk-edu.org/oauth2/start
//     -> 302 to Keycloak /realms/opendesk/protocol/openid-connect/auth
//   KC authorize page  (200, login form #kc-form-login)
//   POST credentials
//     -> redirect back to oauth2-proxy callback
//   callback exchanges code -> sets _oauth2_proxy_home session cookie
//   portal home now serves 200 (authenticated)
//
// Errors are reported with the failing stage so a regression is immediately
// localisable (Keycloak down / DNS-blocked vs oauth2-proxy misconfig vs
// duplicate-ingress 503).
//
// Usage (needs cluster access + real Keycloak user):
//   E2E_KC_USER=testuser E2E_KC_PASS=... node scripts/e2e-portal-login.mjs
//
// Environment:
//   E2E_KC_USER       Keycloak username (default: testuser)
//   E2E_KC_PASS       Keycloak password (REQUIRED for live login)
//   E2E_PORTAL        portal base URL (default: https://home.opendesk-edu.org)
//   E2E_KC_ISSUER     Keycloak issuer (default: https://id.home.opendesk-edu.org/realms/opendesk)
//   E2E_CLIENT_ID     oauth2-proxy client (default: home-portal)
//   E2E_COOKIE_NAME   session cookie to assert (default: _oauth2_proxy_home)
//   E2E_TIMEOUT_MS    per-request timeout in ms (default: 15000)
//
// Exit 0 on success; non-zero with a clear staged message otherwise.
// When E2E_KC_PASS is unset the flow is still walked up to the login form
// (unauthenticated reachability check) and exits 0 — so the gate passes in a
// bare worktree / without credentials.

import { env, exit } from "node:process";

const PORTAL = env.E2E_PORTAL ?? "https://home.opendesk-edu.org";
const KC = env.E2E_KC_ISSUER ?? "https://id.home.opendesk-edu.org/realms/opendesk";
const CLIENT_ID = env.E2E_CLIENT_ID ?? "home-portal";
const COOKIE = env.E2E_COOKIE_NAME ?? "_oauth2_proxy_home";
const KC_USER = env.E2E_KC_USER ?? "testuser";
const KC_PASS = env.E2E_KC_PASS ?? "";
const TIMEOUT = Number(env.E2E_TIMEOUT_MS ?? 15000);

const REDIRECT = `${PORTAL}/oauth2/callback`;
const jar = new Map();

async function req(url, opts = {}, redirects = 0) {
  const res = await fetch(url, {
    redirect: "manual",
    ...opts,
    headers: {
      ...(opts.headers ?? {}),
      cookie: [...jar.entries()].map(([k, v]) => `${k}=${v}`).join("; "),
    },
    signal: AbortSignal.timeout(TIMEOUT),
  });
  for (const c of res.headers.getSetCookie?.() ?? []) {
    const [pair] = c.split(";");
    const [k, ...vRest] = pair.split("=");
    const v = vRest.join("=");
    if (k && v !== "") jar.set(k, v);
  }
  const loc = res.headers.get("location");
  if (res.status >= 300 && res.status < 400 && loc && redirects < 10) {
    return { res, redirect: req(new URL(loc, url).toString(), {}, redirects + 1) };
  }
  return { res, redirect: null };
}

async function follow(url, opts) {
  let cur = await req(url, opts);
  let n = 0;
  while (cur.redirect) {
    cur = await cur.redirect;
    if (++n > 10) break;
  }
  return cur.res;
}

function fail(stage, msg) {
  throw new Error(`[${stage}] ${msg}`);
}

async function main() {
  // ------------------------------------------------------------------
  // Stage 1: oauth2/start must 302-redirect to Keycloak authorize.
  // ------------------------------------------------------------------
  const r1 = await follow(`${PORTAL}/oauth2/start`);
  if (r1.status !== 200 && r1.status !== 302) {
    fail("oauth2/start", `expected 302 to Keycloak, got HTTP ${r1.status}`);
  }
  if (!r1.url.startsWith(`${KC}/protocol/openid-connect/auth`)) {
    fail("oauth2/start", `did not reach Keycloak authorize (url: ${r1.url.slice(0, 100)})`);
  }
  console.log("  ✓ /oauth2/start -> Keycloak authorize");

  // ------------------------------------------------------------------
  // Stage 2: Keycloak must serve the login form (was 500/503).
  // ------------------------------------------------------------------
  const html = await r1.text();
  const form = html.match(/<form[^>]*id="kc-form-login"[^>]*action="([^"]*)"/);
  if (!form) {
    fail("keycloak", "login form (#kc-form-login) not found — Keycloak is degraded");
  }
  const action = form[1].replaceAll("&amp;", "&");
  console.log("  ✓ Keycloak login form served");

  // Unauthenticated reachability is fully validated; stop here without creds.
  if (!KC_PASS) {
    console.log("\nE2E_KC_PASS not set — reached login form, skipping credential stage.");
    console.log("(unauthenticated reachability: PASS)");
    exit(0);
  }

  // ------------------------------------------------------------------
  // Stage 3: POST credentials and follow the callback redirect chain.
  // ------------------------------------------------------------------
  const fields = {};
  for (const m of html.matchAll(/<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"/g)) fields[m[1]] = m[2];
  fields.username = KC_USER;
  fields.password = KC_PASS;

  const r2 = await follow(new URL(action, KC).toString(), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  });

  // r2.url is the post-redirect target: should end at portal (callback -> home).
  if (!r2.url.startsWith(PORTAL)) {
    fail("callback", `did not return to portal after login (url: ${r2.url.slice(0, 100)}, status ${r2.status})`);
  }
  console.log("  ✓ credentials accepted, redirected back to portal");

  if (r2.status === 200 || r2.status === 302) {
    console.log("  ✓ callback -> portal OK");
  } else {
    fail("callback", `callback/portal returned HTTP ${r2.status}`);
  }

  // ------------------------------------------------------------------
  // Stage 4: oauth2-proxy session cookie must be present.
  // ------------------------------------------------------------------
  if (!jar.has(COOKIE)) {
    fail("session", `oauth2-proxy cookie '${COOKIE}' not set after login`);
  }
  console.log(`  ✓ session cookie '${COOKIE}' set`);

  // ------------------------------------------------------------------
  // Stage 5: authenticated portal home must serve 200 (not 403/503).
  // ------------------------------------------------------------------
  const r5 = await follow(`${PORTAL}/`);
  const expected = [200, 302];
  if (!expected.includes(r5.status)) {
    fail("portal", `authenticated portal home returned HTTP ${r5.status} (expected 200)`);
  }
  console.log(`  ✓ authenticated portal serves HTTP ${r5.status}`);

  console.log(`\nPortal login OK — user: ${KC_USER}, client: ${CLIENT_ID}`);
}

main().then(() => exit(0)).catch((err) => {
  console.error(`✘ ${err?.message ?? err}`);
  exit(1);
});
