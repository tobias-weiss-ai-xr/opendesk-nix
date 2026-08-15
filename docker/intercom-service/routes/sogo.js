/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
 *
 * /sogo/ — SOGo CalDAV/CardDAV proxy (fork extension). Enables calendar and
 * contact data access across apps.
 */

const express = require("express");
const router = express.Router();

const { createProxyMiddleware } = require("http-proxy-middleware");

const { stripIntercomCookies, massageCors, logger } = require("../utils");
const { corsOptions, logLevel, sogo } = require("../config");

/**
 * @name /sogo/
 * @desc Proxy for SOGo CalDAV/CardDAV. Adds the proper Authorization Header.
 * @example REPORT http://ics.domain.test/sogo/SOGo/dav/usera1/calendar/
 */
const middleware = sogo.enabled
  ? createProxyMiddleware({
      target: sogo.url,
      logLevel,
      logger,
      changeOrigin: true,
      pathRewrite: {
        "^/sogo": "",
      },
      onProxyReq: function onProxyReq(proxyReq, req, res) {
        stripIntercomCookies(proxyReq);
        if (!req.appSession[sogo.session_storage_key]) {
          logger.info(
            "No SOGo session found in appSession. Likely SOGo is not configured",
          );
          return;
        }
        proxyReq.setHeader(
          "authorization",
          `Bearer ${req.appSession[sogo.session_storage_key]}`,
        );
      },
      onProxyRes: function (proxyRes, req, res) {
        massageCors(req, proxyRes, corsOptions.origin);
      },
    })
  : (req, res, next) => next();

router.use("/", middleware);

module.exports = router;
