/**
 * SPDX-License-Identifier: AGPL-3.0-only
 * SPDX-FileCopyrightText: 2024-2025 Univention GmbH
 */

const backchannelLogout = require("./backchannelLogout");
const fs = require("./fs");
const oc = require("./oc");
const sogo = require("./sogo");
const health = require("./health");
const wiki = require("./wiki");
const nob = require("./nob");
const navigation = require("./navigation");
const silent = require("./silent");
const uuid = require("./uuid");

module.exports = {
  backchannelLogout,
  fs,
  oc,
  sogo,
  health,
  wiki,
  nob,
  navigation,
  silent,
  uuid,
};
