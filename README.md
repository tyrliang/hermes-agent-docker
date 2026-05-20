# hermes-agent-docker

Minimal Docker image packaging for [Hermes Agent](https://github.com/NousResearch/hermes-agent).

## Image contents

The image in this repo:

- installs Hermes with the official upstream install script
- includes `mini-swe-agent`
- persists Hermes state under `/home/agent/.hermes`
- is intended for straightforward local builds and multi-arch publishing

## Quick start

### Build locally

Build the latest `main` by default:

```bash
docker build -t hermes-agent-docker:local .
```

Build a specific Hermes tag:

```bash
docker build \
  --build-arg HERMES_REF=v2026.3.30 \
  -t hermes-agent-docker:v2026.3.30 .
```

`HERMES_REF` defaults to `main` and can point to either a branch or a tag.

### Run Hermes

Mount two paths:

- your current project into `/home/agent/workspace`
- a persistent Hermes home directory into `/home/agent/.hermes`

```bash
docker run --rm -it \
  -v "./tmp/workspace:/home/agent/workspace" \
  -v "./tmp/.hermes:/home/agent/.hermes" \
  hermes-agent-docker:local \
  hermes
```

### Run doctor

```bash
docker run --rm \
  -v "./tmp/.hermes:/home/agent/.hermes" \
  hermes-agent-docker:local \
  hermes doctor
```

## Persistence

Hermes stores config, sessions, memories, and related state in `/home/agent/.hermes` inside the container. Mount that path to keep state across runs.

On first start with an empty mounted `/home/agent/.hermes`, the container seeds that directory from image-prepared Hermes defaults before launching the requested command.

If you do not mount `/home/agent/.hermes`, Hermes will still start, but its state will be lost when the container exits.

## Environment and setup

Run `hermes setup` inside the container and persist `/home/agent/.hermes`, or place the expected config files inside that mounted directory.

