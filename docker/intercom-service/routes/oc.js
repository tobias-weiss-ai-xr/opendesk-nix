/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
 *
 * /oc/ — OpenCloud proxy (fork extension; upstream only ships /fs/ for
 * Nextcloud). The user's token is exchanged via Keycloak to the
 * `opendesk-opencloud` audience (see middlewares/tokenRenewal.js) and injected
 * as a Bearer header.
 */

const express = require("express");
const router = express.Router();

const { createProxyMiddleware } = require("http-proxy-middleware");

const { stripIntercomCookies, massageCors, logger } = require("../utils");
const { corsOptions, logLevel, opencloud } = require("../config");

/**
 * @name /oc/
 * @desc Proxy for OpenCloud. Adds the proper Authorization Header.
 * @example PROPFIND http://ics.domain.test/oc/remote.php/dav/files/usera1/Photos
 */
const middleware = opencloud.enabled
  ? createProxyMiddleware({
      target: opencloud.url,
      logLevel,
      logger,
      changeOrigin: true,
      pathRewrite: {
        "^/oc": "",
      },
      onProxyReq: function onProxyReq(proxyReq, req, res) {
        stripIntercomCookies(proxyReq);
        if (!req.appSession[opencloud.session_storage_key]) {
          logger.info(
            "No OpenCloud session found in appSession. Likely OpenCloud is not configured",
          );
          return;
        }
        proxyReq.setHeader(
          "authorization",
          `Bearer ${req.appSession[opencloud.session_storage_key]}`,
        );
      },
      onProxyRes: function (proxyRes, req, res) {
        massageCors(req, proxyRes, corsOptions.origin);
      },
    })
  : (req, res, next) => next();

router.use("/", middleware);

module.exports = router;
