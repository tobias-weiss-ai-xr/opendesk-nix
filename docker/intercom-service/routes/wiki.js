/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2024-2025 Univention GmbH
 */

const express = require("express");
const router = express.Router();

const { createProxyMiddleware } = require("http-proxy-middleware");

const { stripIntercomCookies, massageCors, logger } = require("../utils");
const { corsOptions, logLevel, xwiki } = require("../config");

/**
 * @name /wiki/
 * @desc
 * Proxy for XWiki.
 * Adds the proper Authorization Header
 * @example GET http://ics.domain.test/wiki/bin/get/Blog/BlogRss?xpage=plain&blog=some.Newsfeed.WebHome
 */
const middleware = xwiki.enabled
  ? createProxyMiddleware({
    target: xwiki.url,
    logLevel,
    logger,
    changeOrigin: true,
    pathRewrite: {
      "^/wiki": "",
    },
    onProxyReq: function onProxyReq(proxyReq, req, res) {
      stripIntercomCookies(proxyReq);
      if (!req.appSession[xwiki.session_storage_key]) {
        logger.info(
          "No XWiki session found in appSession. Likely XWiki is not configured",
        );
        return;
      }
      proxyReq.setHeader(
        "authorization",
        `Bearer ${req.appSession[xwiki.session_storage_key]}`,
      );
      logger.debug("Correctly set Authorization header for XWiki proxy");
    },
    onProxyRes: function (proxyRes, req, res) {
      massageCors(req, proxyRes, corsOptions.origin);
    },
    })
  : (req, res, next) => next();

router.use("/", middleware);

module.exports = router;
