/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2024-2025 Univention GmbH
 */

const express = require("express");
const router = express.Router();

const { createProxyMiddleware } = require("http-proxy-middleware");

const { stripIntercomCookies, massageCors, logger } = require("../utils");
const { corsOptions, logLevel, nordeck, matrix } = require("../config");

/**
 * @name /nob/
 * @desc
 * Proxy for the Nordeck Bot (or just the plain Matrix UserInfo Service in testing).
 * Adds the proper Authorization Header
 */
const middleware = nordeck.url
  ? createProxyMiddleware({
    target: nordeck.url,
    logLevel,
    logger,
    changeOrigin: true,
    pathRewrite: { "^/nob": "" },
    secure: false,
    onProxyReq: function onProxyReq(proxyReq, req, res) {
      stripIntercomCookies(proxyReq);
      // TODO: Build Switch for Nordeck Live Mode
      // Example headers.set('authorization', `MX-Identity ${btoa(JSON.stringify(t))}`);
      // or  proxyReq.setHeader('authorization', `Bearer ${matrix_access_token}`);

      if (!req.appSession[matrix.session_storage_key]) {
        logger.info(
          "No Matrix session found in appSession. Likely Matrix is not configured",
        );
        return;
      }
      // Provide access_token via authentication bearer token header
      // https://spec.matrix.org/v1.4/client-server-api/#client-authentication
      proxyReq.setHeader(
        "authorization",
        `Bearer ${req.appSession[matrix.session_storage_key]}`,
      );
    },
    onProxyRes: function (proxyRes, req, res) {
      // TODO: Matrix seems to be specific with it's headers, we have to decide whether to steamroll or to massage...
      massageCors(req, proxyRes, corsOptions.origin);
    },
    })
  : (req, res, next) => next();

router.use("/", middleware);

module.exports = router;
