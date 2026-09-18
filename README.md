# saashup/keycloak

Custom Keycloak image for Paashups, preconfigured with realms, clients and theme.

## What it does differently from `keycloak/keycloak:26.6`

- On every `start`, `entrypoint.sh` renders `realm-template.json` with the
  env vars below and drops it in `/opt/keycloak/data/import/`, then execs
  `kc.sh start --import-realm`. Keycloak's realm import is idempotent
  (existing realms are left alone), so this is safe to run on every restart.
- The realm import creates: the `paashup` realm, the `SaasHup-Admins` group,
  a seed user in that group, the `grafana` and `saashup` OIDC clients (with
  their secrets, redirect URIs and protocol mappers), and, if credentials are
  supplied, the `google`/`github` identity providers.
- A `paashup` login theme and a `paashup` admin console theme (both extend
  Keycloak's built-in `keycloak.v2`) are baked in. Logo, app name, accent
  color and login background are set per deployment from env vars — see
  [Branding](#branding).

## Environment variables

Baked in as defaults — override with `-e` only if you need something different:
`KC_DB`, `KC_HEALTH_ENABLED`, `KC_METRICS_ENABLED`, `KC_HTTP_RELATIVE_PATH`,
`KC_HTTP_ENABLED`, `KC_HTTP_MANAGEMENT_SCHEME`, `KC_PROXY_HEADERS`,
`KC_HOSTNAME_STRICT`, `KC_HOSTNAME_STRICT_BACKCHANNEL`, and
`KC_BOOTSTRAP_ADMIN_USERNAME` (defaults to `admin`).

**`KC_BOOTSTRAP_ADMIN_PASSWORD` has no default and must always be passed at
`docker run` time.** Without it, no master-realm admin user is created at
all, and Keycloak's own "create the first admin" flow only works when
accessed as `localhost` — which you can't do once you're behind Traefik on a
real domain, so you'd be locked out of the admin console. This is on purpose:
no image should ship with a hardcoded admin password.

Used to render the realm import (all optional, sensible defaults shown):

| Variable | Default |
| --- | --- |
| `BASE_DOMAIN` | *(empty)* |
| `KEYCLOAK_REALM` | `paashup` |
| `KEYCLOAK_ADMIN_GROUP` | `SaasHup-Admins` |
| `KEYCLOAK_SEED_USERNAME` | `saashup` |
| `KEYCLOAK_SEED_PASSWORD` | `saashup` |
| `KEYCLOAK_SEED_EMAIL` | `contact@saashup.com` |
| `GRAFANA_OIDC_CLIENT_ID` | `grafana` |
| `GRAFANA_OIDC_CLIENT_SECRET` | *(empty)* |
| `GRAFANA_OIDC_REDIRECT_URI` | `https://${BASE_DOMAIN}/dashboard/login/generic_oauth` |
| `SAASHUP_OIDC_CLIENT_ID` | `saashup` |
| `SAASHUP_OIDC_CLIENT_SECRET` | *(empty)* |
| `SAASHUP_OIDC_REDIRECT_PATH` | `/oidc/callback` |
| `SAASHUP_OIDC_REDIRECT_URI` | `https://${BASE_DOMAIN}${SAASHUP_OIDC_REDIRECT_PATH}` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | *(empty — IdP skipped if unset)* |
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | *(empty — IdP skipped if unset)* |
| `KEYCLOAK_APP_NAME` | `SaaShup` |
| `KEYCLOAK_LOGO_URL` | `../img/saashup-logo.svg` (baked-in SaaShup logo) |
| `THEME_PRIMARY_COLOR` | `#0d6efd` |
| `THEME_BACKGROUND_URL` | `../img/keycloak-bg-darken.svg` (Keycloak's own default) |

## Branding

`KEYCLOAK_APP_NAME` becomes the realm's `displayName`/`displayNameHtml`
(plain text — always present in the DOM for screen readers and as the
fallback when no logo is configured) and the admin console's browser tab
title.

- `THEME_PRIMARY_COLOR` overrides `--pf-v5-global--primary-color--100`
  (buttons/links) and `--keycloak-card-top-color` (login card's top accent
  border) — same CSS variables Keycloak's own theme exposes for this.
- `THEME_BACKGROUND_URL` overrides `--keycloak-bg-logo-url`, used by a
  `.login-pf body` selector that only exists on the **login page**. The
  admin console (a separate React app, `keycloak-admin-ui.jar`) has no such
  selector and never references this variable at all — no visual effect there.
- `KEYCLOAK_LOGO_URL` is applied as a `background-image` on
  `#kc-header-wrapper`, an id that only exists in the **login page**'s
  server-rendered HTML. 

This covers per-client cosmetics (logo, name, accent color, background)
without a rebuild or a separate image per client — same `paashup` themes
every time, just re-skinned from env vars on start. It also means the
**default look is already fully SaaShup-branded out of the box**: the real
SaaShup logo (`theme/paashup/login/resources/img/saashup-logo.svg`) and
background (`theme/paashup/login/resources/img/saashup-bg.svg`) are baked
into the image and used unless overridden.

## Local test

```bash
docker build -t keycloak:test .
docker run -d --name kc-test -p 18080:8080 \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=saashup \
  -e BASE_DOMAIN=localhost:18080 \
  -e GRAFANA_OIDC_CLIENT_SECRET=grafanasecret \
  -e SAASHUP_OIDC_CLIENT_SECRET=saashupsecret \
  keycloak:test
```
