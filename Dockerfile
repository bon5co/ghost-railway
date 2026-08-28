# Railway wrapper for Ghost 6.60.0 (open-source publishing platform).
# Pins the image, bundles nginx + mailpit, and adds a boot-time Owner seed so a
# fresh deploy is never anonymously claimable. See railway-entrypoint.sh.
FROM ghost:6.60.0-alpine

# nginx: public gateway + /inbox mailpit UI + /healthz (Ghost front-end 301s any
# request without X-Forwarded-Proto: https, so the healthcheck cannot dial Ghost
# directly). apache2-utils: htpasswd for the /inbox basic-auth realm.
# gettext: envsubst renders the nginx template with the injected $PORT.
USER root
RUN apk add --no-cache nginx apache2-utils gettext ca-certificates \
 && mkdir -p /run/nginx

# mailpit: loopback SMTP sink so staff invites, password resets and member magic
# links work out of the box with no external SMTP account (served at /inbox).
ARG MAILPIT_VERSION=1.31.0
RUN wget -qO /tmp/mailpit.tar.gz \
      "https://github.com/axllent/mailpit/releases/download/v${MAILPIT_VERSION}/mailpit-linux-amd64.tar.gz" \
 && tar -xzf /tmp/mailpit.tar.gz -C /usr/local/bin mailpit \
 && rm /tmp/mailpit.tar.gz \
 && chmod +x /usr/local/bin/mailpit

# Railway helpers, kept out of the content volume so a mount cannot hide them.
RUN mkdir -p /var/lib/ghost/railway
COPY seed-owner.cjs reset-owner.cjs /var/lib/ghost/railway/
COPY nginx.conf.template /var/lib/ghost/railway/nginx.conf.template
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# Root so nginx can bind the injected $PORT and the entrypoint can chown the
# uid-0 volume mount; Ghost itself is launched under gosu node.
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
