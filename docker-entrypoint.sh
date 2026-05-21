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

mkdir -p "$HERMES_HOME"

# Gateway / rotating file handlers expect this path; bind mounts may omit it after manual cleanup.
mkdir -p "$HERMES_HOME/logs"

if [ ! -e "$SEED_MARKER" ] && [ -z "$(find "$HERMES_HOME" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  cp -a "$DEFAULTS_DIR"/. "$HERMES_HOME"/
  : > "$SEED_MARKER"
fi

# Hermes dashboard runs in background; bind address defaults to non-localhost for container access -- publish port in Compose.
if _truthy "${HERMES_ENTRYPOINT_DASHBOARD:-1}"; then
  HOST="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
  PORT="${HERMES_DASHBOARD_PORT:-9119}"
  echo "[hermes-entrypoint] starting dashboard on ${HOST}:${PORT}"
  HERMES_NONINTERACTIVE="${HERMES_NONINTERACTIVE:-1}"
  export HERMES_NONINTERACTIVE
  hermes dashboard --host "$HOST" --port "$PORT" --no-open --insecure --skip-build &
fi

# Default gateway: always unless disabled.
if _truthy "${HERMES_ENTRYPOINT_GATEWAY:-1}"; then
  echo '[hermes-entrypoint] starting default gateway (background)'
  HERMES_NONINTERACTIVE="${HERMES_NONINTERACTIVE:-1}"
  export HERMES_NONINTERACTIVE
  hermes gateway run --accept-hooks &
fi

exec "$@"
