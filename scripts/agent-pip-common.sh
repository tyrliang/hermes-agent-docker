# POSIX helpers for volume-persisted Python packages (sourced by entrypoint / agent-pip).
# Installs land under $HOME/.local/lib/pythonX.Y/site-packages; a .pth in the Hermes venv
# adds that path on every interpreter start (hermes CLI unsets PYTHONPATH).

HERMES_PY=${HERMES_PY:-/opt/hermes-agent/venv/bin/python}
HERMES_PIP=${HERMES_PIP:-/opt/hermes-agent/venv/bin/pip}
AGENT_PIP_PTH_NAME=hermes-user-local.pth

agent_pip_python_version() {
  if [ ! -x "$HERMES_PY" ]; then
    return 1
  fi
  "$HERMES_PY" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'
}

agent_pip_target() {
  home=${1:-/home/agent}
  ver=$(agent_pip_python_version) || return 1
  printf '%s/.local/lib/python%s/site-packages' "$home" "$ver"
}

agent_pip_scripts() {
  home=${1:-/home/agent}
  printf '%s/.local/bin' "$home"
}

# Link volume site-packages into the Hermes venv (rewritten each container start).
agent_pip_ensure_bridge() {
  home=${1:-/home/agent}
  if [ ! -x "$HERMES_PY" ]; then
    printf '[agent-pip] WARN: Hermes venv missing at %s — skip .pth bridge\n' "$HERMES_PY" >&2
    return 0
  fi
  target=$(agent_pip_target "$home") || return 1
  scripts=$(agent_pip_scripts "$home")
  mkdir -p "$target" "$scripts"
  venv_site=$("$HERMES_PY" -c 'import site; print(site.getsitepackages()[0])') || return 1
  pth="${venv_site}/${AGENT_PIP_PTH_NAME}"

  # Entrypoint may create this as root; agent-pip must be able to refresh it.
  if [ -f "$pth" ] && [ ! -w "$pth" ]; then
    current=$(tr -d '\n' <"$pth" 2>/dev/null || true)
    if [ "$current" = "$target" ]; then
      printf '[agent-pip] volume site-packages: %s\n' "$target" >&2
      return 0
    fi
    printf '[agent-pip] WARN: %s not writable (stale bridge); redeploy v0.1.2+ image or: sudo chown agent:agent %s\n' "$pth" "$pth" >&2
    return 1
  fi

  printf '%s\n' "$target" >"$pth"
  if [ "$(id -u)" -eq 0 ] && getent passwd agent >/dev/null 2>&1; then
    chown agent:agent "$pth" 2>/dev/null || true
  fi
  printf '[agent-pip] volume site-packages: %s\n' "$target" >&2
}
