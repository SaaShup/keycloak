#!/usr/bin/env bash
set -euo pipefail

TEMPLATE="/opt/keycloak/paashup/realm-template.json"
IMPORT_DIR="/opt/keycloak/data/import"

: "${BASE_DOMAIN:=}"
: "${KEYCLOAK_REALM:=paashup}"
: "${KEYCLOAK_ADMIN_GROUP:=SaasHup-Admins}"
: "${KEYCLOAK_SEED_USERNAME:=saashup}"
: "${KEYCLOAK_SEED_PASSWORD:=saashup}"
: "${KEYCLOAK_SEED_EMAIL:=contact@saashup.com}"
: "${GRAFANA_OIDC_CLIENT_ID:=grafana}"
: "${GRAFANA_OIDC_CLIENT_SECRET:=}"
: "${GRAFANA_OIDC_REDIRECT_URI:=https://${BASE_DOMAIN}/dashboard/login/generic_oauth}"
: "${SAASHUP_OIDC_CLIENT_ID:=saashup}"
: "${SAASHUP_OIDC_CLIENT_SECRET:=}"
: "${SAASHUP_OIDC_REDIRECT_PATH:=/oidc/callback}"
: "${SAASHUP_OIDC_REDIRECT_URI:=https://${BASE_DOMAIN}${SAASHUP_OIDC_REDIRECT_PATH}}"
: "${WEB_ORIGIN:=https://${BASE_DOMAIN}}"

: "${KEYCLOAK_APP_NAME:=SaaShup}"
: "${KEYCLOAK_LOGO_URL:=../img/saashup-logo.svg}"
: "${THEME_PRIMARY_COLOR:=#0d6efd}"
: "${THEME_BACKGROUND_URL:=../img/keycloak-bg-darken.svg}"
: "${THEME_LOGO_WIDTH:=220px}"
: "${THEME_LOGO_HEIGHT:=80px}"

mime_type_for() {
  case "$1" in
    *.svg) printf 'image/svg+xml' ;;
    *.png) printf 'image/png' ;;
    *.jpg|*.jpeg) printf 'image/jpeg' ;;
    *.gif) printf 'image/gif' ;;
    *.webp) printf 'image/webp' ;;
    *) printf 'application/octet-stream' ;;
  esac
}

resolve_image_ref() {
  local ref="$1"
  case "$ref" in
    ""|http://*|https://*|data:*) printf '%s' "$ref" ;;
    *)
      if [[ -f "$ref" ]]; then
        printf 'data:%s;base64,%s' "$(mime_type_for "$ref")" "$(base64 -w0 "$ref")"
      else
        printf '%s' "$ref"
      fi
      ;;
  esac
}

KEYCLOAK_LOGO_URL="$(resolve_image_ref "$KEYCLOAK_LOGO_URL")"
THEME_BACKGROUND_URL="$(resolve_image_ref "$THEME_BACKGROUND_URL")"

DISPLAY_NAME_HTML="${KEYCLOAK_APP_NAME}"

if [[ -n "$KEYCLOAK_LOGO_URL" ]]; then
  LOGO_CSS_RULE="#kc-header-wrapper.pf-v5-c-brand { background: url('${KEYCLOAK_LOGO_URL}') no-repeat center / contain; width: ${THEME_LOGO_WIDTH}; height: ${THEME_LOGO_HEIGHT}; margin: 0 auto; font-size: 0; color: transparent; }"
else
  LOGO_CSS_RULE=""
fi

sed_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//|/\\|}"
  s="${s//&/\\&}"
  printf '%s' "$s"
}

identity_provider_json() {
  local alias="$1" provider_id="$2" client_id="$3" client_secret="$4"
  printf '{"alias":"%s","providerId":"%s","enabled":true,"trustEmail":true,"config":{"clientId":"%s","clientSecret":"%s","useJwksUrl":"true"}}' \
    "$alias" "$provider_id" "$client_id" "$client_secret"
}

providers=()
if [[ -n "${GOOGLE_CLIENT_ID:-}" && -n "${GOOGLE_CLIENT_SECRET:-}" ]]; then
  providers+=("$(identity_provider_json google google "$GOOGLE_CLIENT_ID" "$GOOGLE_CLIENT_SECRET")")
