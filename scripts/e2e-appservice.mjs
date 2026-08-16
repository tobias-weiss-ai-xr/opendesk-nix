#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
//
// Matrix appservice registration acceptance test — MA-2 TDD artifact for
// plan/2026-08-16-matrix-appservice-plan.md (RED until MA-1 lands in
// platform/kubernetes/services/synapse.nix).
//
// Mirrors the Intercom-Service Matrix login flow (m.login.application_service,
// cf. docker/intercom-service): the ICS fetches a per-user access token with
//
//   POST https://matrix.home.opendesk-edu.org/_matrix/client/v3/login
//   Authorization: Bearer <MATRIX_AS_SECRET>        # the appservice as_token
//   { "type": "m.login.application_service",
//     "identifier": { "type": "m.id.user", "user": "<uid>" } }
//
// which only works once Synapse is registered as an application service
// (app_service_config_files in homeserver.yaml).
//
// Two phases:
//   1. Manifest assertions — the rendered Synapse manifest must contain the
//      appservice wiring: app_service_config_files pointing at
//      /config/appservice/intercom.yaml, the templated registration file
//      (sender_localpart + __MATRIX_AS_TOKEN__ / __MATRIX_HS_TOKEN__
//      placeholders rendered by the init-config initContainer), and the
//      synapse-appservice SealedSecret (keys matrix-as-token / matrix-hs-token).
//   2. Live login assertion — performed only when MATRIX_AS_SECRET is set
//      (the as_token from the sealed `intercom` Secret, key `matrix-as-token`,
//      opendesk-edu ns). Without it the script runs manifest-only and exits 0,
//      so the gate passes in a bare worktree.
//
// Usage:
//   node scripts/e2e-appservice.mjs [manifest.yaml]   (default: result/30-synapse.yaml)
//
// Environment:
//   MATRIX_AS_SECRET       appservice as_token — enables the live login phase
//   E2E_MATRIX_USER        localpart to log in as (default: testuser)
//   E2E_MATRIX_HOMESERVER  homeserver base URL (default: https://matrix.home.opendesk-edu.org)
//
// Exit codes: 0 = all assertions passed (or live phase skipped),
//             1 = an assertion failed or the manifest is missing/unreadable.

import { readFileSync } from "node:fs";
import { argv, env, exit } from "node:process";

const MANIFEST_PATH = argv[2] ?? "result/30-synapse.yaml";
const HOMESERVER = env.E2E_MATRIX_HOMESERVER ?? "https://matrix.home.opendesk-edu.org";
const MATRIX_USER = env.E2E_MATRIX_USER ?? "testuser";
const LOGIN_URL = `${HOMESERVER}/_matrix/client/v3/login`;

const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let failures = 0;
const ok = (msg) => console.log(`  ${GREEN}✔${RESET} ${msg}`);
const bad = (msg) => {
  failures += 1;
  console.log(`  ${RED}✘${RESET} ${msg}`);
};

function assertManifest(manifest) {
  console.log(`\n${BOLD}== 1. Manifest assertions (${MANIFEST_PATH}) ==${RESET}`);
  // Required wiring from plan §"Changes" MA-1 (needles appear verbatim in the
  // emitted result/30-synapse.yaml — SealedSecrets keep their key names).
  const needles = [
    ["app_service_config_files", "homeserver.yaml registers the appservice"],
    ["intercom.yaml", "registration file path (appservice/intercom.yaml)"],
    ["sender_localpart", "registration template sender_localpart"],
    ["__MATRIX_AS_TOKEN__", "as_token placeholder (init-config sed)"],
    ["__MATRIX_HS_TOKEN__", "hs_token placeholder (init-config sed)"],
    ["synapse-appservice", "synapse-appservice Secret is emitted"],
    ["matrix-as-token", "Secret key matrix-as-token (sealed)"],
    ["matrix-hs-token", "Secret key matrix-hs-token (sealed)"],
  ];
  for (const [needle, why] of needles) {
    if (manifest.includes(needle)) {
      ok(`${needle} — ${why}`);
    } else {
      bad(`missing "${needle}" — ${why}`);
    }
  }
  if (failures > 0) {
    console.error(
      `${RED}Manifest wiring incomplete — implement MA-1 in platform/kubernetes/services/synapse.nix${RESET}`,
    );
  }
}

async function liveLogin() {
  console.log(`\n${BOLD}== 2. Live appservice login (${LOGIN_URL}) ==${RESET}`);
  const token = env.MATRIX_AS_SECRET;
  if (!token) {
    console.log("  (skipped — MATRIX_AS_SECRET not set; manifest-only mode)");
    return;
  }
  const res = await fetch(LOGIN_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      type: "m.login.application_service",
      identifier: { type: "m.id.user", user: MATRIX_USER },
    }),
  });
  const body = await res.text();
  if (res.status !== 200) {
    bad(`login as "${MATRIX_USER}" -> HTTP ${res.status}: ${body}`);
    return;
  }
  let json;
  try {
    json = JSON.parse(body);
  } catch {
    bad(`login 200 but body is not JSON: ${body.slice(0, 200)}`);
    return;
  }
  if (typeof json.access_token === "string" && json.access_token.length > 0) {
    ok(`m.login.application_service as "${MATRIX_USER}" -> 200 + access_token`);
  } else {
    bad(`login 200 but no access_token in response: ${body.slice(0, 200)}`);
  }
}

async function main() {
  let manifest;
  try {
    manifest = readFileSync(MANIFEST_PATH, "utf8");
  } catch (err) {
    console.error(
      `${RED}✘ cannot read manifest "${MANIFEST_PATH}": ${err.message}${RESET}`,
    );
    console.error("  build it first: nix build .#scs-manifests");
    exit(1);
  }
  assertManifest(manifest);
  if (failures > 0) {
    console.error(`\n${BOLD}Result: ${failures} assertion(s) failed${RESET}`);
    exit(1);
  }
  await liveLogin();
  if (failures > 0) {
    console.error(`\n${BOLD}Result: ${failures} assertion(s) failed${RESET}`);
    exit(1);
  }
  console.log(`\n${GREEN}${BOLD}Result: e2e-appservice passed${RESET}`);
}

main().catch((err) => {
  console.error(`${RED}✘ unexpected error: ${err?.stack ?? err}${RESET}`);
  exit(1);
});
