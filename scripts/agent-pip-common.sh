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
  printf '%s\n' "$target" >"$pth"
  printf '[agent-pip] volume site-packages: %s\n' "$target" >&2
}
