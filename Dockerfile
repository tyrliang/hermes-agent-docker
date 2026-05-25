# syntax=docker/dockerfile:1.7
# Pin base by digest so an upstream tag bump doesn't silently invalidate the entire cache. Bump deliberately.
FROM docker/sandbox-templates:shell@sha256:2f32da82c56bc660c7af142f1b235e33f96f2e7316e1151f03bb88a1927b9df6

ARG HERMES_REF=main
ARG CODEX_VERSION=0.118.0
ARG MICRO_VERSION=2.0.14
ARG CADDY_VERSION=2.11.3
ARG TARGETARCH

COPY docker-entrypoint.sh /usr/local/bin/hermes-entrypoint
COPY scripts/migrate-volume-to-home.sh /usr/local/bin/migrate-volume-to-home.sh

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ffmpeg nano zsh zip \
    && ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
         amd64) MICRO_ASSET_SUFFIX=linux64;     CADDY_ASSET_SUFFIX=linux_amd64 ;; \
         arm64) MICRO_ASSET_SUFFIX=linux-arm64; CADDY_ASSET_SUFFIX=linux_arm64 ;; \
         *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/zyedidia/micro/releases/download/v${MICRO_VERSION}/micro-${MICRO_VERSION}-${MICRO_ASSET_SUFFIX}.tar.gz" \
    | tar -xzf - -C /tmp \
    && mv "/tmp/micro-${MICRO_VERSION}/micro" /usr/local/bin/micro \
    && rm -rf "/tmp/micro-${MICRO_VERSION}" \
    && curl -fsSL "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_${CADDY_ASSET_SUFFIX}.tar.gz" \
    | tar -xzf - -C /usr/local/bin caddy \
    && chmod +x /usr/local/bin/caddy \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /home/agent/.hermes \
    && chown -R agent:agent /home/agent/.hermes

# Baked npm CLIs — system prefix so a fresh /home/agent volume does not hide them.
RUN --mount=type=cache,id=npm-${TARGETARCH},target=/var/cache/npm \
    npm install -g \
    @openai/codex@${CODEX_VERSION} \
    @anthropic-ai/claude-code \
    opencode-ai

# uv installs Python under $HOME/.local by default; root's /root is 700 so agent cannot exec the venv.
ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python

# install.sh git-clones into --dir; do not pre-create /opt/hermes-agent (empty dir fails the installer).
RUN HERMES_HOME=/home/agent/.hermes HOME=/home/agent \
    curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_REF}/scripts/install.sh" \
    | bash -s -- --skip-setup --branch "${HERMES_REF}" --dir /opt/hermes-agent

# Local STT (HERMES_STT_PROVIDER=local); ffmpeg is installed above.
RUN uv pip install --python /opt/hermes-agent/venv/bin/python faster-whisper==1.2.1

RUN --mount=type=cache,id=npm-${TARGETARCH},target=/var/cache/npm \
    cd /opt/hermes-agent \
    && (npm audit fix >/dev/null || [ $? -eq 1 ])

# Dashboard entrypoint uses `hermes dashboard --skip-build`; static UI must exist at hermes_cli/web_dist.
RUN --mount=type=cache,id=npm-${TARGETARCH},target=/var/cache/npm \
    cd /opt/hermes-agent/web \
    && npm ci \
    && npm run build

RUN --mount=type=cache,id=npm-${TARGETARCH},target=/var/cache/npm \
    cd /opt/hermes-agent/scripts/whatsapp-bridge \
    && (npm audit fix >/dev/null || [ $? -eq 1 ])

USER agent
ENV HOME=/home/agent
ENV SHELL=/bin/zsh
WORKDIR /home/agent

# Shell UX snapshot source (copied to /usr/local/share/agent-home-seed after PATH update).
RUN RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    && ZSH_CUSTOM="${HOME}/.oh-my-zsh/custom" \
    && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" \
    && sed -i 's/^plugins=(git)/plugins=(sudo history colored-man-pages zsh-autosuggestions zsh-syntax-highlighting)/' "${HOME}/.zshrc"

USER root

