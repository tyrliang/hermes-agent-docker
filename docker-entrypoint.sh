#!/bin/sh
set -eu

HERMES_HOME=${HERMES_HOME:-/home/agent/.hermes}
DEFAULTS_DIR=/usr/local/share/hermes-home
SEED_MARKER="$HERMES_HOME/.docker-defaults-seeded"

mkdir -p "$HERMES_HOME"

# Gateway / rotating file handlers expect this path; bind mounts may omit it after manual cleanup.
mkdir -p "$HERMES_HOME/logs"

# Hook lives at bootload/bootload.sh by default; extra helpers/snippets can live under bootload/.
mkdir -p "$HERMES_HOME/bootload"

if [ ! -e "$SEED_MARKER" ] && [ -z "$(find "$HERMES_HOME" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  cp -a "$DEFAULTS_DIR"/. "$HERMES_HOME"/
  : > "$SEED_MARKER"
fi

# Optional mount-local bootstrap (default: $HERMES_HOME/bootload/bootload.sh).
BOOTLOAD_SCRIPT=${HERMES_BOOTLOAD_SCRIPT:-"$HERMES_HOME/bootload/bootload.sh"}
if [ -x "$BOOTLOAD_SCRIPT" ]; then
  exec "$BOOTLOAD_SCRIPT" "$@"
fi

exec "$@"
