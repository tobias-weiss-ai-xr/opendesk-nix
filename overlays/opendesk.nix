# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors

_final: prev: rec {
  opendesk = rec {
    inherit (prev)
      mariadb
      postgresql
      redis
      nginx
      ;
  };
}
