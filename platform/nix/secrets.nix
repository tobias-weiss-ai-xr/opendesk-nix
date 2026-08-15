# Decrypt a per-environment sops+age encrypted secrets store.
#
# Usage:
#   let secretsLib = import ../../nix/secrets.nix { inherit pkgs; };
#       secrets    = secretsLib ../secrets/scs.enc.json;
#   in secrets.opencloud.service_account_secret
#
# Requires SOPS_AGE_KEY in the build environment (CI secret) or
# ~/.config/sops/age/keys.txt. When the key is absent the store decrypts to
# an EMPTY attrset so `nix flake check` / evaluation still succeeds; the real
# secrets are only materialized when the key is present (i.e. at deploy time).
#
# Rotation: `sops edit <store>` to add/change values, or use
# scripts/secrets/rotate.sh <service> <key> for a random value. Then commit
# and redeploy. One file holds every service's secrets for the environment.
{ pkgs }:

envSecretsPath:

  builtins.fromJSON (builtins.readFile (pkgs.runCommand "env-secrets" {
    nativeBuildInputs = [ pkgs.sops ];
    SOPS_AGE_KEY = builtins.getEnv "SOPS_AGE_KEY";
  } ''
    export SOPS_AGE_KEY="$SOPS_AGE_KEY"
    if [ -n "$SOPS_AGE_KEY" ]; then
      sops -d ${envSecretsPath} > $out
    else
      echo '{}' > $out
    fi
  ''))
