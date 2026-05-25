# hermes-agent-docker

Docker packaging for [Hermes Agent](https://github.com/NousResearch/hermes-agent), tuned for everyday **interactive dev** (comfortable shell, small editors, common agent CLIs) and **hands-off runs** via a writable agent home volume for persistence across container restarts.

## Image layout (v0.1.0+)

**Upgrading v0.1.0 → v0.1.1:** see [docs/v0.1.0-to-v0.1.1-migration.md](docs/v0.1.0-to-v0.1.1-migration.md) (`agent-pip` for persistent Python libs).

Three persistence layers:

| Layer | Contents | Location |
|-------|----------|----------|
| **1 – Baked (image)** | Hermes app, STT venv, codex/claude/opencode, zsh template, micro/caddy/ffmpeg | `/opt/hermes-agent`, `/usr/local` |
| **2 – Runtime user (volume)** | `.local`, `.bun`, `.npm`, `.cache`, `.config`, git creds | `/home/agent/*` |
| **3 – Hermes state (volume)** | `.env`, `config.yaml`, `state.db`, profiles, skills, logs | `$HERMES_HOME` = `/home/agent/.hermes` |

Immutable software lives **outside** `/home/agent` so a fresh Railway volume does not hide the Hermes app.

## Image contents

- **Hermes CLI** installed with upstream `install.sh` into **`/opt/hermes-agent`** (see `HERMES_REF`). Wrapper at **`/usr/local/bin/hermes`**.
- **Base:** [`docker/sandbox-templates:shell`](https://hub.docker.com/r/docker/sandbox-templates) Debian-based environment.
- **Shell UX:** **Zsh** with **Oh My Zsh**, **autosuggestions**, and **syntax highlighting** — seeded on first boot from `/usr/local/share/agent-home-seed`.
- **Editors / utilities:** `micro`, `nano`, `ffmpeg`, `zip` (+ **`MICRO_VERSION`** pin).
- **Globally installed CLIs:** `@openai/codex`, `@anthropic-ai/claude-code`, and `opencode-ai` (system **`/usr/local/bin`**).
- **Maintenance:** conservative `npm audit fix` on `hermes-agent` and `whatsapp-bridge` during build.
- **Persistence:** volume at **`/home/agent`**; Hermes state under **`$HERMES_HOME`**. See **entrypoint seeding** below.

### Where to install packages

| Purpose | Location |
|---------|----------|
| Hermes config, sessions, cron, skills | `$HERMES_HOME` (`~/.hermes`) |
| User Python libs (`agent-pip install`) | `~/.local/lib/pythonX.Y/site-packages` (+ `~/.local/bin` scripts) |
| User CLIs (`npm install -g`) | `~/.local` |
| Bun | `~/.bun` |
| Baked Hermes / CLIs | `/opt/hermes-agent`, `/usr/local/bin` (image only) |

**Cheatsheet for agents:** [docs/agent-package-install-cheatsheet.md](docs/agent-package-install-cheatsheet.md) — which command to use for Python, npm, Bun, uv, etc.

## Entrypoint behaviour (`hermes-entrypoint`)

The image **ENTRYPOINT** always runs **`/usr/local/bin/hermes-entrypoint`** before your **CMD**:

1. Ensures **`/home/agent`** layout (`$HERMES_HOME`, `$HERMES_HOME/logs`, `~/.local/bin`, `workspace`) and **`chown`s** the full home mount.
2. **First boot `.hermes`:** if empty and **`$HERMES_HOME/.docker-defaults-seeded`** absent, seeds from **`/usr/local/share/hermes-home`**.
3. **First boot home skeleton:** if no **`~/.zshrc`**, seeds from **`/usr/local/share/agent-home-seed`**.
4. **Legacy flat volume (v0.0.x → v0.1.0):** if Hermes state is still at `/home/agent/` root after remounting the volume, skips seeding and auto-start until you run **`migrate-volume-to-home.sh /home/agent`** (nests flat state under `.hermes/` and moves **`~/.hermes/workspace` → `~/workspace`**) — see [migration guide](docs/railway-home-volume-migration.md).
5. **Auto-start (defaults on):**
   - **`hermes dashboard`** in background on **`127.0.0.1`**, fronted by **Caddy** basic-auth on **`0.0.0.0:9119`**.
   - **`hermes gateway run --accept-hooks`** in background unless **`HERMES_ENTRYPOINT_GATEWAY=off`**.
6. **`exec` CMD:** default **`sleep infinity`**.

### Railway (Docker image deploy)

Use **`v0.1.1+`** (or **`v0.1.0+`**) for home-volume persistence.

1. **Image:** `ghcr.io/<owner>/hermes-agent-docker:v0.1.0` (or newer).
2. **Start command:** leave **empty** (use Dockerfile **`ENTRYPOINT`** + **`CMD`**).
3. **Networking:** public domain **target port `9119`** (Caddy proxy).
4. **Variables:** **`HERMES_DASHBOARD_AUTH_USER`** and **`HERMES_DASHBOARD_AUTH_PASS`** (required for dashboard).
5. **Volume:** mount at **`/home/agent`** (`RAILWAY_VOLUME_MOUNT_PATH=/home/agent`).

**Upgrading from v0.0.x:** deploy **v0.1.0+**, remount the same volume at **`/home/agent`**, then run **`migrate-volume-to-home.sh /home/agent`** via Railway SSH and restart. See [docs/railway-home-volume-migration.md](docs/railway-home-volume-migration.md).

**Upgrading from v0.1.0:** deploy **v0.1.1+**, then reinstall extra Python packages with **`agent-pip install`**. See [docs/v0.1.0-to-v0.1.1-migration.md](docs/v0.1.0-to-v0.1.1-migration.md).

### Railway SSH

Railway opens a **root** shell. Prefer **`su - agent`** (login shell → **`/etc/profile.d/hermes-agent.sh`**) or **`/usr/local/bin/hermes`** directly.

## Build arguments

| Build arg       | Default   | Meaning |
|-----------------|-----------|---------|
| `HERMES_REF`    | `main`    | Hermes Agent git branch or tag passed to **`install.sh`**. |
| `CODEX_VERSION` | `0.118.0` | **`@openai/codex@…`** semver. |
| `MICRO_VERSION` | `2.0.14`  | **`micro`** editor release. |
| `CADDY_VERSION` | `2.11.3`  | **`caddy`** release bundled as the dashboard auth proxy. |

## Quick start

### Build locally

```bash
docker build -t hermes-agent-docker:local .
```

### Run (persisted agent home)

```bash
mkdir -p ./tmp/agent-home
docker run --rm -it \
  -v "./tmp/agent-home:/home/agent" \
  hermes-agent-docker:local \
  zsh
```

```bash
docker run --rm \
  -v "./tmp/agent-home:/home/agent" \
  hermes-agent-docker:local \
  hermes doctor
```

**Migrating local data from v0.0.x:** `mv ./tmp/.hermes ./tmp/agent-home/.hermes`

## Persistence and configuration

- **`HERMES_HOME`** defaults to **`/home/agent/.hermes`** (inside the volume).
- Mount **`/home/agent`** so runtime installs under **`~/.local`**, **`~/.bun`**, etc. survive redeploys.
- **Python extras:** `agent-pip install <package>` (not bare `pip install` — see v0.1.1 migration guide).
- Run **`hermes setup`** once on a fresh volume (or restore from backup).

## Publishing (this fork)

GitHub Actions builds **linux/amd64** and **linux/arm64**, pushes to **GHCR** on push to **`main`** or **workflow_dispatch**.

Each publish gets **`ghcr.io/<owner>/<repo>:vX.Y.Z`** from the repo-root **`VERSION`** file.

### Bumping what consumers pull (`VERSION`)

```bash
scripts/set-version.sh 0.1.0
git add VERSION && git commit -m "chore: release v0.1.0"
git push origin main
```

**Breaking change in v0.1.0:** volume mount path changed from `/home/agent/.hermes` to `/home/agent`. See [docs/railway-home-volume-migration.md](docs/railway-home-volume-migration.md).

## Related layout

Compose stacks in **hermes-stack** mount **`./tmp/agent-home:/home/agent`**. Mission Control integration shares **`$HERMES_HOME`** on that volume.
