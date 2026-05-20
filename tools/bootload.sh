#!/bin/bash
# Optional container boot hook: lives on the Hermes bind mount so it can change
# without rebuilding the image. Default path is $HERMES_HOME/bootload/bootload.sh —
# sibling files under bootload/ can hold extra snippets, env, or helpers.
#
# hermes-entrypoint execs this when it exists and is executable (see HERMES_BOOTLOAD_SCRIPT).
# Customize BACKGROUND_GATEWAY_PROFILES (array below), then extend for other boot logic.

set -eu

HH="${HERMES_HOME:-/home/agent/.hermes}"

# Hermes profiles to start as background gateways before the default (foreground).
# Omit names, or leave the array empty, to skip secondary gateways entirely.
readonly BACKGROUND_GATEWAY_PROFILES=(
  cfo
  life
)

trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

for profile in "${BACKGROUND_GATEWAY_PROFILES[@]}"; do
    [ -z "$profile" ] && continue
    if [ -d "$HH/profiles/$profile" ]; then
        echo "[bootload] Starting gateway for profile: $profile"
        hermes -p "$profile" gateway run &
        sleep 2
    fi
done

echo "[bootload] Starting default gateway (foreground)"
exec hermes gateway run
