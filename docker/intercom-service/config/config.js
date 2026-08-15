/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2024-2025 Univention GmbH
 */

const issuerBaseUrl =
  process.env.ISSUER_BASE_URL ??
  `${process.env.KEYCLOAK_URL}/auth/realms/${process.env.REALM_NAME}`;

const config = {
  corsOptions: {
    methods: "GET,POST,PUT,DELETE,PROPFIND,MKCOL",
    credentials: true,
    // TODO: can we drop Authorization?
    exposedHeaders: [
      "etag",
      "dav",
      "Content-Security-Policy",
      "Location",
      "Authorization",
      "depth",
      "content-type",
      "ocs-apirequest",
    ],
    origin: new RegExp(process.env.ORIGIN_REGEX),
  },
  issuerBaseUrl,
  logLevel: `${process.env.LOG_LEVEL}`.toLowerCase() ?? "info",
  enableSessionCookie: JSON.parse(
    (process.env.ENABLE_SESSION_COOKIE ?? "false").toLowerCase(),
  ),
  sessionRollingDuration: JSON.parse(
    process.env.SESSION_ROLLING_DURATION ?? 86400,
  ),
  userUniqueMapper: process.env.USER_UNIQUE_MAPPER ?? "entryuuid",
  usernameClaim: process.env.USERNAME_CLAIM ?? "phoenixusername",
  nordeck: {
    url: process.env.NORDECK_URL,
  },
  portal: {
    url: process.env.PORTAL_URL,
    secret: process.env.PORTAL_API_KEY,
  },
  xwiki: {
    enabled: JSON.parse((process.env.XWIKI_ENABLED ?? "false").toLowerCase()),
    name: "XWiki",
    url: process.env.XWIKI_URL,
    audience: process.env.XWIKI_AUDIENCE,
    session_storage_key: "xwiki_access_token",
  },
  nextcloud: {
    enabled: JSON.parse((process.env.NC_ENABLED ?? "false").toLowerCase()),
    name: "Nextcloud",
    url: process.env.NC_URL,
    audience: process.env.NC_AUDIENCE,
    session_storage_key: "nc_access_token",
  },
  opencloud: {
    enabled: JSON.parse((process.env.OC_ENABLED ?? "false").toLowerCase()),
    name: "OpenCloud",
    url: process.env.OC_URL,
    audience: process.env.OC_AUDIENCE,
    session_storage_key: "oc_access_token",
  },
  sogo: {
    enabled: JSON.parse((process.env.SOGO_ENABLED ?? "false").toLowerCase()),
    name: "SOGo",
    url: process.env.SOGO_URL,
    session_storage_key: "sogo_access_token",
  },

  intercom: {
    clientId: process.env.CLIENT_ID,
    clientSecret: process.env.CLIENT_SECRET,
    proxy: JSON.parse((process.env.PROXY ?? "false").toLowerCase()),
    secret: process.env.SECRET,
    baseUrl: process.env.BASE_URL,
  },
  matrix: {
    enabled: JSON.parse((process.env.MATRIX_ENABLED ?? "false").toLowerCase()),
    name: "Matrix",
    url: process.env.MATRIX_URL,
    appServiceSecret: process.env.MATRIX_AS_SECRET,
    session_storage_key: "matrix_access_token",
  },
  redis: {
    user: process.env.REDIS_USER ?? "default",
    password: process.env.REDIS_PASSWORD,
    host: process.env.REDIS_HOST ?? "redis-intercom",
    port: process.env.REDIS_PORT ?? 6379,
    caPath: process.env.NODE_EXTRA_CA_CERTS ?? "...",
    mTLS: JSON.parse((process.env.REDIS_MTLS ?? "false").toLowerCase()),
    SSL: JSON.parse((process.env.REDIS_SSL ?? "false").toLowerCase()),
  },
};

module.exports = config;
