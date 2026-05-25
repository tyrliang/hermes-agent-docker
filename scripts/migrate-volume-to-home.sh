#!/usr/bin/env bash
# Restructure a Railway/Hermes volume from flat layout (Hermes state at volume root)
# to nested layout (Hermes state under .hermes/) for /home/agent mount cutover.
# Also moves shared project files from $HERMES_HOME/workspace to /home/agent/workspace
# (Docker WORKDIR), matching v0.1.0+ layout.
#
# Usage:
#   DRY_RUN=1 bash scripts/migrate-volume-to-home.sh /mnt
#   bash scripts/migrate-volume-to-home.sh /mnt
#
# /mnt is the volume root (e.g. mount at /home/agent in a debug container, or /mnt in alpine).
set -euo pipefail

ROOT=${1:-/mnt}
DRY_RUN=${DRY_RUN:-0}
AGENT_UID=${AGENT_UID:-1000}
AGENT_GID=${AGENT_GID:-1000}

log() { printf '[migrate-volume] %s\n' "$*"; }
run() {
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN: $*"
  else
    log "RUN: $*"
    "$@"
  fi
}

_hermes_nested() {
  local hermes_dir=$1
  [ -f "$hermes_dir/config.yaml" ] || [ -f "$hermes_dir/.env" ] || [ -f "$hermes_dir/state.db" ]
}

_flat_layout() {
  local root=$1
  for f in config.yaml .env state.db .docker-defaults-seeded; do
    if [ -e "$root/$f" ]; then
      return 0
    fi
  done
  return 1
}

# Move $HERMES_HOME/workspace → $ROOT/workspace (image WORKDIR / cron workdir).
_relocate_hermes_workspace() {
  local root=$1
  local hermes_dir=$2
  local src="$hermes_dir/workspace"
  local dest="$root/workspace"

  if [ ! -d "$src" ]; then
    log "No $src — workspace relocation skipped"
    return 0
  fi

  if [ -z "$(find "$src" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
    log "Removing empty $src"
    run rm -rf "$src"
    return 0
  fi

  if [ -d "$dest" ] && [ -n "$(find "$dest" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
    log "Merging $src/ into existing $dest/"
    if command -v rsync >/dev/null 2>&1; then
      run rsync -a "$src/" "$dest/"
    else
      run cp -a "$src/." "$dest/"
    fi
    run rm -rf "$src"
    return 0
  fi

  log "Moving $src -> $dest (shared workspace for Docker WORKDIR)"
  run mkdir -p "$root"
  if [ -e "$dest" ]; then
    run rm -rf "$dest"
  fi
  run mv "$src" "$dest"
}

if [ ! -d "$ROOT" ]; then
  log "ERROR: directory does not exist: $ROOT" >&2
  exit 1
fi

HERMES_DIR="$ROOT/.hermes"

if _hermes_nested "$HERMES_DIR"; then
  log "Hermes state already nested under $HERMES_DIR"
elif _flat_layout "$ROOT"; then
  log "Flat layout detected — moving top-level entries into $HERMES_DIR"
  run mkdir -p "$HERMES_DIR"
  while IFS= read -r -d '' entry; do
    base=$(basename "$entry")
    [ "$base" = ".hermes" ] && continue
    run mv "$entry" "$HERMES_DIR/"
  done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -print0)
else
  log "ERROR: unknown volume layout under $ROOT (no Hermes markers at root or under .hermes/)" >&2
  exit 1
fi

_relocate_hermes_workspace "$ROOT" "$HERMES_DIR"

run mkdir -p "$ROOT/.local/bin" "$ROOT/workspace"

if [ "$DRY_RUN" != "1" ]; then
  chown -R "$AGENT_UID:$AGENT_GID" "$ROOT" 2>/dev/null || log "WARN: chown failed (run as root?)"
fi

log "Migration OK. Volume root should contain .hermes/, .local/, workspace/"
log "  Shared projects (second-brain, etc.) belong in workspace/, not under .hermes/workspace/"
log "Next: restart the Railway service (or redeploy) so the entrypoint starts gateway/dashboard."

if [ "$DRY_RUN" != "1" ]; then
  ls -la "$ROOT" | head -20
  ls -la "$HERMES_DIR" | head -20
  if [ -d "$ROOT/workspace" ]; then
    ls -la "$ROOT/workspace" | head -10
  fi
fi
