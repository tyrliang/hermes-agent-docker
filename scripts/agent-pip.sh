#!/usr/bin/env bash
# Install Python packages onto the /home/agent volume (same persistence model as npm -g).
# Usage: agent-pip install <package>   |   agent-pip list   |   agent-pip uninstall <pkg>
set -euo pipefail

HOME="${HOME:-/home/agent}"
# shellcheck source=agent-pip-common.sh
. /usr/local/lib/hermes-agent/agent-pip-common.sh

if [ ! -x "$HERMES_PY" ] || [ ! -x "$HERMES_PIP" ]; then
  printf 'agent-pip: Hermes venv not found under /opt/hermes-agent\n' >&2
  exit 1
fi

if [ "${1:-}" = "pip" ]; then
  shift
fi

TARGET=$(agent_pip_target "$HOME")
SCRIPTS=$(agent_pip_scripts "$HOME")
mkdir -p "$TARGET" "$SCRIPTS"
agent_pip_ensure_bridge "$HOME" >/dev/null

case "${1:-}" in
  install | download | wheel)
    printf 'agent-pip: target %s\n' "$TARGET" >&2
    ;;
esac

exec "$HERMES_PIP" \
  --target="$TARGET" \
  --install-scripts="$SCRIPTS" \
  "$@"
