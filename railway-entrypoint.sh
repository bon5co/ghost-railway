#!/bin/bash
# Railway entrypoint for Ghost 6.60.0.
#  - repairs the uid-0 volume mount (Railway mounts volumes owned by root)
#  - seeds the Ghost Owner over loopback BEFORE nginx opens the public $PORT,
#    so a fresh deploy is never anonymously claimable (the AzuraCast rule)
#  - re-applies the Owner credential every boot, so a redeploy is a working reset
#  - fronts Ghost with nginx, and bundles mailpit so e-mail flows work with no
#    external SMTP account
set -e

GHOST_INSTALL="${GHOST_INSTALL:-/var/lib/ghost}"
GHOST_CONTENT="${GHOST_CONTENT:-$GHOST_INSTALL/content}"
export GHOST_INSTALL GHOST_CONTENT

# ---------------------------------------------------------------- guardrails
if [ -z "${GHOST_ADMIN_PASSWORD:-}" ]; then
  echo "[entrypoint] FATAL: GHOST_ADMIN_PASSWORD is empty. Refusing to boot so the" >&2
  echo "[entrypoint]        instance is never left anonymously claimable." >&2
  exit 1
fi
export GHOST_ADMIN_EMAIL="${GHOST_ADMIN_EMAIL:-admin@example.com}"

# ---------------------------------------------------------------- public url
# Ghost builds every link and the canonical redirect from `url`; derive it from
# the injected public domain so it is correct with no manual variable.
if [ -z "${url:-}" ] && [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export url="https://${RAILWAY_PUBLIC_DOMAIN}"
fi

# ---------------------------------------------------------------- ghost binds loopback
# nginx is the only thing on $PORT; Ghost listens on 127.0.0.1:2368.
export server__host="127.0.0.1"
export server__port="2368"

# ---------------------------------------------------------------- mail
# Default to the bundled mailpit sink unless the deployer supplies real SMTP.
if [ -n "${SMTP_HOST:-}" ]; then
  export mail__transport="SMTP"
  export mail__options__host="$SMTP_HOST"
  export mail__options__port="${SMTP_PORT:-587}"
  [ -n "${SMTP_USER:-}" ] && export mail__options__auth__user="$SMTP_USER"
  [ -n "${SMTP_PASS:-}" ] && export mail__options__auth__pass="$SMTP_PASS"
else
  export mail__transport="SMTP"
  export mail__options__host="127.0.0.1"
  export mail__options__port="1025"
  export mail__options__secure="false"
fi
export mail__from="${mail__from:-Ghost <noreply@${RAILWAY_PUBLIC_DOMAIN:-localhost}>}"

# ---------------------------------------------------------------- volume repair
# Railway mounts the volume owned by uid 0; Ghost runs as node. Mirror upstream's
# own fixup (only touch files not already owned by node).
find "$GHOST_CONTENT" \! -user node -exec chown node '{}' + 2>/dev/null || true

# Restore the content skeleton (themes, default files) the way the stock
# entrypoint does — a volume mount otherwise hides what the image shipped there.
baseDir="$GHOST_INSTALL/content.orig"
if [ -d "$baseDir" ]; then
  for src in "$baseDir"/*/ "$baseDir"/themes/*; do
    src="${src%/}"; [ -e "$src" ] || continue
    target="$GHOST_CONTENT/${src#$baseDir/}"
    mkdir -p "$(dirname "$target")"
    if [ ! -e "$target" ]; then
      tar -cC "$(dirname "$src")" "$(basename "$src")" | tar -xC "$(dirname "$target")"
    fi
  done
  chown -R node "$GHOST_CONTENT" 2>/dev/null || true
fi

# ---------------------------------------------------------------- mailpit
mailpit --smtp 127.0.0.1:1025 --listen 127.0.0.1:8025 \
        --db-file "$GHOST_CONTENT/data/mailpit.db" >/tmp/mailpit.log 2>&1 &
MAILPIT_PID=$!

# ---------------------------------------------------------------- ghost (loopback)
gosu node node "$GHOST_INSTALL/current/index.js" &
GHOST_PID=$!

# ---------------------------------------------------------------- seed + rotate owner
# Both run against the loopback listener before nginx opens $PORT.
SEED_PORT="$server__port" GHOST_ADMIN_EMAIL="$GHOST_ADMIN_EMAIL" GHOST_ADMIN_PASSWORD="$GHOST_ADMIN_PASSWORD" \
  node "$GHOST_INSTALL/railway/seed-owner.cjs" || echo "[entrypoint] seed step returned non-zero (see above)" >&2
GHOST_INSTALL="$GHOST_INSTALL" GHOST_VERSION="$GHOST_VERSION" \
  node "$GHOST_INSTALL/railway/reset-owner.cjs" || true

# ---------------------------------------------------------------- nginx (public $PORT)
export PORT="${PORT:-8080}"
: "${GHOST_INBOX_USER:=admin}"
htpasswd -bc /var/lib/ghost/railway/inbox.htpasswd "$GHOST_INBOX_USER" "$GHOST_ADMIN_PASSWORD" >/dev/null 2>&1
envsubst '${PORT}' < /var/lib/ghost/railway/nginx.conf.template > /etc/nginx/nginx.conf
nginx -g 'daemon off;' &
NGINX_PID=$!

echo "[entrypoint] up: ghost(pid $GHOST_PID) nginx(pid $NGINX_PID) mailpit(pid $MAILPIT_PID) on \$PORT=$PORT" >&2

# If Ghost or nginx exits, bring the container down so Railway restarts it.
wait -n "$GHOST_PID" "$NGINX_PID"
echo "[entrypoint] a supervised process exited; shutting down" >&2
kill "$GHOST_PID" "$NGINX_PID" "$MAILPIT_PID" 2>/dev/null || true
exit 1
