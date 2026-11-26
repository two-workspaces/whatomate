#!/bin/bash
# Maps Railway onto Whatomate. Upstream reads every setting from WHATOMATE_* variables
# (a double underscore separates the config section: WHATOMATE_DATABASE__HOST), so the
# template sets those directly; this script only fills the gaps that would otherwise
# stop the server or leave it unsafe:
# - listens on $PORT; uploads and IVR audio live on the /data volume;
# - production mode, with the allowed origins built from the public URL and the Railway
#   domain (production refuses to start without them, and WebSockets check them);
# - an empty JWT secret, encryption key, webhook token or admin password is generated once
#   and kept on the volume, so nothing falls back to upstream's samples (admin / admin);
# - login rate limits per visitor: Railway's edge puts the visitor first in
#   X-Forwarded-For and drops a spoofed value, which is what upstream reads;
# - waits for Postgres and Redis, which start alongside it;
# - if the server exits within 60 s of starting (a bad variable), a notice page is served
#   instead of a crash loop. Later exits pass through so Railway restarts it.
set -u
log() { echo "[railway] $*"; }

DATA=/data
mkdir -p "$DATA/uploads" "$DATA/audio"

PORT="${PORT:-8080}"
case "$PORT" in '' | *[!0-9]*) log "PORT=$PORT is not a number, using 8080"; PORT=8080 ;; esac
export WHATOMATE_SERVER__PORT="$PORT" WHATOMATE_SERVER__HOST=0.0.0.0

: "${WHATOMATE_APP__ENVIRONMENT:=production}"
: "${WHATOMATE_APP__DEBUG:=false}"
: "${WHATOMATE_STORAGE__LOCAL_PATH:=$DATA/uploads}"
: "${WHATOMATE_CALLING__AUDIO_DIR:=$DATA/audio}"
: "${WHATOMATE_RATE_LIMIT__ENABLED:=true}"
: "${WHATOMATE_RATE_LIMIT__TRUST_PROXY:=true}"
export WHATOMATE_APP__ENVIRONMENT WHATOMATE_APP__DEBUG WHATOMATE_STORAGE__LOCAL_PATH \
  WHATOMATE_CALLING__AUDIO_DIR WHATOMATE_RATE_LIMIT__ENABLED WHATOMATE_RATE_LIMIT__TRUST_PROXY

# Public URL: upstream refuses anything but a bare http(s) origin, so drop a bad one.
url="${WHATOMATE_SERVER__PUBLIC_URL:-}"
url="${url%/}"
case "$url" in
  '') ;;
  http://*/* | https://*/*) log "WHATOMATE_SERVER__PUBLIC_URL must be just https://host, without a path; ignoring it"; url="" ;;
  http://* | https://*) ;;
  *) log "WHATOMATE_SERVER__PUBLIC_URL must start with https://; ignoring it"; url="" ;;
esac
if [ -z "$url" ] && [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then url="https://$RAILWAY_PUBLIC_DOMAIN"; fi
export WHATOMATE_SERVER__PUBLIC_URL="$url"

# Allowed origins: what you set, plus the public URL and the Railway domain.
origins="${WHATOMATE_SERVER__ALLOWED_ORIGINS:-}"
for o in "$url" "${RAILWAY_PUBLIC_DOMAIN:+https://$RAILWAY_PUBLIC_DOMAIN}"; do
  [ -z "$o" ] && continue
  case ",$origins," in *",$o,"*) ;; *) origins="${origins:+$origins,}$o" ;; esac
done
if [ -z "$origins" ]; then
  origins="http://localhost:$PORT"
  log "no public domain yet: add one under Settings > Networking (port $PORT) and redeploy"
fi
export WHATOMATE_SERVER__ALLOWED_ORIGINS="$origins"

