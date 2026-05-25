# Railway home volume migration (v0.1.0+)

This guide covers migrating from **hermes-agent-docker v0.0.x** (volume mounted at `/home/agent/.hermes`) to **v0.1.0+** (volume mounted at `/home/agent`).

## Why migrate

| Layout | Mount path | What persists |
|--------|------------|---------------|
| **Old (v0.0.x)** | `/home/agent/.hermes` | Hermes state only (`config.yaml`, `state.db`, profiles, …) |
| **New (v0.1.0+)** | `/home/agent` | Hermes state **and** runtime user installs (`~/.local`, `~/.bun`, `~/.npm`, …) |

The new image keeps immutable software in the image (`/opt/hermes-agent`, `/usr/local/bin`) so an empty volume does not hide the Hermes app. Mutable data lives under the single Railway volume.

`HERMES_HOME` remains **`/home/agent/.hermes`**.

## Target layout

After migration, the volume root (`/home/agent` in the container) should look like:

```
/home/agent/                 ← Railway volume root
├── .hermes/                 ← HERMES_HOME (layer 3)
│   ├── config.yaml
│   ├── .env
│   ├── state.db
│   ├── profiles/
│   └── ...
├── .local/                  ← pip/npm user installs (layer 2)
├── .bun/ .npm/ .cache/ .config/
└── workspace/               ← shared project files (second-brain, daily-ai-briefing; Docker WORKDIR)
```

**Not** under `.hermes/workspace/` — older deploys kept the wiki inside `$HERMES_HOME`; the migration script moves that tree to `/home/agent/workspace/`.

## Pre-flight checklist

- [ ] Note current image tag and `HERMES_REF` build arg
- [ ] **Stop** the Railway service (gateway + dashboard) to avoid `state.db` corruption
- [ ] Confirm volume size / usage
- [ ] **Mandatory backup** (Railway snapshot or tar export — see Step 1)
- [ ] Inventory paths created inside the old `.hermes` mount from “install under ~/.hermes” workarounds
- [ ] List packages to reinstall into `~/.local` after cutover (anything only in ephemeral container layers)

## Step 1 — Backup the volume

### Option A — Railway

