#!/usr/bin/env bash
# End-to-end test: keycloak + grafana + saashup behind traefik, driven by
# Playwright (run in its official image, same docker network, so no browser
# needs to be installed locally).
# Usage: tests/e2e/run.sh            (builds ./Dockerfile as saashup-keycloak:test)
#        KEYCLOAK_IMAGE=ghcr.io/saashup/keycloak:v1.0.0 SAASHUP_IMAGE=... tests/e2e/run.sh
set -euo pipefail

cd "$(dirname "$0")"
export KEYCLOAK_IMAGE="${KEYCLOAK_IMAGE:-saashup-keycloak:test}"
export E2E_PORT="${E2E_PORT:-18088}"
PLAYWRIGHT_IMAGE="mcr.microsoft.com/playwright:v1.55.0-noble"

[[ -z "${SKIP_BUILD:-}" && "$KEYCLOAK_IMAGE" == "saashup-keycloak:test" ]] && docker build -t "$KEYCLOAK_IMAGE" ../..

cleanup() { docker compose down -v >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup # always start from a clean state (grafana keeps keycloak user ids)

docker compose up -d
for url in /auth/realms/paashup /dashboard/api/health; do
  for _ in $(seq 1 90); do
    curl -fs "http://localhost:$E2E_PORT$url" >/dev/null 2>&1 && continue 2
    sleep 2
  done
  docker compose logs --tail=50
  echo "timeout waiting for $url" >&2; exit 1
done

docker run --rm --network kc-e2e_default --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD":/work -w /work "$PLAYWRIGHT_IMAGE" \
  sh -c 'npm install --no-audit --no-fund --silent && npx playwright test'
