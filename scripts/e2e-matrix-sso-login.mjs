#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
//
// Matrix SSO login via Keycloak (opendesk-matrix client) — provisions the
// OIDC user in Synapse (mxid = @<opendesk_useruuid>:matrix.home.opendesk-edu.org)
// and returns a Matrix access_token. Prerequisite for the Intercom-Service
// appservice login (scripts/e2e-appservice.mjs live phase): the appservice
// impersonates EXISTING users only (non-exclusive namespace).
//
// Flow: GET /_matrix/client/v3/login/sso/redirect/oidc → Keycloak authorize →
// login form POST → synapse OIDC callback (token exchange) → "Continue to your
// account" page → submit → m.login.token exchange → access_token.
//
// Usage (inside a pod with network access, e.g. the intercom-service pod):
//   E2E_KC_USER=testuser E2E_KC_PASS=... node --input-type=module - < scripts/e2e-matrix-sso-login.mjs
//
// Environment:
//   E2E_KC_USER       Keycloak username (default: testuser)
//   E2E_KC_PASS       Keycloak password (REQUIRED)
//   E2E_MATRIX_HS     homeserver base URL (default: https://matrix.home.opendesk-edu.org)
//   E2E_KC_ISSUER     Keycloak issuer (default: https://id.home.opendesk-edu.org/realms/opendesk)
//   E2E_REDIRECT_URL  client redirect target (default: https://matrix.home.opendesk-edu.org/_synapse/client/oidc/callback)
//
// Exit 0 on success (prints access_token), non-zero with a clear message otherwise.

import { env, exit } from "node:process";

const HS = env.E2E_MATRIX_HS ?? "https://matrix.home.opendesk-edu.org";
const KC = env.E2E_KC_ISSUER ?? "https://id.home.opendesk-edu.org/realms/opendesk";
const REDIRECT = env.E2E_REDIRECT_URL ?? "https://matrix.home.opendesk-edu.org/_synapse/client/oidc/callback";
const KC_USER = env.E2E_KC_USER ?? "testuser";
const KC_PASS = env.E2E_KC_PASS;

if (!KC_PASS) {
  console.error("✘ E2E_KC_PASS is required (the Keycloak user password)");
  exit(1);
}

const jar = new Map();

async function req(url, opts = {}, redirects = 0) {
  const res = await fetch(url, {
    redirect: "manual",
    ...opts,
    headers: {
      ...(opts.headers ?? {}),
      cookie: [...jar.entries()].map(([k, v]) => `${k}=${v}`).join("; "),
    },
  });
  for (const c of res.headers.getSetCookie?.() ?? []) {
    const [pair] = c.split(";");
    const [k, v] = pair.split("=");
    if (k && v !== "") jar.set(k, v);
  }
  const loc = res.headers.get("location");
  if (res.status >= 300 && res.status < 400 && loc && redirects < 8) {
    return { res, redirect: req(new URL(loc, url).toString(), {}, redirects + 1) };
  }
  return { res, redirect: null };
}

async function follow(url, opts) {
  let cur = await req(url, opts);
  let n = 0;
  while (cur.redirect) {
    cur = await cur.redirect;
    if (++n > 8) break;
  }
  return cur.res;
}

async function main() {
  // 1. Start SSO (the idp id "oidc" is the synapse default for the first OIDC provider)
  const r1 = await follow(
    `${HS}/_matrix/client/v3/login/sso/redirect/oidc?redirectUrl=${encodeURIComponent(REDIRECT)}`,
  );
  if (!r1.url.includes("openid-connect/auth")) {
    throw new Error(`SSO start did not reach Keycloak authorize (status ${r1.status}, url ${r1.url.slice(0, 80)})`);
  }

  // 2. Keycloak login form
  const html = await (await follow(r1.url)).text();
  const form = html.match(/<form[^>]*id="kc-form-login"[^>]*action="([^"]*)"/);
  const action = form ? form[1].replaceAll("&amp;", "&") : null;
  if (!action) throw new Error("Keycloak login form not found");
  const fields = {};
  for (const m of html.matchAll(/<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"/g)) fields[m[1]] = m[2];
  fields.username = KC_USER;
  fields.password = KC_PASS;

  const r2 = await follow(new URL(action, KC).toString(), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  });
  let body = await r2.text();

  // 3. If synapse shows the "Continue to your account" page, the token exchange
  //    already succeeded; grab the loginToken from the page and exchange it.
  if (body.includes("Continue to your account")) {
    // synapse renders the confirmation as an anchor whose href carries the
    // loginToken (no form) — extract it and exchange it directly.
    const href = body.match(/href="([^"]*loginToken=[^"]*)"/)?.[1];
    const tok = href?.match(/loginToken=([A-Za-z0-9_-]+)/)?.[1];
    if (!tok) throw new Error("loginToken not found on the continue page");
    const r3 = await fetch(`${HS}/_matrix/client/v3/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "m.login.token", token: tok }),
    });
    const d3 = await r3.json();
    if (r3.status !== 200 || !d3.access_token) {
      throw new Error(`m.login.token failed: ${r3.status} ${JSON.stringify(d3).slice(0, 200)}`);
    }
    console.log(`Matrix SSO login OK — user_id: ${d3.user_id}`);
    console.log(`access_token: ${d3.access_token}`);
    return;
  }

  // 4. Fallback: the loginToken may be in the final redirect URL
  const m = r2.url.match(/loginToken=([^&]+)/);
  if (m) {
    const r3 = await fetch(`${HS}/_matrix/client/v3/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "m.login.token", token: decodeURIComponent(m[1]) }),
    });
    const d3 = await r3.json();
    if (r3.status !== 200 || !d3.access_token) {
      throw new Error(`m.login.token failed: ${r3.status} ${JSON.stringify(d3).slice(0, 200)}`);
    }
    console.log(`Matrix SSO login OK — user_id: ${d3.user_id}`);
    return;
  }
  throw new Error(`loginToken not found (final url: ${r2.url.slice(0, 160)})`);
}

main().then(() => exit(0)).catch((err) => {
  console.error(`✘ ${err?.message ?? err}`);
  exit(1);
});
