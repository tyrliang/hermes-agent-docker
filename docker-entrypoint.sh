#!/bin/sh
set -eu

# Optional auto-start before CMD (see README):
# · HERMES_ENTRYPOINT_DASHBOARD — default 1: hermes dashboard in background
# · HERMES_ENTRYPOINT_GATEWAY   — default 1: always start default hermes gateway in background
# Override with 0|false|no|off (case insensitive).

_truthy() {
  v=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "$v" in 1 | true | yes | on) return 0 ;;
  *) return 1 ;;
  esac
}

HERMES_HOME=${HERMES_HOME:-/home/agent/.hermes}
DEFAULTS_DIR=/usr/local/share/hermes-home
SEED_MARKER="$HERMES_HOME/.docker-defaults-seeded"

# Entrypoint runs as root (see Dockerfile). Fix volume ownership, then continue as agent.
# Railway volumes are often root-owned after a misconfigured deploy (bare sleep as root).
if [ "$(id -u)" -eq 0 ] && [ -z "${HERMES_ENTRYPOINT_REEXEC:-}" ] && getent passwd agent >/dev/null 2>&1; then
  mkdir -p "$HERMES_HOME" "$HERMES_HOME/logs" 2>/dev/null || true
  chown -R agent:agent "$HERMES_HOME" 2>/dev/null || true
  export HERMES_ENTRYPOINT_REEXEC=1
  exec runuser -m -u agent -- env HERMES_ENTRYPOINT_REEXEC=1 /usr/local/bin/hermes-entrypoint "$@"
fi

mkdir -p "$HERMES_HOME"

# Gateway / rotating file handlers expect this path; bind mounts may omit it after manual cleanup.
mkdir -p "$HERMES_HOME/logs"

if [ ! -e "$SEED_MARKER" ] && [ -z "$(find "$HERMES_HOME" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  cp -a "$DEFAULTS_DIR"/. "$HERMES_HOME"/
  : > "$SEED_MARKER"
fi

# Hermes dashboard runs in background, gated behind a Caddy reverse proxy that
# enforces HTTP Basic Auth. The dashboard itself binds to 127.0.0.1 so it is
# only reachable through the proxy.
if _truthy "${HERMES_ENTRYPOINT_DASHBOARD:-1}"; then
  PUBLIC_HOST="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
  PUBLIC_PORT="${HERMES_DASHBOARD_PORT:-9119}"
  INTERNAL_PORT="${HERMES_DASHBOARD_INTERNAL_PORT:-9118}"
  AUTH_USER="${HERMES_DASHBOARD_AUTH_USER:-}"
  AUTH_PASS="${HERMES_DASHBOARD_AUTH_PASS:-}"

  if [ -z "$AUTH_USER" ] || [ -z "$AUTH_PASS" ]; then
    cat >&2 <<'EOF'
[hermes-entrypoint] FATAL: dashboard auth is not configured.

The dashboard exposes API keys, sessions, and gateway controls; running it on
a network-reachable port without auth is unsafe.

To start the dashboard, set BOTH of the following on the container:

  HERMES_DASHBOARD_AUTH_USER=<username>
  HERMES_DASHBOARD_AUTH_PASS=<password>

To skip the dashboard entirely (e.g. headless gateway-only deployments):

  HERMES_ENTRYPOINT_DASHBOARD=0
EOF
    exit 1
  fi

  RUN_DIR="$HERMES_HOME/.run"
  mkdir -p "$RUN_DIR"
  CADDYFILE="$RUN_DIR/Caddyfile"

  # Caddy's own Caddyfile env-substitution ({$VAR}) is used so the bcrypt
  # hash (which contains $2a$, $14$, etc.) is never re-interpreted by the shell.
  cat > "$CADDYFILE" <<'EOF'
{
    auto_https off
    admin off
    persist_config off
    log {
        output stderr
        format console
        level WARN
    }
}

:{$HERMES_DASHBOARD_PROXY_PORT} {
    bind {$HERMES_DASHBOARD_PROXY_HOST}
    basic_auth {
        {$HERMES_DASHBOARD_AUTH_USER} {$HERMES_DASHBOARD_AUTH_HASH}
    }
    reverse_proxy 127.0.0.1:{$HERMES_DASHBOARD_PROXY_UPSTREAM} {
        # Hermes validates Host against its bind (127.0.0.1) — not the public edge hostname.
        header_up Host 127.0.0.1:{$HERMES_DASHBOARD_PROXY_UPSTREAM}
        flush_interval -1
    }
}
EOF

  HERMES_DASHBOARD_AUTH_HASH=$(caddy hash-password --plaintext "$AUTH_PASS")
  export HERMES_DASHBOARD_PROXY_HOST="$PUBLIC_HOST"
  export HERMES_DASHBOARD_PROXY_PORT="$PUBLIC_PORT"
  export HERMES_DASHBOARD_PROXY_UPSTREAM="$INTERNAL_PORT"
  export HERMES_DASHBOARD_AUTH_USER
  export HERMES_DASHBOARD_AUTH_HASH

  echo "[hermes-entrypoint] starting dashboard on 127.0.0.1:${INTERNAL_PORT} (caddy basic-auth proxy on ${PUBLIC_HOST}:${PUBLIC_PORT}, user '${AUTH_USER}')"
  HERMES_NONINTERACTIVE="${HERMES_NONINTERACTIVE:-1}"
  export HERMES_NONINTERACTIVE
  hermes dashboard --host 127.0.0.1 --port "$INTERNAL_PORT" --no-open --skip-build --tui &
  caddy run --config "$CADDYFILE" --adapter caddyfile &
fi

# Default gateway: always unless disabled.
if _truthy "${HERMES_ENTRYPOINT_GATEWAY:-1}"; then
  echo '[hermes-entrypoint] starting default gateway (background)'
  HERMES_NONINTERACTIVE="${HERMES_NONINTERACTIVE:-1}"
  export HERMES_NONINTERACTIVE
  hermes gateway run --accept-hooks &
fi

exec "$@"
