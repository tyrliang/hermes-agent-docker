# Hermes agent prompt: v0.0.8 → v0.1.0 `~/.hermes` path migration

Operator guide for infrastructure cutover: [railway-home-volume-migration.md](./railway-home-volume-migration.md).

After the volume is remounted at `/home/agent` and `migrate-volume-to-home.sh` has run (if needed), paste the prompt below into a Hermes agent session with filesystem access. The agent should run as user **`agent`** (`su - agent` if the shell is root).

---

## Operator checklist (before pasting)

1. Deploy **v0.1.0+** and remount the volume at **`/home/agent`** (not `/home/agent/.hermes`).
2. If the entrypoint prints **legacy flat volume**, run as root:
   ```bash
   DRY_RUN=1 migrate-volume-to-home.sh /home/agent
   migrate-volume-to-home.sh /home/agent
   ```
   That script nests Hermes state under `.hermes/`, relocates **`~/.hermes/workspace` → `/home/agent/workspace`**, and creates `~/.local` + `workspace/`. Restart the service before continuing.
3. Paste the **Agent prompt** section into Hermes.

---

## Agent prompt

```markdown
# Task: Complete Hermes v0.0.8 → v0.1.0 path migration under ~/.hermes

You are running inside **hermes-agent-docker v0.1.0+**. The Railway/local volume now mounts at **`/home/agent`** (not `/home/agent/.hermes`). **`HERMES_HOME` is still `/home/agent/.hermes`** (`~/.hermes`). Hermes state belongs only under `~/.hermes`; user CLIs and package installs belong under **`/home/agent`** (`~/.local`, `~/.bun`, `~/.npm`, `~/.cache`), not inside `~/.hermes`.

Shared project files (second-brain, daily-ai-briefing, etc.) belong in **`/home/agent/workspace`** (Docker `WORKDIR`), not `~/.hermes/workspace`.

Work as user **`agent`** (`su - agent` if you are root). Do not modify **`/opt/hermes-agent`** or **`/usr/local/bin`** (image-baked). Do not delete `state.db`, `config.yaml`, or `.env` without explicit backup.

---

## Phase 0 — Preconditions

1. Confirm layout:
   ```bash
   ls -la /home/agent/.hermes/config.yaml /home/agent/.hermes/state.db /home/agent/.hermes/.env 2>/dev/null
   ls -la /home/agent/config.yaml /home/agent/state.db 2>/dev/null
   ls -la /home/agent/workspace 2>/dev/null
   ```
2. If `config.yaml` / `state.db` / `.env` exist at **`/home/agent/` root** but NOT under **`/home/agent/.hermes/`**, stop and tell the operator to run first (as root):
   ```bash
   DRY_RUN=1 migrate-volume-to-home.sh /home/agent
   migrate-volume-to-home.sh /home/agent
   ```
   Then restart the service before continuing.

3. If `~/.hermes/workspace` still exists with project files, tell the operator to run `migrate-volume-to-home.sh /home/agent` (it moves/merges into `/home/agent/workspace`).

4. Record baseline:
   ```bash
   hermes doctor 2>&1 | tee ~/.hermes/migration-notes.txt
   date -u >> ~/.hermes/migration-notes.txt
   ```

---

## Phase 1 — Path reference (use when rewriting)

| Role | Old / wrong (v0.0.x) | Correct (v0.1.0+) |
|------|----------------------|-------------------|
| Agent home (volume root) | volume = `~/.hermes` only | **`/home/agent`** (`$HOME`) |
| Hermes state | sometimes flat at volume root | **`$HERMES_HOME` = `~/.hermes`** |
| Shared projects | `~/.hermes/workspace/...` | **`~/workspace/...`** (`/home/agent/workspace`) |
| Hermes app + venv | `/opt/hermes`, `/home/agent/hermes-agent` | **`/opt/hermes-agent`** (image only) |
| Hermes CLI | `/opt/hermes/.venv/bin/python3 /opt/hermes/hermes` | **`hermes`** on PATH → `/usr/local/bin/hermes` |
| User pip/npm globals | `~/.hermes/bin`, `~/.hermes/lib`, `~/.hermes/site-packages` | **`~/.local/bin`**, **`~/.local/lib`** |
| npm prefix | under `~/.hermes` | **`NPM_CONFIG_PREFIX=~/.local`** |
| Bun | under `~/.hermes` | **`~/.bun`** |
| Profiles | `/opt/data/profiles/...` | **`~/.hermes/profiles/...`** |
| Cron/skill workdirs | `/home/agent/hermes-agent`, `~/.hermes/workspace`, `/opt/hermes/...` | **`/home/agent/workspace/...`** or paths under **`~/.hermes`** |
| Chrome / agent-browser | outside `.hermes` | **`~/.hermes/.agent-browser`** (keep here) |
| Hermes-bundled Node | — | **`~/.hermes/node`** if present — **keep** |
| Skill venvs | — | **`~/.hermes/skills/...`**, **`~/.hermes/venvs/...`** — **keep** |
| Baked CLIs (codex, micro, caddy) | copied into volume | **`/usr/local/bin`** (image — do not duplicate on volume) |

Expected PATH (from profile):  
`~/.local/bin` → `~/.bun/bin` → `/opt/hermes-agent/venv/bin` → `/usr/local/bin` → system paths.

---

## Phase 2 — Relocate mistaken installs out of ~/.hermes

Scan `~/.hermes` for trees that are **not** Hermes state. For each, **move** (do not copy-delete without verifying) to the correct home location and log in `~/.hermes/migration-notes.txt`:

| If found under `~/.hermes/` | Action |
|----------------------------|--------|
| `bin/`, `lib/`, `site-packages/`, `share/` at `.hermes` root (pip `--user` hack) | Move contents to **`~/.local/`** (merge carefully; preserve permissions) |
| `node_modules/` at `.hermes` root for global tools | Prefer **`npm install -g`** into `~/.local` after move; document in `migration-reinstall.txt` |
| `workspace/` with projects (second-brain, etc.) | Move/merge to **`/home/agent/workspace/`** if `migrate-volume-to-home.sh` did not already |
| Duplicate `hermes-agent/` source tree under `.hermes` | **Do not use** — app is `/opt/hermes-agent`; archive or remove only after confirming nothing references it |
| `.gitconfig`, `.git-credentials` under `.hermes` | Move to **`/home/agent/.gitconfig`**, **`/home/agent/.git-credentials`** |
| `.npm`, `.cache`, `.config` under `.hermes` | Move to **`/home/agent/.npm`**, **`.cache`**, **`.config`** |
| `.agent-browser/` | **Keep** in `~/.hermes/.agent-browser` |
| `node/` (Hermes-bundled) | **Keep** |
| `skills/`, `venvs/`, `profiles/`, `cron/`, `sessions/`, `plugins/`, `logs/`, `state.db`, `config.yaml`, `.env` | **Keep** in `~/.hermes` |

Create dirs if missing: `mkdir -p ~/.local/bin ~/.bun ~/.npm ~/.cache ~/workspace`.

---

## Phase 3 — Update all path references inside ~/.hermes

Recursively audit and fix **every** persisted file under `~/.hermes` that embeds old paths. Search:

```bash
grep -rE '/home/agent/hermes-agent|/opt/hermes[^-]|/opt/data/profiles|/opt/hermes\.venv|PYTHONPATH.*hermes|NPM_CONFIG_PREFIX.*\.hermes|\.hermes/bin|\.hermes/lib|\.hermes/workspace' \
  ~/.hermes \
  --include='*.yaml' --include='*.yml' --include='*.json' --include='*.md' --include='*.sh' --include='*.env' --include='*.txt' \
  2>/dev/null
