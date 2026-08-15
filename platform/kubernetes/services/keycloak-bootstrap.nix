# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Keycloak Bootstrap — idempotent provisioning Job for the `opendesk` realm.
#
# The Keycloak deployment only contains the `master` realm. This Job creates
# the `opendesk` realm, the OpenLDAP user federation and the OIDC clients the
# platform needs (intercom, opencloud, matrix, sogo) via kcadm.sh. Every step
# is get-or-create, so the Job is safe to run multiple times.
#
# The realm model lives in env.keycloak.bootstrap (environments/scs/default.nix)
# as pure data; this file renders it into the bootstrap script and wraps it in
# a batch/v1 Job + ConfigMap + sealed client-secret (SealedSecret at build time).
#
# Image: docker.io/keycloak/keycloak:26.0 (matches live keycloak)

{
  lib,
  env ? import ../environments/scs/default.nix { inherit lib; },
  ...
}:

let
  name = "keycloak-bootstrap";
  image = "docker.io/keycloak/keycloak";
  tag = "26.0";

  realm = env.keycloak.realm;
  bootstrap = env.keycloak.bootstrap;

  labels = lib.mkLabels { inherit name; } // {
    "app.kubernetes.io/component" = "identity";
    "app.kubernetes.io/managed-by" = "nix";
  };

  resources = {
    requests = {
      cpu = "100m";
      memory = "128Mi";
    };
    limits = {
      cpu = "500m";
      memory = "512Mi";
    };
  };

  securityContext = {
    allowPrivilegeEscalation = false;
    runAsNonRoot = true;
    runAsUser = 1000;
    readOnlyRootFilesystem = false;
    capabilities = {
      drop = [ "ALL" ];
    };
    seccompProfile = {
      type = "RuntimeDefault";
    };
  };

  podSecurityContext = {
    runAsNonRoot = true;
    runAsUser = 1000;
    fsGroup = 1000;
    fsGroupChangePolicy = "OnRootMismatch";
  };

  # =========================================================================
  # kcadm -s argument rendering (realm model -> kcadm.sh flags)
  # =========================================================================

  # Quote dotted path segments for kcadm's JSON-path syntax, e.g.
  # `attributes."use.refresh.tokens"` or `config."user.attribute"`.
  quotePathKey = key:
    let
      parts = lib.splitString "." key;
      head = builtins.head parts;
      rest = lib.concatStringsSep "." (builtins.tail parts);
    in
      if rest == "" then key
      else if builtins.match ".*\\..*" rest != null then "${head}.\"${rest}\""
      else key;

  # Render a kcadm `-s` value: strings/booleans as JSON scalars, lists as JSON
  # arrays (Keycloak component config values are string arrays).
  kcadmValue = v:
    if builtins.isBool v then (if v then "true" else "false")
    else if builtins.isInt v then toString v
    else if builtins.isString v then "\"${v}\""
    else if builtins.isList v then "[${lib.concatMapStringsSep "," (x: "\"${x}\"") v}]"
    else abort "keycloak-bootstrap: unsupported kcadm value type";

  kcadmArg = key: value: "-s '${quotePathKey key}=${kcadmValue value}'";

  # Space-joined `-s` args for a flat attrset (optionally under a path prefix).
  kcadmArgs = prefix: attrs:
    lib.concatMapStringsSep " " (
      k: kcadmArg (if prefix == "" then k else "${prefix}.${k}") attrs.${k}
    ) (builtins.attrNames attrs);

  # Join generated args with shell line-continuations (cosmetic only).
  multiLine = args: lib.concatStringsSep " \\\n  " args;

  realmArgs = kcadmArgs "" bootstrap.realm;

  ldap = bootstrap.ldap;
  ldapArgs = multiLine (
    [
      (kcadmArg "name" ldap.name)
      (kcadmArg "providerId" ldap.providerId)
      (kcadmArg "providerType" ldap.providerType)
      (kcadmArg "parentId" realm)
    ]
    ++ (lib.mapAttrsToList (k: v: kcadmArg "config.${k}" v) ldap.config)
  );

  # get-or-create block for one protocol mapper (on the resolved $uuid client).
  renderMapper = m:
    let
      configArgs = lib.mapAttrsToList (k: v: kcadmArg "config.${k}" v) m.config;
      createArgs = multiLine (
        [
          (kcadmArg "name" m.name)
          (kcadmArg "protocol" "openid-connect")
          (kcadmArg "protocolMapper" m.protocolMapper)
        ]
        ++ configArgs
      );
    in
    ''
      if ! "$KC" get clients/$uuid/protocol-mappers/models -r "$REALM" 2>/dev/null | grep -q '"name"[[:space:]]*:[[:space:]]*"${m.name}"'; then
        echo "[bootstrap]   creating protocol mapper '${m.name}'"
        "$KC" create clients/$uuid/protocol-mappers/models -r "$REALM" \
          ${createArgs}
      else
        echo "[bootstrap]   protocol mapper '${m.name}' already exists"
      fi
    '';

  # get-or-create block for one OIDC client + its protocol mappers.
  renderClient = c:
    let
      attrArgs = lib.mapAttrsToList (k: v: kcadmArg "attributes.${k}" v) c.attributes;
      createArgs = multiLine (
        [
          (kcadmArg "clientId" c.clientId)
          (kcadmArg "enabled" true)
          (kcadmArg "publicClient" false)
          (kcadmArg "consentRequired" false)
          (kcadmArg "frontchannelLogout" false)
          (kcadmArg "authorizationServicesEnabled" false)
          (kcadmArg "defaultClientScopes" [ "offline_access" ])
          (kcadmArg "redirectUris" c.redirectUris)
        ]
        ++ attrArgs
        # Client secret comes from the sealed keycloak-clients Secret (never a
        # cleartext literal in the ConfigMap script).
        ++ [ "-s secret=\"$(cat /mnt/secrets/${c.secretKey})\"" ]
      );
      mappers = bootstrap.protocolMappers ++ (c.mappers or [ ]);
      mapperBlocks = lib.concatMapStringsSep "\n" renderMapper mappers;
    in
    ''
      # --- client: ${c.clientId} --------------------------------------------
      if "$KC" get clients -r "$REALM" -q "clientId=${c.clientId}" 2>/dev/null | grep -q '"clientId"'; then
        echo "[bootstrap] client '${c.clientId}' already exists"
      else
        echo "[bootstrap] creating client '${c.clientId}'"
        "$KC" create clients -r "$REALM" \
          ${createArgs}
      fi

      # Resolve the internal client uuid, then get-or-create the protocol
      # mappers (mappers need the uuid, not the clientId, in the URL path).
      uuid=$("$KC" get clients -r "$REALM" -q "clientId=${c.clientId}" 2>/dev/null \
        | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
      if [ -z "$uuid" ]; then
        echo "[bootstrap] WARNING: could not resolve uuid for client '${c.clientId}', skipping mappers" >&2
      else
      ${mapperBlocks}
      fi
    '';

  bootstrapScript = ''
    #!/bin/bash
    # SPDX-License-Identifier: Apache-2.0
    #
    # Idempotent Keycloak bootstrap: realm + LDAP federation + OIDC clients.
    # Every step is get-or-create; safe to run multiple times.
    # Rendered from env.keycloak.bootstrap by keycloak-bootstrap.nix.

    set -eu

    KC=/opt/keycloak/bin/kcadm.sh
    KCHOST=${env.keycloak.internalUrl}
    REALM=${realm}
    ADMIN_USER=${bootstrap.adminUser}
    ADMIN_PASSWORD_FILE=/mnt/secrets-admin/admin-password

    echo "[bootstrap] waiting for Keycloak at $KCHOST ..."
    # The keycloak:26.0 image has no curl/wget — use a bash /dev/tcp probe.
    # (sh is bash on this image; /dev/tcp needs a bash shell.)
    KC_HOST="$(echo "$KCHOST" | sed 's|.*://||; s|:.*||')"
    KC_PORT="$(echo "$KCHOST" | sed 's|.*:||')"
    i=0
    until (echo > "/dev/tcp/$KC_HOST/$KC_PORT") 2>/dev/null; do
      i=$((i + 1))
      if [ "$i" -ge 120 ]; then
        echo "[bootstrap] Keycloak not ready after 120s" >&2
        exit 1
      fi
      sleep 1
    done
    echo "[bootstrap] Keycloak is ready."
    # Give the HTTP layer a moment, then authenticate (retries if needed).
    sleep 3

    # Authenticate against the master realm (sealed keycloak-db secret,
    # key `admin-password`, mounted read-only at /mnt/secrets-admin).
    "$KC" config credentials --server "$KCHOST" --realm master --user "$ADMIN_USER" \
      --password "$(cat "$ADMIN_PASSWORD_FILE")"

    # --- realm ---------------------------------------------------------------
    if "$KC" get "realms/$REALM" >/dev/null 2>&1; then
      echo "[bootstrap] realm '$REALM' already exists"
    else
      echo "[bootstrap] creating realm '$REALM'"
      "$KC" create realms \
        ${realmArgs}
    fi

    # --- LDAP user federation -------------------------------------------------
    if "$KC" get components -r "$REALM" 2>/dev/null | grep -q '"name"[[:space:]]*:[[:space:]]*"${ldap.name}"'; then
      echo "[bootstrap] LDAP federation '${ldap.name}' already exists"
    else
      echo "[bootstrap] creating LDAP federation '${ldap.name}'"
      "$KC" create components -r "$REALM" \
        ${ldapArgs}
    fi

    # --- OIDC clients ----------------------------------------------------------
    ${lib.concatMapStringsSep "\n" renderClient bootstrap.clients}

    echo "[bootstrap] done."
  '';

in
[
  # batch/v1 Job — runs the bootstrap script once per invocation (idempotent).
  ({
    apiVersion = "batch/v1";
    kind = "Job";
    metadata = {
      inherit name;
      namespace = env.namespace;
      inherit labels;
    };
    spec = {
      backoffLimit = 4;
      ttlSecondsAfterFinished = 86400;
      template = {
        metadata = {
          inherit labels;
        };
        spec = {
          restartPolicy = "Never";
          securityContext = podSecurityContext;
          containers = [
            {
              inherit name;
              image = "${image}:${tag}";
              imagePullPolicy = "IfNotPresent";
              command = [ "/bin/sh" "/mnt/scripts/bootstrap.sh" ];
              env = [
                {
                  # kcadm writes its credentials config under $HOME/.keycloak
                  name = "HOME";
                  value = "/tmp";
                }
              ];
              inherit resources;
              inherit securityContext;
              volumeMounts = [
                {
                  name = "scripts";
                  mountPath = "/mnt/scripts";
                  readOnly = true;
                }
                {
                  name = "secrets";
                  mountPath = "/mnt/secrets";
                  readOnly = true;
                }
                {
                  name = "secrets-admin";
                  mountPath = "/mnt/secrets-admin";
                  readOnly = true;
                }
              ];
            }
          ];
          volumes = [
            {
              name = "scripts";
              configMap = {
                name = "keycloak-bootstrap";
                defaultMode = 493;
              };
            }
            {
              name = "secrets";
              secret = {
                secretName = "keycloak-clients";
              };
            }
            {
              name = "secrets-admin";
              secret = {
                secretName = "keycloak-db";
                items = [
                  {
                    key = "admin-password";
                    path = "admin-password";
                  }
                ];
              };
            }
          ];
        };
      };
    };
  })

  # Bootstrap script ConfigMap (mode 0755, galera initdb pattern). No secrets
  # here — client secrets are read from /mnt/secrets at runtime.
  (lib.configMap {
    name = "keycloak-bootstrap";
    namespace = env.namespace;
    inherit labels;
    data = {
      "bootstrap.sh" = bootstrapScript;
    };
  })

  # OIDC client secrets — sealed at build time (scs/default.nix `serialize`).
  # The opencloud value matches the existing sealed secret
  # opendesk-opencloud-db / oidc-client-secret ("opencloud-secret-change-me");
  # it lives here (not in opendesk-edu) because a pod can only mount secrets
  # from its own namespace and the Job runs in `opendesk`.
  (lib.secret {
    name = "keycloak-clients";
    namespace = env.namespace;
    inherit labels;
    stringData = {
      "intercom-client-secret" = "intercom-client-secret-change-me";
      "matrix-client-secret" = "matrix-client-secret-change-me";
      "sogo-client-secret" = "sogo-client-secret-change-me";
      "opencloud-client-secret" = "opencloud-secret-change-me";
    };
  })
]
