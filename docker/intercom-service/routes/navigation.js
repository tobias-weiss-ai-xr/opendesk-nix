/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2024-2025 Univention GmbH
 */

const express = require("express");
const router = express.Router();

const { createProxyMiddleware } = require("http-proxy-middleware");

const { stripIntercomCookies, massageCors, logger } = require("../utils");
const { corsOptions, logLevel, portal, usernameClaim } = require("../config");

/**
 * @name "/portal.json (without silly quotes for jsdoc)"
 * @desc
 * Proxy to the portal for global Navigation Data.
 * Adds the proper Authorization Header
 */
// TODO: https://127.0.0.1/univention/portal/navigation.json?lang=de_DE -H "Authorization: Basic username:MyPortalSecretFromBMIUXAnsibleHostINI"
const middleware = portal.url
  ? createProxyMiddleware({
    target: portal.url,
    logLevel,
    logger,
    changeOrigin: true,
    pathRewrite: { "^/navigation.json": "/univention/portal/navigation.json" },
    onProxyReq: function onProxyReq(proxyReq, req, res) {
      stripIntercomCookies(proxyReq);
      if (!req?.decodedIdToken?.[usernameClaim]) {
        logger.error("No claim %s found in the id_token", usernameClaim);
        logger.error("Error setting Authorization Header for portal.json");
        return;
      }
      proxyReq.setHeader(
        "Authorization",
        "Basic " +
          Buffer.from(
            req.decodedIdToken[usernameClaim] + ":" + portal.secret,
          ).toString("base64"),
      );
    },
    onProxyRes: function (proxyRes, req, res) {
      massageCors(req, proxyRes, corsOptions.origin);
    },
    })
  : (req, res, next) => next();

router.use("/", middleware);

module.exports = router;
