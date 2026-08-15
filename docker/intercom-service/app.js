/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2024-2025 Univention GmbH
 */

/*
 * Simple Backend for the Browser: OIDC Login, some Methods to call
 */
require("dotenv").config({ path: "./.env.prod" });
const express = require("express");
var app = express();
app.set("view engine", "ejs");
const {
  auth,
  requiresAuth,
  attemptSilentLogin,
} = require("express-openid-connect");
const csrfDSC = require("express-csrf-double-submit-cookie");
const cookieParser = require("cookie-parser");
const jose = require("jose");

var cors = require("cors");

const {
  corsOptions,
  issuerBaseUrl,
  sessionRollingDuration,
  enableSessionCookie,
  intercom,
  xwiki,
  nextcloud,
  opencloud,
  sogo,
  matrix,
  userUniqueMapper,
} = require("./config");

const {
  fetchMatrixToken,
  fetchOIDCToken,
  JWKS,
  redisStore,
  logger,
} = require("./utils");

const {
  backchannelLogout,
  fs,
  oc: ocRoute,
  sogo: sogoRoute,
  health: healthRoute,
  wiki,
  nob,
  navigation,
  silent,
  uuid,
} = require("./routes");

const {
  oidcVerifyDecodeAccessToken,
  oidcVerifyDecodeIdentityToken,
  refreshIntercomTokenIfNeeded,
  refreshOIDCTokenIfNeeded,
  updateSessionState,
  refreshMatrixTokenIfNeeded,
} = require("./middlewares");

const csrfProtection = csrfDSC({ cookie: { sameSite: "none", secure: true } });

app.use(express.urlencoded({ extended: true }));

app.use(
  auth({
    issuerBaseURL: issuerBaseUrl,
    baseURL: intercom.baseUrl,
    clientID: intercom.clientId,
    clientSecret: intercom.clientSecret,
    authRequired: false,
    secret: intercom.secret,
    idpLogout: true,
    authorizationParams: {
      response_type: "code",
      scope: "openid offline_access",
    },
    session: {
      store: redisStore,
      rollingDuration: sessionRollingDuration,
      cookie: {
        transient: enableSessionCookie,
      },
    },
    afterCallback: async (req, res, session, decodedState) => {
      // TODO: Add some kind of error handling, if tokens can't be fetched the user should see an error message of some sort
      try {
        var ret = {};

        // fetch token for xwiki
        if (!(xwiki.session_storage_key in session) && xwiki.enabled) {
          ret[xwiki.session_storage_key] = await fetchOIDCToken(
            session.access_token,
            xwiki.audience,
          );
        }

        if (!(nextcloud.session_storage_key in session) && nextcloud.enabled) {
          ret[nextcloud.session_storage_key] = await fetchOIDCToken(
            session.access_token,
            nextcloud.audience,
          );
        }

        const { payload } = await jose.jwtVerify(session.id_token, JWKS, {
          issuer: issuerBaseUrl,
        });
        let uid = payload[userUniqueMapper];

        if (!uid) {
          logger.warn(
            "Sorry can't find the preferred username/uuid, maybe the mapping is missing?",
          );
        }

        if (!(matrix.session_storage_key in session) && matrix.enabled) {
          logger.debug("Fetching Matrix access_token");
          ret[matrix.session_storage_key] = await fetchMatrixToken(uid);
        }
      } catch (error) {
        logger.error("Error fetching tokens: " + error);
      }
      return { ...session, ...ret };
    },
  }),
);

app.use(cors(corsOptions));
app.use(cookieParser());
app.use(csrfProtection);
app.use(updateSessionState);

/**
 * Just a simple Endpoint to check if the service is there and for CORS testing
 */
app.get("/", function (req, res) {
  res.send("<p>Hello</p>");
});

/**
 * @name /health
 * @desc Kubernetes liveness/readiness endpoint (openDesk Edu extension)
 */
app.use("/health", healthRoute);

/**
 * @name /backchannel-logout
 * @desc
 * OpenID Connect Backchannel Logout implementation to delete the session from the store
 */
app.use("/backchannel-logout", backchannelLogout);

/**
 * @name /nob/
 * @desc
 * Proxy for the Nordeck Bot (or just the plain Matrix UserInfo Service in testing).
 * Adds the proper Authorization Header
 */
app.use(
  "/nob",
  requiresAuth(),
  refreshIntercomTokenIfNeeded,
  csrfProtection.validate,
  oidcVerifyDecodeAccessToken(attemptSilentLogin),
  refreshMatrixTokenIfNeeded,
  nob,
);

/**
 * @name /fs/
 * @desc
 * Proxy for Nextcloud.
 * Adds the proper Authorization Header
 * @example PROPFIND http://ics.domain.test/fs/remote.php/dav/files/usera1/Photos
 *
 */
app.use(
  "/fs",
  requiresAuth(),
  refreshIntercomTokenIfNeeded,
  oidcVerifyDecodeAccessToken(attemptSilentLogin),
  refreshOIDCTokenIfNeeded(nextcloud),
  fs,
);

/**
 * @name /oc/
 * @desc
 * Proxy for OpenCloud (openDesk Edu extension).
 * Adds the proper Authorization Header (Keycloak token exchange to the
 * `opendesk-opencloud` audience).
 */
app.use(
  "/oc",
  requiresAuth(),
  refreshIntercomTokenIfNeeded,
  oidcVerifyDecodeAccessToken(attemptSilentLogin),
  refreshOIDCTokenIfNeeded(opencloud),
  ocRoute,
);

/**
 * @name /sogo/
 * @desc
 * Proxy for SOGo CalDAV/CardDAV (openDesk Edu extension).
 * Adds the proper Authorization Header.
 */
app.use(
  "/sogo",
  requiresAuth(),
  refreshIntercomTokenIfNeeded,
  refreshOIDCTokenIfNeeded(sogo),
  sogoRoute,
);

/**
 * @name /wiki/
 * @desc
 * Proxy for XWiki.
 * Adds the proper Authorization Header
 * @example GET http://ics.domain.test/wiki/bin/get/Blog/BlogRss?xpage=plain&blog=some.Newsfeed.WebHome
 */
app.use(
  "/wiki",
  requiresAuth(),
  refreshIntercomTokenIfNeeded,
  refreshOIDCTokenIfNeeded(xwiki),
  wiki,
);

/**
 * @name /navigation.json
 * @desc
 * Proxy to the portal for global Navigation Data.
 * Adds the proper Authorization Header
 */
app.use(
  "/navigation.json",
  requiresAuth(),
  refreshIntercomTokenIfNeeded,
  oidcVerifyDecodeAccessToken(attemptSilentLogin),
  oidcVerifyDecodeIdentityToken(attemptSilentLogin),
  navigation,
);

/**
 * @name /silent
 * @desc
 * Performs a "silent login", eg logs the user into the intercom service without interaction
 * if the user is already logged in to keycloak.
 *
 * Reports the Session Status via window.postmessage (JSON: {"loggedIn": true})
 */
app.use(
  "/silent",
  attemptSilentLogin(),
  oidcVerifyDecodeAccessToken(attemptSilentLogin),
  silent,
);

/**
 * @name /uuid
 * @desc returns the unique identifier claim of the logged in user
 */
app.use(
  "/uuid",
  requiresAuth(),
  refreshIntercomTokenIfNeeded,
  oidcVerifyDecodeIdentityToken(attemptSilentLogin),
  uuid,
);

var server = app.listen(process.env.PORT, function () {
  var host = server.address().address;
  var port = server.address().port;
  logger.info(`Intercom app listening at http://${host}:${port}`);
});
