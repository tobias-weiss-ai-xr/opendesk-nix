/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
 *
 * /health — Kubernetes liveness/readiness endpoint (fork extension; upstream
 * has no health endpoint).
 */

const express = require("express");
const router = express.Router();

router.get("/", function (req, res) {
  res.status(200).json({ status: "ok" });
});

module.exports = router;
