#!/usr/bin/env bash
# Builds the image, starts it with different env vars and checks the imported
# realm through the admin REST API.
# Usage: tests/smoke-test.sh [image]   (no arg = build from ./Dockerfile)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${1:-saashup-keycloak:test}"
PORT="${PORT:-18080}"
NAME="kc-smoke-$$"
ADMIN_PASSWORD="smoke-admin-pw"
FAILED=0

[[ $# -eq 0 ]] && docker build -t "$IMAGE" "$ROOT"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILED=1; }

check() { # description, actual, expected
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected '$3', got '$2')"; fi
}
check_nonempty() { # description, actual
  if [[ -n "$2" && "$2" != "null" ]]; then pass "$1"; else fail "$1 (empty)"; fi
}

start() { # docker run args...
  cleanup
  docker run -d --name "$NAME" -p "$PORT:8080" \
    -e KC_BOOTSTRAP_ADMIN_PASSWORD="$ADMIN_PASSWORD" "$@" "$IMAGE" start-dev >/dev/null
  for _ in $(seq 1 90); do
    curl -fs "http://localhost:$PORT/auth/realms/master" >/dev/null 2>&1 && return 0
    sleep 2
  done
  docker logs "$NAME" | tail -50
  echo "Keycloak did not start" >&2; exit 1
}

api() { curl -fs -H "Authorization: Bearer $TOKEN" "http://localhost:$PORT/auth/admin/realms/$1"; }

login() {
  TOKEN="$(curl -fs -d client_id=admin-cli -d username=admin -d "password=$ADMIN_PASSWORD" \
    -d grant_type=password "http://localhost:$PORT/auth/realms/master/protocol/openid-connect/token" | jq -r .access_token)"
}

client() { api "$REALM/clients?clientId=$1" | jq -c '.[0]'; }

REALM=paashup

echo "== Case 1: defaults (BASE_DOMAIN only)"
start -e BASE_DOMAIN=example.com
login
check "realm exists" "$(api "$REALM" | jq -r .realm)" "$REALM"
check "admin group exists" "$(api "$REALM/groups?search=SaasHup-Admins" | jq -r '.[0].name')" "SaasHup-Admins"
check "seed user exists" "$(api "$REALM/users?username=saashup&exact=true" | jq -r '.[0].username')" "saashup"

G="$(client grafana)"; S="$(client saashup)"
check "grafana redirectUris" "$(jq -r '.redirectUris|join(",")' <<<"$G")" "https://example.com/dashboard/login/generic_oauth"
check "grafana webOrigins" "$(jq -r '.webOrigins|join(",")' <<<"$G")" "https://example.com"
check "grafana post logout uris" "$(jq -r '.attributes["post.logout.redirect.uris"]' <<<"$G")" "https://example.com/dashboard##https://example.com/dashboard/*"
check "saashup redirectUris" "$(jq -r '.redirectUris|join(",")' <<<"$S")" "https://example.com/oidc/callback"
check "saashup webOrigins" "$(jq -r '.webOrigins|join(",")' <<<"$S")" "https://example.com"
check "saashup post logout uris" "$(jq -r '.attributes["post.logout.redirect.uris"]' <<<"$S")" "https://example.com/*"
check_nonempty "grafana secret generated" "$(api "$REALM/clients/$(jq -r .id <<<"$G")/client-secret" | jq -r .value)"
P="$(client paasbox)"
check "paasbox redirectUris" "$(jq -r '.redirectUris|join(",")' <<<"$P")" "https://example.com/datacenter/*"
check "paasbox webOrigins" "$(jq -r '.webOrigins|join(",")' <<<"$P")" "https://example.com"
check "paasbox post logout uris" "$(jq -r '.attributes["post.logout.redirect.uris"]' <<<"$P")" "https://example.com/datacenter/*"
check_nonempty "paasbox secret generated" "$(api "$REALM/clients/$(jq -r .id <<<"$P")/client-secret" | jq -r .value)"
check_nonempty "saashup secret generated" "$(api "$REALM/clients/$(jq -r .id <<<"$S")/client-secret" | jq -r .value)"
check "auto-link flow exists" "$(api "$REALM/authentication/flows" | jq -r '[.[]|select(.alias=="first broker login auto-link")]|length')" "1"
check "no identity providers" "$(api "$REALM/identity-provider/instances" | jq length)" "0"

echo "== Case 2: overrides + identity providers"
start -e BASE_DOMAIN=example.com -e KEYCLOAK_REALM=other \
  -e GRAFANA_OIDC_CLIENT_SECRET=fixed-grafana-secret \
  -e GRAFANA_POST_LOGOUT_REDIRECT_URIS=https://logout.example.org/bye \
  -e SAASHUP_POST_LOGOUT_REDIRECT_URIS=https://a.example.org/*##https://b.example.org/* \
  -e GOOGLE_CLIENT_ID=gid -e GOOGLE_CLIENT_SECRET=gsecret \
  -e GITHUB_CLIENT_ID=hid -e GITHUB_CLIENT_SECRET=hsecret
login
REALM=other
check "custom realm exists" "$(api "$REALM" | jq -r .realm)" "other"
G="$(client grafana)"; S="$(client saashup)"
check "grafana post logout override" "$(jq -r '.attributes["post.logout.redirect.uris"]' <<<"$G")" "https://logout.example.org/bye"
check "saashup post logout override" "$(jq -r '.attributes["post.logout.redirect.uris"]' <<<"$S")" "https://a.example.org/*##https://b.example.org/*"
check "grafana fixed secret" "$(api "$REALM/clients/$(jq -r .id <<<"$G")/client-secret" | jq -r .value)" "fixed-grafana-secret"
check "idp aliases" "$(api "$REALM/identity-provider/instances" | jq -r '[.[].alias]|sort|join(",")')" "github,google"
check "idps use auto-link flow" "$(api "$REALM/identity-provider/instances" | jq -r '[.[].firstBrokerLoginFlowAlias]|unique|join(",")')" "first broker login auto-link"

echo
if [[ $FAILED -eq 0 ]]; then echo "All checks passed"; else echo "Some checks failed"; exit 1; fi
