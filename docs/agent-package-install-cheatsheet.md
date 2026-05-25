# Agent package install cheatsheet (hermes-agent-docker)

Paste this file (or the **Agent instructions** section below) into a Hermes session so the agent picks the right install command and persistence layer.

**Image:** v0.1.1+ recommended (needs **`agent-pip`** for Python).  
**Volume:** `/home/agent` — user installs must land under `$HOME`, not in the image or inside `~/.hermes` (except skill-specific venvs).

---

## Agent instructions (copy from here)

You run as user **`agent`** with **`HOME=/home/agent`** and **`HERMES_HOME=/home/agent/.hermes`**. The Railway/local volume is mounted at `/home/agent`.

### Persistence layers

| Layer | Path | Who installs |
|-------|------|----------------|
| Image (ephemeral on rebuild) | `/opt/hermes-agent`, `/usr/local/bin` | Dockerfile only — **do not modify** |
| User runtime (volume) | `~/.local`, `~/.bun`, `~/.npm`, `~/.cache` | **You** — use commands below |
| Hermes state (volume) | `~/.hermes` | Config, skills, DB — **not** for global pip/npm unless a skill venv |
| Projects | `~/workspace/` | Per-project `package.json`, venvs, etc. |

### Install commands (use these defaults)

| Ecosystem | Global / agent-wide (persists on volume) | Project-local (inside `~/workspace/<project>/`) |
|-----------|------------------------------------------|--------------------------------------------------|
| **Python** | `agent-pip install <pkg>` | `cd ~/workspace/<project> && python -m venv .venv && .venv/bin/pip install <pkg>` |
| **npm** | `npm install -g <pkg>` | `cd ~/workspace/<project> && npm install` |
| **Bun** | `bun install -g <pkg>` (**Bun is not pre-installed** — install first; see §3) | `cd ~/workspace/<project> && bun install` |
| **uv (Python CLI tools)** | `uv tool install <tool>` | `uv pip install --python .venv/bin/python <pkg>` in project dir |
| **Other CLIs** | `uv tool install <name>` if available; else document manual install in `~/.hermes/migration-reinstall.txt` | project README |

### Never use (wrong layer or broken on this image)

| Command | Why |
|---------|-----|
| `pip install <pkg>` (default `pip` in Hermes venv) | Installs into **image** venv — lost on rebuild |
| `pip install --user <pkg>` | Fails (venv disables user site) or PEP 668 on system Python |
| `/usr/bin/python3 -m pip install …` | PEP 668 externally-managed |
| `npm install <pkg>` without `-g` at `$HOME` | Installs under cwd, not a stable global prefix |
| Installing into `~/.hermes/bin`, `~/.hermes/lib`, `~/.hermes/site-packages` | Wrong layer — use `~/.local` or `agent-pip` |
| Editing `/opt/hermes-agent` or `/usr/local/bin` | Image-only |

### After installing anything global

1. Log the exact command in **`~/.hermes/migration-reinstall.txt`** (one line per package/tool).
2. Verify binary on PATH: `which <cmd>` → should be under `~/.local/bin` or `~/.bun/bin`.
3. For Python: `/opt/hermes-agent/venv/bin/python -c "import <module>"`.

### Environment (already set in image; do not override unless debugging)

```bash
HOME=/home/agent
HERMES_HOME=/home/agent/.hermes
NPM_CONFIG_PREFIX=/home/agent/.local
npm_config_cache=/home/agent/.npm
BUN_INSTALL=/home/agent/.bun
XDG_CACHE_HOME=/home/agent/.cache
XDG_DATA_HOME=/home/agent/.local/share
PATH=~/.local/bin:~/.bun/bin:/opt/hermes-agent/venv/bin:/usr/local/bin:...
```

---

## 1. Python

### Global libraries (Hermes, gateway, skills importing at runtime)

```bash
agent-pip install <package>
agent-pip install "hindsight-client>=0.4.22"
agent-pip list
agent-pip uninstall <package>   # if supported for --target installs
```

- **Lands on volume:** `~/.local/lib/pythonX.Y/site-packages` (X.Y = Hermes venv version)
- **Scripts:** `~/.local/bin` (console scripts from `--target` installs may be limited; prefer `python -m <module>` when needed)
- **Hermes visibility:** entrypoint writes `hermes-user-local.pth` under `/opt/hermes-agent/venv/lib/pythonX.Y/site-packages/` each boot (`.pth` bridge)

**`.pth` bridge ownership:** v0.1.2+ images `chown` the bridge file to `agent` when the entrypoint creates it, so `agent-pip install` does not need a manual `sudo chown`. On older builds, if `agent-pip` reports permission denied on `hermes-user-local.pth`, run once: `sudo chown agent:agent /opt/hermes-agent/venv/lib/python*/site-packages/hermes-user-local.pth`

