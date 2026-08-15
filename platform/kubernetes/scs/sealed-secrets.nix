# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 openDesk Edu Contributors
#
# Sealed Secrets — Encrypt Kubernetes Secrets at rest using asymmetric encryption.
#
# The sealed-secrets CONTROLLER is deployed OUT-OF-BAND (one-time, manual) into
# the kube-system namespace from the upstream Bitnami manifest:
#
#   kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.36.0/controller.yaml
#
# It is intentionally NOT managed by this Nix module (this function returns an
# empty list): the live controller holds the RSA key secret (sealed-secrets-key*)
# and serves its self-signed CA. Managing it here would risk drift against the
# running instance.
#
# SERVICE Secrets (DB passwords, OIDC client secrets, the OpenCloud
# service-account secret, etc.) ARE sealed — see
# platform/kubernetes/scs/default.nix `serialize` / `sealSecret`, which run
# `kubeseal` against the committed public key
# (platform/kubernetes/sealed-secrets-pub.pem) at build time. The manifest
# output therefore never contains cleartext; the controller decrypts
# SealedSecrets into real Secrets at apply time.
#
# Seal a new secret once the controller is running and the cert is fetched:
#   kubeseal --cert sealed-secrets-pub.pem -n <ns> --name <name> -o yaml < secret.yaml
#   kubectl apply -f sealedsecret.yaml
#
# Aligns with ZKI checkpoint P0-DATA-001 (encryption at rest).

{ ... }:
[
  # No resources: the controller is deployed out-of-band (see header comment).
  # Service Secrets are sealed at serialization time in default.nix (`serialize`).
]