```

Apply these rewrite rules (context-aware; do not break intentional relative paths):

1. `/home/agent/hermes-agent` → `/home/agent/workspace` or the actual project path under `~/workspace`
2. `~/.hermes/workspace/` or `/home/agent/.hermes/workspace/` → `/home/agent/workspace/`
3. `/opt/hermes/` or `/opt/hermes` (not `/opt/hermes-agent`) → remove or replace with `hermes` CLI / `/opt/hermes-agent` only in comments documenting image layout
4. `/opt/data/profiles/` → `/home/agent/.hermes/profiles/`
5. `/opt/hermes/.venv/bin/python3` + `hermes` invocations → `hermes` (bare CLI)
6. `PYTHONPATH=...hermes...` in startup scripts → remove unless a specific skill venv requires it (document exception)
7. Cron `workdir`, skill `cwd`, hook scripts, `start-gateways.sh`, profile docs: align to **`/home/agent/.hermes/profiles/<name>/...`** and **`/home/agent/workspace/...`**
8. `.env` keys pointing at old install roots: update to current layout; keep secrets unchanged
9. Session JSON / memory / knowledge paths: update only absolute paths; leave content hashes and IDs alone

**High-priority files** (edit if present):  
`config.yaml`, `.env`, `cron/jobs.json`, `start-gateways.sh`, `hooks/**`, `profiles/**/config.yaml`, `skills/**/SKILL.md`, `knowledge-config.json`, any `*.sh` in `~/.hermes`.

For `start-gateways.sh` specifically:
- Drop obsolete `PYTHONPATH` exports
- Use `hermes` on PATH, not `/opt/hermes/.venv/bin/python3 /opt/hermes/hermes`
- Profile dirs: `/home/agent/.hermes/profiles/$profile`

Append a summary of every file changed to **`~/.hermes/migration-notes.txt`**.

---

## Phase 4 — Reinstall list for ephemeral tooling

Anything that lived only in the **old container layer** (not on the volume) must be reinstalled into the new layout. Create **`~/.hermes/migration-reinstall.txt`** listing:
- packages/tools you cannot find under `~/.local/bin`, `~/.bun/bin`, or `/usr/local/bin`
- commands to run, e.g. `pip install --user <pkg>`, `npm install -g <pkg>`, `uv tool install ...`
- whether `agent-browser install` is needed (only if `~/.hermes/.agent-browser` is missing)

Do **not** reinstall Hermes itself into the volume.

---

## Phase 5 — Validation

Run and capture output in `migration-notes.txt`:

```bash
export HOME=/home/agent HERMES_HOME=/home/agent/.hermes
which hermes micro caddy codex 2>/dev/null || true
echo "PATH=$PATH"
hermes doctor
hermes skills list
hermes cron list
ls -la ~/.hermes/state.db ~/.hermes/.env ~/.hermes/gateway.pid 2>/dev/null || true
ls -la ~/workspace 2>/dev/null | head -10
grep -rE '/opt/hermes[^-]|/home/agent/hermes-agent|/opt/data/|\.hermes/workspace' ~/.hermes \
  --include='*.yaml' --include='*.json' --include='*.sh' --include='*.env' 2>/dev/null | head -30 || echo "No stale paths found"
```

Success criteria:
- No Hermes markers at `/home/agent/config.yaml` (only under `~/.hermes`)
- Shared projects under `~/workspace`, not `~/.hermes/workspace`
- No remaining stale absolute paths in config/cron/scripts (grep clean or documented exceptions)
- `hermes doctor` passes
- Cron jobs show sensible `workdir` under `workspace` or `.hermes`
- User tools expected in `~/.local/bin`, not `~/.hermes/bin`

Report: files moved, files edited, reinstall commands, validation results, and anything requiring operator restart (gateway/dashboard).
```