**Verify:**

```bash
/opt/hermes-agent/venv/bin/python -c "import <module>; print('ok')"
ls ~/.local/lib/python*/site-packages | head
```

### Skill-specific or isolated Python env (volume)

```bash
uv venv ~/.hermes/venvs/<name>
uv pip install --python ~/.hermes/venvs/<name>/bin/python <package>
```

Document the venv path in `~/.hermes/migration-notes.txt` if a skill or cron job depends on it.

### Project-local Python

```bash
cd ~/workspace/<project>
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Use the project venv in scripts/cron `workdir` — do not expect Hermes to import these unless `PYTHONPATH` is set for that job only.

---

## 2. npm

### Global CLIs / packages (volume)

```bash
npm install -g <package>
npm install -g cowsay   # example
```

- **Prefix:** `NPM_CONFIG_PREFIX=~/.local` → binaries in **`~/.local/bin`**
- **Cache:** `~/.npm`

**Verify:**

```bash
which <cmd>    # e.g. ~/.local/bin/...
npm list -g --depth=0
```

### Project-local (workspace)

```bash
cd ~/workspace/<project>
npm install
npm ci
```

### Already baked in image (do not reinstall to volume)

`@openai/codex`, `@anthropic-ai/claude-code`, `opencode-ai` → `/usr/local/bin`

---

## 3. Bun

**Bun is not pre-installed** in the image. `BUN_INSTALL` defaults to **`~/.bun`** (on the volume) once you install Bun.

### Install Bun (one-time, if `bun` is not on PATH)

```bash
# One-time — pick upstream install method; then:
export BUN_INSTALL=/home/agent/.bun
export PATH="$BUN_INSTALL/bin:$PATH"
```

Record the install command in `~/.hermes/migration-reinstall.txt`.

### Global tools

```bash
bun install -g <package>
```

**Verify:** `which <cmd>` → `~/.bun/bin/...`

### Project-local

```bash
cd ~/workspace/<project>
bun install
```

---

## 4. uv (Python CLIs & tooling)

`uv` is available from the Hermes install. Use for **CLI tools** and **project venvs**, not for replacing `agent-pip` for Hermes-wide imports.

### Global CLI tools (typically `~/.local/bin`)

```bash
uv tool install <package>
uv tool list
```

### Project venv + packages

```bash
cd ~/workspace/<project>
uv venv
uv pip install -r requirements.txt
# or
uv pip install --python .venv/bin/python <package>
```

### Do not use for Hermes-wide libs

```bash
# BAD for persistence into Hermes runtime:
uv pip install --python /opt/hermes-agent/venv/bin/python <pkg>
```

That targets the **image** venv (ephemeral). Use **`agent-pip install`** instead.

---

## 5. Other runtimes and tools

| Tool | Global (volume) approach | Notes |
|------|--------------------------|-------|
| **Hermes CLI** | `hermes` on PATH | Image wrapper — do not reinstall into volume |
| **codex / claude / opencode** | `/usr/local/bin` | Baked at image build |
| **micro, caddy, ffmpeg** | `/usr/local/bin` | Image only |
| **Rust CLI** | `cargo install <crate>` if `cargo` exists; may need `~/.cargo/bin` on PATH | Ensure `~/.cargo` is on volume |
| **Go CLI** | `go install …@latest` with `GOBIN=~/.local/bin` or `GOPATH` under `$HOME` | Set env so artifacts stay on volume |
| **apt packages** | `apt-get` as **root** only | System layer — not persisted on Railway volume; prefer image rebuild |
| **Chrome / agent-browser** | `agent-browser install` if needed | State under `~/.hermes/.agent-browser` |

When unsure, add a line to **`~/.hermes/migration-reinstall.txt`** with the exact install command to re-run after deploy.

---

## Quick decision tree

```
Need a Python import from Hermes / gateway / default agent?
  → agent-pip install <pkg>

Need a Node CLI available everywhere?
  → npm install -g <pkg>

Prefer Bun for a global JS tool?
  → bun install -g <pkg>

Need deps only for one repo under ~/workspace?
  → cd project && npm install | bun install | uv venv + uv pip install

Need a Python CLI (ruff, ty, etc.) on PATH?
  → uv tool install <tool>

Need an isolated Python env for one skill?
  → uv venv ~/.hermes/venvs/<name> + uv pip install --python ...
```

---

## Related docs

- [v0.1.0 → v0.1.1 migration](./v0.1.0-to-v0.1.1-migration.md) — `agent-pip` introduction
- [Railway home volume (v0.0.x → v0.1.0)](./railway-home-volume-migration.md) — volume layout
- [Hermes migration prompt](./hermes-agent-migration-prompt.md) — full post-cutover cleanup