fi
if [[ -n "${GITHUB_CLIENT_ID:-}" && -n "${GITHUB_CLIENT_SECRET:-}" ]]; then
  providers+=("$(identity_provider_json github github "$GITHUB_CLIENT_ID" "$GITHUB_CLIENT_SECRET")")
fi

IDENTITY_PROVIDERS_JSON="[]"
if [[ ${#providers[@]} -gt 0 ]]; then
  IDENTITY_PROVIDERS_JSON="[$(IFS=,; echo "${providers[*]}")]"
fi

mkdir -p "$IMPORT_DIR"
REALM_FILE="${IMPORT_DIR}/${KEYCLOAK_REALM}-realm.json"

sed \
  -e "s|\${KEYCLOAK_REALM}|$(sed_escape "$KEYCLOAK_REALM")|g" \
  -e "s|\${KEYCLOAK_ADMIN_GROUP}|$(sed_escape "$KEYCLOAK_ADMIN_GROUP")|g" \
  -e "s|\${KEYCLOAK_SEED_USERNAME}|$(sed_escape "$KEYCLOAK_SEED_USERNAME")|g" \
  -e "s|\${KEYCLOAK_SEED_PASSWORD}|$(sed_escape "$KEYCLOAK_SEED_PASSWORD")|g" \
  -e "s|\${KEYCLOAK_SEED_EMAIL}|$(sed_escape "$KEYCLOAK_SEED_EMAIL")|g" \
  -e "s|\${GRAFANA_OIDC_CLIENT_ID}|$(sed_escape "$GRAFANA_OIDC_CLIENT_ID")|g" \
  -e "s|\${GRAFANA_OIDC_CLIENT_SECRET}|$(sed_escape "$GRAFANA_OIDC_CLIENT_SECRET")|g" \
  -e "s|\${GRAFANA_OIDC_REDIRECT_URI}|$(sed_escape "$GRAFANA_OIDC_REDIRECT_URI")|g" \
  -e "s|\${SAASHUP_OIDC_CLIENT_ID}|$(sed_escape "$SAASHUP_OIDC_CLIENT_ID")|g" \
  -e "s|\${SAASHUP_OIDC_CLIENT_SECRET}|$(sed_escape "$SAASHUP_OIDC_CLIENT_SECRET")|g" \
  -e "s|\${SAASHUP_OIDC_REDIRECT_URI}|$(sed_escape "$SAASHUP_OIDC_REDIRECT_URI")|g" \
  -e "s|\${WEB_ORIGIN}|$(sed_escape "$WEB_ORIGIN")|g" \
  -e "s|\${IDENTITY_PROVIDERS_JSON}|$(sed_escape "$IDENTITY_PROVIDERS_JSON")|g" \
  -e "s|\${KEYCLOAK_APP_NAME}|$(sed_escape "$KEYCLOAK_APP_NAME")|g" \
  -e "s|\${DISPLAY_NAME_HTML}|$(sed_escape "$DISPLAY_NAME_HTML")|g" \
  "$TEMPLATE" > "$REALM_FILE"

BRAND_CSS="/opt/keycloak/paashup/brand.css"
sed \
  -e "s|\${THEME_PRIMARY_COLOR}|$(sed_escape "$THEME_PRIMARY_COLOR")|g" \
  -e "s|\${THEME_BACKGROUND_URL}|$(sed_escape "$THEME_BACKGROUND_URL")|g" \
  -e "s|\${LOGO_CSS_RULE}|$(sed_escape "$LOGO_CSS_RULE")|g" \
  /opt/keycloak/paashup/brand-template.css > "$BRAND_CSS"

mkdir -p /opt/keycloak/themes/paashup/login/resources/css
cp "$BRAND_CSS" /opt/keycloak/themes/paashup/login/resources/css/brand.css

mkdir -p /opt/keycloak/themes/paashup/admin/resources/css
cp "$BRAND_CSS" /opt/keycloak/themes/paashup/admin/resources/css/brand.css
sed \
  -e "s|\${KEYCLOAK_APP_NAME}|$(sed_escape "$KEYCLOAK_APP_NAME")|g" \
  -e "s|\${WEB_ORIGIN}|$(sed_escape "$WEB_ORIGIN")|g" \
  /opt/keycloak/paashup/admin-theme-template.properties > /opt/keycloak/themes/paashup/admin/theme.properties

exec /opt/keycloak/bin/kc.sh "$@" --import-realm
