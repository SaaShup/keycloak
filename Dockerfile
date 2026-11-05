FROM keycloak/keycloak:26.7 AS builder

ENV KC_DB=dev-file
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_HTTP_RELATIVE_PATH=/auth

RUN /opt/keycloak/bin/kc.sh build

FROM keycloak/keycloak:26.7

COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY --chown=1000:0 --chmod=0755 entrypoint.sh /opt/keycloak/paashup/entrypoint.sh
COPY --chown=1000:0 realm-template.json /opt/keycloak/paashup/realm-template.json
COPY --chown=1000:0 brand-template.css /opt/keycloak/paashup/brand-template.css
COPY --chown=1000:0 admin-theme-template.properties /opt/keycloak/paashup/admin-theme-template.properties
COPY --chown=1000:0 login-theme-template.properties /opt/keycloak/paashup/login-theme-template.properties
COPY --chown=1000:0 theme/paashup /opt/keycloak/themes/paashup

RUN mkdir -p \
      /opt/keycloak/themes/paashup/login/resources/css \
      /opt/keycloak/themes/paashup/login/resources/img \
      /opt/keycloak/themes/paashup/admin/resources/css \
      /opt/keycloak/themes/paashup/admin/resources/img

ENV KC_DB=dev-file
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_HTTP_RELATIVE_PATH=/auth

ENV KC_HTTP_ENABLED=true
ENV KC_HTTP_MANAGEMENT_SCHEME=http
ENV KC_PROXY_HEADERS=xforwarded
ENV KC_HOSTNAME_STRICT=false
ENV KC_HOSTNAME_STRICT_BACKCHANNEL=false

ENV KC_BOOTSTRAP_ADMIN_USERNAME=admin

ENV THEME_BACKGROUND_URL=../img/saashup-bg.svg

LABEL traefik.enable="true" \
      traefik.docker.network="traefik" \
      traefik.http.routers.keycloak.entrypoints="http" \
      traefik.http.services.keycloak.loadbalancer.server.port="8080" \
      traefik.http.middlewares.force-https-header.headers.customrequestheaders.X-Forwarded-Proto="https" \
      traefik.http.routers.keycloak.middlewares="force-https-header" \
      traefik.http.middlewares.force-https-header.headers.customrequestheaders.X-Forwarded-Port="443" \
      prometheus_address="keycloak:8080" \
      prometheus_path="/admin/keycloak/realms/master/metrics" \
      prometheus_scrape="true"

ENTRYPOINT ["/opt/keycloak/paashup/entrypoint.sh"]
CMD ["start"]
