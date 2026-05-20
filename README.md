# hermes-agent-docker

Docker packaging for [Hermes Agent](https://github.com/NousResearch/hermes-agent), tuned for everyday **interactive dev** (comfortable shell, small editors, common agent CLIs) and **hands-off runs** via a writable Hermes home and an optional **`bootload/bootload.sh`** hook you keep on the host.

## Image contents

- **Hermes CLI** installed with the upstream `install.sh` (see `HERMES_REF` below). Contents beyond this image follow whatever that release ships—skills, bridges, bundled tooling included.
- **Base:** [`docker/sandbox-templates:shell`](https://hub.docker.com/r/docker/sandbox-templates) Debian-based environment.
- **Shell UX:** **Zsh** as login shell with **Oh My Zsh**, **autosuggestions**, and **syntax highlighting** (`docker exec -it … zsh`).
- **Editors / utilities:** `micro`, `nano`, `ffmpeg`, `zip` (+ build-time **micro** version pin via `MICRO_VERSION`).
- **Globally installed CLIs:** `@openai/codex`, `@anthropic-ai/claude-code`, and `opencode-ai` (`NPM_CONFIG_PREFIX=/home/agent/.local`; on `PATH`).
- **Maintenance:** conservative `npm audit fix` passes on `hermes-agent` and `whatsapp-bridge` during build.
- **Persistence:** declares a volume at `/home/agent/.hermes`; see below for **entrypoint seeding**, **`logs/`**, and **`bootload/`** (default hook path **`bootload/bootload.sh`**).

## Entrypoint behaviour (`hermes-entrypoint`)

The image **ENTRYPOINT** always runs **`/usr/local/bin/hermes-entrypoint`** before your **CMD**:

1. Ensures **`$HERMES_HOME`** (default `/home/agent/.hermes`), **`$HERMES_HOME/logs`**, and **`$HERMES_HOME/bootload`** exist (Hermes expects **`logs/`**; **`bootload/`** is reserved for the hook plus any extra payloads you version next to **`bootload.sh`**).
2. **First boot:** if the mount is empty and **`$HERMES_HOME/.docker-defaults-seeded`** is absent, seeds the tree from **`/usr/local/share/hermes-home`** (Hermes defaults captured at image build time), then touches the marker.
3. **`bootload` hook:** Resolves **`${HERMES_BOOTLOAD_SCRIPT:-$HERMES_HOME/bootload/bootload.sh}`**. If that path **exists and is executable**, **`exec`**s it with the same arguments as **CMD**. Otherwise **`exec`**s **CMD** as usual—so gateways, **`sleep infinity`**, **`hermes`**, etc. stay under your Compose or **`docker run`** control.

Anything you want **without rebuilding the image** (multi-gateway startup, env tweaks, wrappers, sourced helpers under **`bootload/`**) lives on the **`$HERMES_HOME`** bind mount—default entry is **`bootload/bootload.sh`**.

### Bootload layout (`bootload/`)

Install the template **`tools/bootload.sh`** as **`$HERMES_HOME/bootload/bootload.sh`** (plus anything else under **`bootload/`** — fragments, **`source`** helpers, staged env files):

```bash
mkdir -p ./tmp/.hermes/bootload
install -m 0755 ./tools/bootload.sh ./tmp/.hermes/bootload/bootload.sh
# edit ./tmp/.hermes/bootload/bootload.sh (and sibling files under bootload/) as needed
```

Disable autoload by omitting **`bootload.sh`** or **`chmod -x ./tmp/.hermes/bootload/bootload.sh`** (with **`HERMES_BOOTLOAD_SCRIPT`**, point at nothing executable to fall through to plain **CMD**).

## Build arguments

| Build arg       | Default   | Meaning |
|-----------------|-----------|---------|
| `HERMES_REF`    | `main`    | Hermes Agent git branch or tag passed to **`install.sh`**. |
| `CODEX_VERSION` | `0.118.0` | **`@openai/codex@…`** semver. |
| `MICRO_VERSION` | `2.0.14`  | **`micro`** editor release. |

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

GitHub Actions (**.github/workflows/docker.yml**) builds **linux/amd64** and **linux/arm64** and pushes to **GHCR** when:

- **`main`** is pushed (**`latest`**, **`main`**, **`sha-<short>`**), or
- a **git tag** matching **`v*`** is pushed (the registry gets an image tagged **exactly that string**, e.g. **`…:v0.6.2`**),

PRs build without push (no GHCR publish). Manual **workflow_dispatch** runs can override **`HERMES_REF`**.

### Cutting a release (version tag → same GHCR tag)

[`docker/metadata-action`](https://github.com/docker/metadata-action) maps **`type=ref,event=tag`**, so the **Docker tag** mirrors the **git tag**:

1. Commit what you want on **`main`** (or the branch that will receive the tag).
2. Create and push a **[SemVer-style](https://semver.org/)** annotated tag prefixed with **`v`**:

   ```bash
   scripts/tag-release.sh 1.2.3          # prints "Next: git push origin v1.2.3"
   git push origin v1.2.3
   ```

   Or by hand:

   ```bash
   git tag -a v1.2.3 -m "release v1.2.3"
   git push origin v1.2.3
   ```

   Creating a **GitHub Release** with the same **`v*`** tag triggers the same **push tag** workflow.

3. Pull **`ghcr.io/<owner>/<repo>:v1.2.3`** after the job finishes.

**Tip:** Bump **`Dockerfile`** pins (`HERMES_REF`, **`CODEX_VERSION`**, **`MICRO_VERSION`**) before tagging when you intend that release line to freeze those bumps for consumers.

## Related layout

Compose stacks that attach **Mission Control** and share **`./tmp/.hermes`** with this image are documented in companion repos (same bind mount semantics and **`bootload/`** hook semantics apply).