# Real hermes launcher — independent of $HOME/.local (hidden when /home/agent is volume-mounted).
RUN printf '%s\n' \
         '#!/bin/sh' \
         '# hermes-agent-docker — exec venv entrypoint; clear inherited PYTHONPATH.' \
         'unset PYTHONPATH PYTHONHOME' \
         'exec /opt/hermes-agent/venv/bin/hermes "$@"' \
       > /usr/local/bin/hermes \
    && chmod 755 /usr/local/bin/hermes

RUN HERMES_HOME=/home/agent/.hermes HOME=/home/agent /usr/local/bin/hermes skills list >/dev/null

# Entrypoint drops to agent; venv Python must not live under /root (700).
RUN runuser -u agent -- env HOME=/home/agent HERMES_HOME=/home/agent/.hermes /usr/local/bin/hermes skills list >/dev/null

RUN mkdir -p /usr/local/share/hermes-home \
    && cp -a /home/agent/.hermes/. /usr/local/share/hermes-home/ \
    && chmod 755 /usr/local/bin/hermes-entrypoint /usr/local/bin/migrate-volume-to-home.sh \
    && chown -R agent:agent /usr/local/share/hermes-home \
    && chsh -s /bin/zsh agent

# zsh: PATH + FHS env for login and non-login shells.
RUN grep -q 'hermes-agent-docker PATH' /home/agent/.zshrc 2>/dev/null || printf '%s\n' \
         '' \
         '# hermes-agent-docker PATH' \
         'export HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"' \
         'export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"' \
         'export npm_config_cache="${npm_config_cache:-$HOME/.npm}"' \
         'export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"' \
         'export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"' \
         'export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"' \
         'export PATH="$HOME/.local/bin:$HOME/.bun/bin:/opt/hermes-agent/venv/bin:/usr/local/bin:$PATH"' \
       >> /home/agent/.zshrc \
    && mkdir -p /usr/local/share/agent-home-seed \
    && cp -a /home/agent/.oh-my-zsh /usr/local/share/agent-home-seed/ \
    && cp /home/agent/.zshrc /usr/local/share/agent-home-seed/.zshrc \
    && chown -R agent:agent /usr/local/share/agent-home-seed

RUN printf '%s\n' \
         '# Hermes Agent — agent home + CLI paths for login shells (Railway SSH, su - agent).' \
         'export HERMES_HOME="${HERMES_HOME:-/home/agent/.hermes}"' \
         'export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$HOME/.local}"' \
         'export npm_config_cache="${npm_config_cache:-$HOME/.npm}"' \
         'export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"' \
         'export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"' \
         'export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"' \
         'case ":${PATH}:" in *:/home/agent/.local/bin:*) ;; *) PATH="/home/agent/.local/bin:${PATH}" ;; esac' \
         'case ":${PATH}:" in *:/home/agent/.bun/bin:*) ;; *) PATH="/home/agent/.bun/bin:${PATH}" ;; esac' \
         'case ":${PATH}:" in *:/opt/hermes-agent/venv/bin:*) ;; *) PATH="/opt/hermes-agent/venv/bin:${PATH}" ;; esac' \
         'export PATH' \
       > /etc/profile.d/hermes-agent.sh \
    && chmod 644 /etc/profile.d/hermes-agent.sh

ENV HERMES_HOME=/home/agent/.hermes
ENV NPM_CONFIG_PREFIX=/home/agent/.local
ENV BUN_INSTALL=/home/agent/.bun
ENV XDG_CACHE_HOME=/home/agent/.cache
ENV XDG_DATA_HOME=/home/agent/.local/share
ENV PATH="/home/agent/.local/bin:/home/agent/.bun/bin:/opt/hermes-agent/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Run entrypoint as root so it can chown a persisted volume, then drop to agent (see entrypoint).
USER root
WORKDIR /home/agent/workspace
VOLUME ["/home/agent"]
ENTRYPOINT ["/usr/local/bin/hermes-entrypoint"]
# Foreground process after entrypoint auto-start; Compose/Railway should not override this.
CMD ["sleep", "infinity"]
