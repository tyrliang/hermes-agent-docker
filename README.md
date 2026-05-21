# hermes-agent-docker

Docker packaging for [Hermes Agent](https://github.com/NousResearch/hermes-agent), tuned for everyday **interactive dev** (comfortable shell, small editors, common agent CLIs) and **hands-off runs** via a writable Hermes bind mount (`$HERMES_HOME`) for persistence and configuration across container restarts.

## Image contents

- **Hermes CLI** installed with the upstream `install.sh` (see `HERMES_REF` below). Contents beyond this image follow whatever that release ships—skills, bridges, bundled tooling included.
- **Base:** [`docker/sandbox-templates:shell`](https://hub.docker.com/r/docker/sandbox-templates) Debian-based environment.
- **Shell UX:** **Zsh** as login shell with **Oh My Zsh**, **autosuggestions**, and **syntax highlighting** (`docker exec -it … zsh`).
- **Editors / utilities:** `micro`, `nano`, `ffmpeg`, `zip` (+ build-time **micro** version pin via `MICRO_VERSION`).
- **Globally installed CLIs:** `@openai/codex`, `@anthropic-ai/claude-code`, and `opencode-ai` (`NPM_CONFIG_PREFIX=/home/agent/.local`; on `PATH`).
- **Maintenance:** conservative `npm audit fix` passes on `hermes-agent` and `whatsapp-bridge` during build.
- **Persistence:** declares a volume at `/home/agent/.hermes`; see below for **entrypoint seeding** and **`logs/`**.

## Entrypoint behaviour (`hermes-entrypoint`)

The image **ENTRYPOINT** always runs **`/usr/local/bin/hermes-entrypoint`** before your **CMD**:

1. Ensures **`$HERMES_HOME`** (default **`/home/agent/.hermes`**) and **`$HERMES_HOME/logs`** exist (Hermes expects **`logs/`** for gateway rotating logs).
2. **First boot:** if the mount is empty and **`$HERMES_HOME/.docker-defaults-seeded`** is absent, seeds the tree from **`/usr/local/share/hermes-home`** (Hermes defaults captured at image build time), then touches the marker.
3. **Auto-start (defaults on):**
   - **`hermes dashboard`** runs in the **background**, bound to **`127.0.0.1`** and fronted by a bundled **Caddy** reverse proxy that enforces **HTTP Basic Auth**. The proxy listens on **`HERMES_DASHBOARD_HOST`** (default **`0.0.0.0`**) **:`HERMES_DASHBOARD_PORT`** (default **`9119`**); publish **`9119`** on the container to reach the UI from the host. The dashboard refuses to start unless **both** **`HERMES_DASHBOARD_AUTH_USER`** and **`HERMES_DASHBOARD_AUTH_PASS`** are set (the password is bcrypt-hashed at startup — Caddy never sees the plaintext beyond the hash). Internal upstream port is **`HERMES_DASHBOARD_INTERNAL_PORT`** (default **`9118`**, rarely needs changing).
   - **`hermes gateway run --accept-hooks`** (**default profile**) runs in the **background**. Disable with **`HERMES_ENTRYPOINT_GATEWAY=off`**.
   - Toggle dashboard with **`HERMES_ENTRYPOINT_DASHBOARD`** using the same truthy/off values as **`HERMES_ENTRYPOINT_GATEWAY`** (**`0`**, **`false`**, **`no`**, **`off`** — case insensitive; unset defaults **on**). Set it to **`0`** for headless gateway-only deployments where you don't want to configure dashboard auth.
4. **`exec` CMD:** runs your **CMD** after auto-start (default **`sleep infinity`** in the image).

### Railway (Docker image deploy)

Use **`v0.0.7+`** (image includes **`CMD ["sleep","infinity"]`**; entrypoint runs as **root**, **`chown`s** the volume, then drops to **`agent`**).

1. **Image:** `ghcr.io/<owner>/hermes-agent-docker:v0.0.6` (or newer).
2. **Start command:** leave **empty** in Railway (use Dockerfile **`ENTRYPOINT`** + **`CMD`**). Do **not** set bare **`sleep infinity`** (skips entrypoint → no dashboard) or **`/usr/local/bin/hermes-entrypoint sleep infinity`** alone on older images (root + volume → crash).
3. **Networking:** public domain **target port `9119`** (Caddy proxy). Ignore Railway’s injected **`PORT`** for routing.
4. **Variables:** **`HERMES_DASHBOARD_AUTH_USER`** and **`HERMES_DASHBOARD_AUTH_PASS`** (required for dashboard).
5. **Volume:** mount at **`/home/agent/.hermes`** (same path as Compose).

**Beyond the defaults:** Extra Hermes gateways (other profiles), one-off **`hermes`** commands, **`screen`**/**`tmux`** sessions, or custom wrappers are up to your **CMD** (Compose **`command:`**), **`docker compose exec`** from the host, or shell sessions — not a separate **`bootload.sh`** hook. Keep anything you store under **`$HERMES_HOME`** on the bind mount so it survives container recreation (**`.env`**, **`profiles/`**, **`logs/`**, etc.).

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

Pinned Hermes ref:

```bash
docker build \
  --build-arg HERMES_REF=v2026.5.7 \
  -t hermes-agent-docker:v2026.5.7 .
```

### Run (workspace + persisted Hermes home)

```bash
docker run --rm -it \
  -v "./tmp/workspace:/home/agent/workspace" \
  -v "./tmp/.hermes:/home/agent/.hermes" \
  hermes-agent-docker:local \
  hermes
```

### Interactive shell / doctor

```bash
docker run --rm -it \
  -v "./tmp/workspace:/home/agent/workspace" \
  -v "./tmp/.hermes:/home/agent/.hermes" \
  hermes-agent-docker:local \
  zsh
```

```bash
docker run --rm \
  -v "./tmp/.hermes:/home/agent/.hermes" \
  hermes-agent-docker:local \
  hermes doctor
```

## Persistence and configuration

Hermes expects state under **`$HERMES_HOME`** (default **`/home/agent/.hermes`**). Mount it to survive container recreation.

Without a mount, state lives only in the container filesystem and is lost when the container is removed.

Run **`hermes setup`** inside the container once you have the mount (or populate that directory from a backup).

## Publishing (this fork)

GitHub Actions (**.github/workflows/docker.yml**) builds **linux/amd64** and **linux/arm64** in **parallel on native runners** (no QEMU for arm64), merges a multi-arch manifest, and pushes to **GHCR** on every push to **`main`** or **workflow_dispatch**. Pull requests build **amd64 only** (no GHCR publish).

**CI cache:** per-arch **GitHub Actions cache** (`scope=linux-amd64` / `linux-arm64`) plus **GHCR `buildcache-*` tags** so layers survive across runs. Pin **`HERMES_REF`** to a tag (not `main`) when you want stable cache keys and reproducible images — see workflow `workflow_dispatch` or set the default in **`.github/workflows/docker.yml`**.

Each publish gets:

- **`ghcr.io/<owner>/<repo>:latest`** plus branch / SHA tags from [`docker/metadata-action`](https://github.com/docker/metadata-action), and  
- **`ghcr.io/<owner>/<repo>:vX.Y.Z`** where **`vX.Y.Z`** is **`v`** plus the semver in the repo-root **`VERSION`** file (first non-empty, non-comment line; optional leading **`v`** in the file is accepted).

Manual **workflow_dispatch** can override **`HERMES_REF`** (Hermes upstream ref for **`Dockerfile`**) independently of **`VERSION`**.

### Bumping what consumers pull (`VERSION`)

Treat **`VERSION`** as the semver line you mean for pinning images (immutable only if each release bumps it — see below).

```bash
# optional helper (writes VERSION; commit + push yourself)
scripts/set-version.sh 0.0.5
git add VERSION && git commit -m "chore: release v0.0.5"
git push origin main
```

After CI: **`docker pull ghcr.io/<owner>/<repo>:v0.0.5`**.

Because **`VERSION` is a moving tag**, each push rebuilds **`vX.Y.Z`**. Bump **`VERSION`** whenever you intend a distinct release artifact; **`sha-<short>`** remains the deterministic digest choice for lockfiles.

**Tip:** Bump **`Dockerfile`** pins (`HERMES_REF`, **`CODEX_VERSION`**, **`MICRO_VERSION`**) alongside **`VERSION`** when you want that release line to encode specific upstream / tool versions.

## Related layout

Compose stacks that attach **Mission Control** and share **`./tmp/.hermes`** with this image are documented in companion repos (same bind mount semantics apply).

