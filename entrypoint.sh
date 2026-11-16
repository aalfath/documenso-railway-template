#!/bin/sh
# Railway entrypoint for Documenso.
#  1. Creates a self-signed signing certificate on the volume on first boot.
#  2. Runs the database migrations (as upstream's start.sh does).
#  3. Creates the first admin account once, so a fresh deploy can log in
#     without SMTP (Documenso only lets verified emails sign in).
#  4. Starts the server as the unprivileged "nodejs" user.
set -e
cd /app/apps/remix

if [ "$(id -u)" = "0" ]; then
  CERT_DIR="$(dirname "${NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH:-/opt/documenso/cert.p12}")"
  mkdir -p "$CERT_DIR"
  chown -R nodejs "$CERT_DIR"
  export HOME=/tmp/documenso-home
  exec su -p -s /bin/sh nodejs -c 'mkdir -p "$HOME" && exec "$0"' "$0"
fi

# Derived defaults. Railway sets RAILWAY_PUBLIC_DOMAIN when a domain is attached.
if [ -z "$NEXT_PUBLIC_WEBAPP_URL" ] && [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
  export NEXT_PUBLIC_WEBAPP_URL="https://$RAILWAY_PUBLIC_DOMAIN"
fi
export PORT="${PORT:-3000}"
export NEXT_PRIVATE_INTERNAL_WEBAPP_URL="${NEXT_PRIVATE_INTERNAL_WEBAPP_URL:-http://localhost:$PORT}"
export NEXT_PRIVATE_DIRECT_DATABASE_URL="${NEXT_PRIVATE_DIRECT_DATABASE_URL:-$NEXT_PRIVATE_DATABASE_URL}"
export NEXT_PUBLIC_DISABLE_SIGNUP="${NEXT_PUBLIC_DISABLE_SIGNUP:-true}"

# 1. Signing certificate (self-signed, 10 years). Kept on the volume and reused.
CERT="${NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH:-/opt/documenso/cert.p12}"
if [ -z "$NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS" ] && [ ! -s "$CERT" ]; then
  host="${NEXT_PUBLIC_WEBAPP_URL#*://}"; host="${host%%/*}"
  echo "Creating a self-signed signing certificate for ${host:-Documenso} at $CERT"
  tmp="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=${host:-Documenso}/O=Documenso" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$CERT" -passout env:NEXT_PRIVATE_SIGNING_PASSPHRASE 2>/dev/null \
  || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$CERT" -passout env:NEXT_PRIVATE_SIGNING_PASSPHRASE
  chmod 600 "$CERT"
  rm -rf "$tmp"
fi

# 2. Migrations.
echo "Running database migrations"
npx prisma migrate deploy --schema ../../packages/prisma/schema.prisma

# 3. First admin, once. Skipped when DOCUMENSO_ADMIN_EMAIL is empty or the
#    account already exists. The account is signed up through Documenso's own
#    endpoint on a private side port (sign-up forced on for that process only),
#    then marked verified and given the ADMIN role.
if [ -n "$DOCUMENSO_ADMIN_EMAIL" ] && [ -n "$DOCUMENSO_ADMIN_PASSWORD" ]; then
  if node -e '
    const { PrismaClient } = require("@prisma/client");
    const p = new PrismaClient();
    p.user.findFirst({ where: { email: process.env.DOCUMENSO_ADMIN_EMAIL.trim().toLowerCase() } })
      .then((u) => p.$disconnect().then(() => process.exit(u ? 0 : 1)))
      .catch((e) => { console.error(e.message); process.exit(2); });
  '; then
    echo "Admin account already exists"
  else
    echo "Creating the admin account"
    BOOT_PORT=3999
    NEXT_PUBLIC_DISABLE_SIGNUP=false NEXT_PUBLIC_DISABLE_EMAIL_PASSWORD_SIGNUP=false \
      PORT=$BOOT_PORT NEXT_PRIVATE_INTERNAL_WEBAPP_URL="http://localhost:$BOOT_PORT" \
      HOSTNAME=127.0.0.1 node build/server/main.js >/tmp/bootstrap.log 2>&1 &
    pid=$!
    i=0
    until wget -q -O /dev/null "http://127.0.0.1:$BOOT_PORT/api/health"; do
      i=$((i + 1))
      if [ "$i" -gt 180 ] || ! kill -0 "$pid" 2>/dev/null; then
        echo "Bootstrap server did not start:"; tail -n 40 /tmp/bootstrap.log; exit 1
      fi
      sleep 1
    done
    BOOT_PORT=$BOOT_PORT node -e '
      const { PrismaClient } = require("@prisma/client");
      const email = process.env.DOCUMENSO_ADMIN_EMAIL.trim().toLowerCase();
      const origin = new URL(process.env.NEXT_PUBLIC_WEBAPP_URL || "http://localhost").origin;
      (async () => {
        const res = await fetch("http://127.0.0.1:" + process.env.BOOT_PORT + "/api/auth/email-password/signup", {
          method: "POST",
          headers: { "Content-Type": "application/json", Origin: origin },
          body: JSON.stringify({ name: "Admin", email, password: process.env.DOCUMENSO_ADMIN_PASSWORD }),
        });
        if (res.status < 200 || res.status > 299) throw new Error("signup returned " + res.status + ": " + (await res.text()).slice(0, 300));
        const p = new PrismaClient();
        await p.user.update({ where: { email }, data: { emailVerified: new Date(), roles: ["USER", "ADMIN"] } });
        await p.$disconnect();
      })().catch((e) => { console.error(e.message); process.exit(1); });
    ' || { kill "$pid" 2>/dev/null; tail -n 40 /tmp/bootstrap.log; exit 1; }
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "Admin account created for $DOCUMENSO_ADMIN_EMAIL"
  fi
fi

# 4. Server.
echo "Starting Documenso on port $PORT"
export HOSTNAME=0.0.0.0
exec node build/server/main.js
