/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2024-2025 Univention GmbH
 */

const express = require("express");
const router = express.Router();

const { createProxyMiddleware } = require("http-proxy-middleware");

const { stripIntercomCookies, massageCors, logger } = require("../utils");
const { corsOptions, logLevel, nextcloud } = require("../config");

/**
 * @name /fs/
 * @desc Proxy for Nextcloud. Adds the proper Authorization Header.
 * @example PROPFIND http://ics.domain.test/fs/remote.php/dav/files/usera1/Photos
 */
const middleware = nextcloud.enabled
  ? createProxyMiddleware({
      target: nextcloud.url,
      logLevel,
      logger,
      changeOrigin: true,
      pathRewrite: {
        "^/fs": "",
      },
      onProxyReq: function onProxyReq(proxyReq, req, res) {
        stripIntercomCookies(proxyReq);
        if (!req.appSession[nextcloud.session_storage_key]) {
          logger.info(
            "No Nextcloud session found in appSession. Likely Nextcloud is not configured",
          );
          return;
        }
        proxyReq.setHeader(
          "authorization",
          `Bearer ${req.appSession[nextcloud.session_storage_key]}`,
        );
      },
      onProxyRes: function (proxyRes, req, res) {
        massageCors(req, proxyRes, corsOptions.origin);
      },
    })
  : (req, res, next) => next();

router.use("/", middleware);

module.exports = router;