Use Railway volume snapshot / clone per [Railway docs](https://docs.railway.com/guides/volumes).

### Option B — One-off container

With the service stopped, attach the volume to a debug container:

```bash
docker run --rm -v <volume>:/mnt -v "$(pwd)":/backup alpine \
  tar -czf /backup/hermes-volume-pre-migration-$(date +%Y%m%d).tar.gz -C /mnt .
```

Verify the archive lists `config.yaml`, `state.db`, `.env` at the **archive root** (confirms flat layout from the old mount).

---

## Recommended path — cut over first, migrate in place

This is the intended Railway workflow: deploy **v0.1.0+**, remount the **same** volume at `/home/agent`, let the entrypoint prepare the home layout, then run the migration script via SSH.

### Step 2 — Deploy v0.1.0 and remount the volume

With the service **stopped**:

1. Deploy image **`v0.1.0+`**
2. Railway → Service → Volume: change mount path from **`/home/agent/.hermes`** to **`/home/agent`**
3. Env: `HERMES_HOME=/home/agent/.hermes` (image default; set explicitly if you overrode it before)
4. Leave start command **empty** (image `ENTRYPOINT` + `CMD sleep infinity`)
5. Redeploy / start the service

**What happens on first boot**

Your old volume still has Hermes state at the **volume root** (`config.yaml`, `state.db`, `.env`, … at `/home/agent/`). The entrypoint:

- Creates **`/home/agent/.hermes/logs`**, **`~/.local/bin`**, **`workspace/`** if missing
- **Does not** seed default Hermes config into `.hermes/` (your real data is still at `/home/agent/` root)
- **Does not** start gateway or dashboard (flat layout detected — avoids using wrong paths)
- Prints a message pointing you to the migration script

The container should stay up (`sleep infinity`) so you can SSH in.

### Step 3 — Run the migration script (Railway SSH)

Open **Railway SSH** (root shell). Run:

```bash
# Optional dry run
DRY_RUN=1 migrate-volume-to-home.sh /home/agent

# Apply
migrate-volume-to-home.sh /home/agent
```

The script is baked into the image at **`/usr/local/bin/migrate-volume-to-home.sh`**. It:

1. Moves everything at `/home/agent/` root (except `.hermes` itself) into **`/home/agent/.hermes/`** (flat → nested), **or** skips that if already nested.
2. Relocates **`/home/agent/.hermes/workspace/`** → **`/home/agent/workspace/`** (merge if both exist).
3. Creates **`~/.local`** and **`workspace/`** if missing.

Safe to re-run: already-nested volumes only perform the workspace step.

Verify:

```bash
ls -la /home/agent/.hermes/config.yaml /home/agent/.hermes/state.db /home/agent/.hermes/.env
# Should NOT still exist at /home/agent/config.yaml after migration
ls -la /home/agent/workspace/second-brain 2>/dev/null || ls -la /home/agent/workspace/
# Should NOT still have project files only under .hermes/workspace/
test ! -d /home/agent/.hermes/workspace && echo "workspace relocation OK"
```

### Step 4 — Restart the service

Restart or redeploy the Railway service. The entrypoint should now:

- See nested layout under `.hermes/` (no flat-layout warning)
- **Not** re-seed if `.docker-defaults-seeded` or existing config is present
- Start gateway and dashboard as usual

### Step 5 — Post-cutover validation

```bash
su - agent
hermes doctor
hermes skills list
hermes cron list
ls -la ~/.hermes/state.db ~/.hermes/.env
which hermes micro caddy
echo "$PATH"
```

Functional checks:

- Dashboard on port **9119** (with `HERMES_DASHBOARD_AUTH_USER` / `HERMES_DASHBOARD_AUTH_PASS`)
- Gateway running; `~/.hermes/gateway.pid` present
- Telegram / cron / hooks if used
- **Persistence test:** `agent-pip install cowsay` (v0.1.1+) or `npm install -g cowsay`, restart container, confirm import / `~/.local/bin`

---

## Alternative path — migrate before cutover

If you prefer to restructure the volume **before** changing the mount path (e.g. offline debug container):

1. Complete Step 1 (backup)
2. With the **old** image still mounted at `/home/agent/.hermes`, run:
   ```bash
   bash scripts/migrate-volume-to-home.sh /home/agent/.hermes
   ```
   (`/home/agent/.hermes` is the volume root in that layout.)
3. Then do Step 2 above (deploy v0.1.0, remount at `/home/agent`) — entrypoint should start normally without Step 3

This path is equivalent; use it if you want gateway/dashboard never paused on Railway.

---

For an automated pass over `~/.hermes` (path rewrites, misplaced installs, validation), paste the prompt in [hermes-agent-migration-prompt.md](./hermes-agent-migration-prompt.md) into a Hermes agent session after Steps 3–5.

## Step 6 — Workspace path in Hermes config (optional)

After relocation, update persisted references from `~/.hermes/workspace/...` to `/home/agent/workspace/...` if grep still finds them:

```bash
grep -rE '\.hermes/workspace|~/\.hermes/workspace' /home/agent/.hermes \
  --include='*.yaml' --include='*.md' --include='*.json' 2>/dev/null | head -20
```

Typical files: `cron/jobs.json` prompts, `memories/MEMORY.md`, `skills/**/SKILL.md`. Profile `terminal.cwd` entries should already use `/home/agent/workspace/second-brain` or `/home/agent/.hermes/profiles/<name>/workspace`.

## Step 7 — Relocate mistaken “install under .hermes” artifacts

After Step 3 (or the alternative path), scan `$ROOT/.hermes` for non-state trees:

| If found under `.hermes/` | Action |
|---------------------------|--------|
| `node/` (Hermes-bundled Node) | **Keep** under `.hermes/node` if present |
| `bin/`, `lib/`, `site-packages/` at `.hermes` root (pip hack) | Move to `../.local/` on volume |
| `.agent-browser/` | **Keep** in `.hermes/.agent-browser` |
| Skill-specific venvs | Keep under `.hermes/skills/…` or `.hermes/venvs/` |

Document changes in `~/.hermes/migration-notes.txt`.

## Step 8 — Reinstall ephemeral tooling

Anything installed only in the **container layer** on old deploys (not on the volume):

- Custom pip/npm packages in old ephemeral `~/.local`
- `uv`, `bun`, other CLIs
- Re-run `agent-browser install` only if Chrome is missing from `~/.hermes/.agent-browser`

Track reinstall commands in `~/.hermes/migration-reinstall.txt`.

## Step 9 — Path audit in persisted config

```bash
grep -rE '/home/agent/hermes-agent|/opt/hermes' ~/.hermes \
  --include='*.yaml' --include='*.md' --include='*.json' 2>/dev/null | head -50
```

Update cron `workdir` / skill paths if they referenced `/home/agent/hermes-agent`. Custom `start-gateways.sh` should keep profile paths as `/home/agent/.hermes/profiles/...`.

## Step 10 — Git credentials

With the full home mount, place once on the volume:

```
/home/agent/.gitconfig
/home/agent/.git-credentials
```

No separate file-level Docker mounts needed.

## Rollback

| Situation | Action |
|-----------|--------|
| Cutover failed **before** Step 3 migration | Remount at `/home/agent/.hermes`, redeploy **v0.0.x** image (your data is still at volume root) |
| Step 3 done, new image fails | Keep mount at `/home/agent`; fix forward — nested `.hermes` is valid for v0.1.0+ |
| Need full rollback after Step 3 | Restore from Step 1 backup; do not flatten without a backup |

## Local dev parity (hermes-stack)

```bash
mkdir -p ./tmp/agent-home
# One-time from old layout:
# mv ./tmp/.hermes ./tmp/agent-home/.hermes
# DRY_RUN=1 migrate-volume-to-home.sh ./tmp/agent-home   # or run inside a debug container with the mount
# migrate-volume-to-home.sh ./tmp/agent-home

docker compose ... -v ./tmp/agent-home:/home/agent
```

## Where to install packages (after migration)

| Purpose | Location |
|---------|----------|
| Hermes config, sessions, cron, skills | `$HERMES_HOME` (`~/.hermes`) |
| User Python (`agent-pip install`, v0.1.1+) | `~/.local/lib/python*/site-packages` |
| User CLIs (`npm install -g` with default prefix) | `~/.local` |
| Bun | `~/.bun` |
| Caches | `~/.cache`, `~/.npm` |
| Baked Hermes app | `/opt/hermes-agent` (image — do not modify) |
| Baked CLIs (codex, micro, hermes wrapper) | `/usr/local/bin` (image) |
