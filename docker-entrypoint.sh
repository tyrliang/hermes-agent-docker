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

AGENT_HOME=/home/agent
HERMES_HOME=${HERMES_HOME:-/home/agent/.hermes}
# shellcheck source=agent-pip-common.sh
. /usr/local/lib/hermes-agent/agent-pip-common.sh 2>/dev/null || true
DEFAULTS_DIR=/usr/local/share/hermes-home
HOME_SEED_DIR=/usr/local/share/agent-home-seed
SEED_MARKER="$HERMES_HOME/.docker-defaults-seeded"
HOME_SEED_MARKER="$AGENT_HOME/.docker-home-seeded"

_agent_path() {
  printf '%s' "${AGENT_HOME}/.local/bin:${AGENT_HOME}/.bun/bin:/opt/hermes-agent/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

_agent_env_exports() {
  printf '%s\n' \
    "HOME=${AGENT_HOME}" \
    "HERMES_HOME=${HERMES_HOME}" \
    "NPM_CONFIG_PREFIX=${NPM_CONFIG_PREFIX:-${AGENT_HOME}/.local}" \
    "npm_config_cache=${npm_config_cache:-${AGENT_HOME}/.npm}" \
    "BUN_INSTALL=${BUN_INSTALL:-${AGENT_HOME}/.bun}" \
    "XDG_CACHE_HOME=${XDG_CACHE_HOME:-${AGENT_HOME}/.cache}" \
    "XDG_DATA_HOME=${XDG_DATA_HOME:-${AGENT_HOME}/.local/share}" \
    "PATH=$(_agent_path)"
}

# Old Railway mount put Hermes state at the volume root; v0.1.0+ mounts the volume at /home/agent.
_flat_volume_pending_migration() {
  if [ -f "$HERMES_HOME/config.yaml" ] || [ -f "$HERMES_HOME/.env" ] || [ -f "$HERMES_HOME/state.db" ]; then
    return 1
  fi
  if [ -f "$AGENT_HOME/config.yaml" ] || [ -f "$AGENT_HOME/.env" ] || [ -f "$AGENT_HOME/state.db" ]; then
    return 0
  fi
  return 1
}

# Entrypoint runs as root (see Dockerfile). Fix volume ownership, then continue as agent.
# Railway volumes are often root-owned after a misconfigured deploy (bare sleep as root).
if [ "$(id -u)" -eq 0 ] && [ -z "${HERMES_ENTRYPOINT_REEXEC:-}" ] && getent passwd agent >/dev/null 2>&1; then
  mkdir -p "$AGENT_HOME/.hermes/logs" "$AGENT_HOME/.local/bin" "$AGENT_HOME/workspace" 2>/dev/null || true
  if command -v agent_pip_ensure_bridge >/dev/null 2>&1; then
    agent_pip_ensure_bridge "$AGENT_HOME" || true
  fi
  chown -R agent:agent "$AGENT_HOME" 2>/dev/null || true

  export HERMES_ENTRYPOINT_REEXEC=1
  # shellcheck disable=SC2046
  exec runuser -m -u agent -- env \
    HERMES_ENTRYPOINT_REEXEC=1 \
    $(_agent_env_exports) \
    /usr/local/bin/hermes-entrypoint "$@"
fi

mkdir -p "$HERMES_HOME"

# Gateway / rotating file handlers expect this path; bind mounts may omit it after manual cleanup.
mkdir -p "$HERMES_HOME/logs"

if command -v agent_pip_ensure_bridge >/dev/null 2>&1; then
  agent_pip_ensure_bridge "$AGENT_HOME" || true
fi

if _flat_volume_pending_migration; then
  cat >&2 <<'EOF'
[hermes-entrypoint] Legacy flat volume detected (Hermes state at /home/agent/ root).

Gateway and dashboard are paused until you restructure the volume. From Railway SSH:

  migrate-volume-to-home.sh /home/agent
  # or: bash /usr/local/bin/migrate-volume-to-home.sh /home/agent

Then restart the service. See docs/railway-home-volume-migration.md

EOF
else
  if [ ! -e "$SEED_MARKER" ] && [ -z "$(find "$HERMES_HOME" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
    cp -a "$DEFAULTS_DIR"/. "$HERMES_HOME"/
    : > "$SEED_MARKER"
  fi
fi

# First boot on a fresh /home/agent volume: seed zsh skeleton from image (not on volume).
if [ ! -e "$HOME_SEED_MARKER" ] && [ ! -e "$AGENT_HOME/.zshrc" ] && [ -d "$HOME_SEED_DIR" ]; then
  cp -a "$HOME_SEED_DIR"/. "$AGENT_HOME"/
  : > "$HOME_SEED_MARKER"
fi

# Hermes dashboard runs in background, gated behind a Caddy reverse proxy that
# enforces HTTP Basic Auth. The dashboard itself binds to 127.0.0.1 so it is
# only reachable through the proxy.
if _flat_volume_pending_migration; then
  : # wait for migrate-volume-to-home.sh before starting Hermes services
elif _truthy "${HERMES_ENTRYPOINT_DASHBOARD:-1}"; then
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
if _flat_volume_pending_migration; then
  :
elif _truthy "${HERMES_ENTRYPOINT_GATEWAY:-1}"; then
  echo '[hermes-entrypoint] starting default gateway (background)'
  HERMES_NONINTERACTIVE="${HERMES_NONINTERACTIVE:-1}"
  export HERMES_NONINTERACTIVE
  hermes gateway run --accept-hooks &
fi

exec "$@"