# Secrets kept on the volume when a variable is empty. The encryption key protects the
# WhatsApp access tokens stored in the database: once set, it must never change.
kept() { # name file minlen
  local name=$1 file="$DATA/$2" min=$3 val="${!1:-}"
  if [ ${#val} -ge "$min" ]; then return; fi
  [ -n "$val" ] && log "$name is shorter than $min characters; using a generated one instead"
  if [ ! -s "$file" ]; then
    (umask 077; head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40 > "$file")
    log "$name was empty: generated one and saved it at $file"
  fi
  export "$name=$(cat "$file")"
}
kept WHATOMATE_JWT__SECRET .jwt-secret 32
kept WHATOMATE_APP__ENCRYPTION_KEY .encryption-key 1
kept WHATOMATE_WHATSAPP__WEBHOOK_VERIFY_TOKEN .webhook-verify-token 1

: "${WHATOMATE_DEFAULT_ADMIN__EMAIL:=admin@example.com}"
export WHATOMATE_DEFAULT_ADMIN__EMAIL
if [ -z "${WHATOMATE_DEFAULT_ADMIN__PASSWORD:-}" ] || [ "${WHATOMATE_DEFAULT_ADMIN__PASSWORD}" = admin ]; then
  unset WHATOMATE_DEFAULT_ADMIN__PASSWORD
  kept WHATOMATE_DEFAULT_ADMIN__PASSWORD .admin-password 12
  log "admin login: $WHATOMATE_DEFAULT_ADMIN__EMAIL with the password in $DATA/.admin-password"
fi

# Wait for Postgres and Redis (bash /dev/tcp resolves IPv6 private-network names).
wait_for() { # label host port
  local host=$2 port=$3 i
  [ -z "$host" ] && { log "$1 host is empty; check the template's $1 variables"; return; }
  for i in $(seq 1 90); do
    if timeout 2 bash -c ">/dev/tcp/$host/$port" 2>/dev/null; then return; fi
    [ "$i" = 1 ] && log "waiting for $1 at $host:$port"
    sleep 2
  done
  log "$1 at $host:$port is still not reachable after 3 minutes; starting anyway"
}
wait_for Postgres "${WHATOMATE_DATABASE__HOST:-}" "${WHATOMATE_DATABASE__PORT:-5432}"
wait_for Redis "${WHATOMATE_REDIS__HOST:-}" "${WHATOMATE_REDIS__PORT:-6379}"

# Railway counts the kernel's cache of files read or written as the service's memory and
# never frees it without memory pressure; drop it for the volume every 15 minutes.
( while sleep 900; do nice -n 19 sh /usr/local/bin/drop-file-cache.sh "$DATA" /tmp; done ) &
trimmer=$!

notice() {
  kill "$trimmer" 2>/dev/null
  dir=/tmp/notice
  mkdir -p "$dir"
  echo ok > "$dir/health"
  cat > "$dir/index.html" <<EOF
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Whatomate is not running</title>
<body style="font:16px/1.5 system-ui,sans-serif;max-width:40em;margin:4em auto;padding:0 1em">
<h1>Whatomate is not running</h1>
<p>The server stopped right after starting ($1). Open this service's <b>Deploy Logs</b> on Railway:
the lines above "[railway] showing a notice page" say what to fix, usually a variable or the
Postgres or Redis service. Fix it, then redeploy. Your data is untouched.</p>
</body>
EOF
  log "showing a notice page on port $PORT until the problem is fixed"
  exec busybox httpd -f -p "0.0.0.0:$PORT" -h "$dir"
}

# The image's config.toml is upstream's sample (a published JWT secret, debug on), so start
# from an empty file and take everything from variables. /data/config.toml, if you create
# one, is read instead; variables still override it.
conf=/tmp/whatomate.toml
: > "$conf"
if [ -s "$DATA/config.toml" ]; then conf="$DATA/config.toml"; log "reading $conf (variables still override it)"; fi

started=$(date +%s)
./whatomate server -config "$conf" -migrate &
pid=$!
stopping=
trap 'stopping=1; kill -TERM "$pid" 2>/dev/null' TERM INT
wait "$pid"; rc=$?
# wait returns early when the trap fires; wait again for the real exit status.
while kill -0 "$pid" 2>/dev/null; do wait "$pid"; rc=$?; done
[ -n "$stopping" ] && { kill "$trimmer" 2>/dev/null; exit "$rc"; }
if [ $(( $(date +%s) - started )) -lt 60 ]; then
  notice "exit code $rc"
fi
kill "$trimmer" 2>/dev/null
exit "$rc"
