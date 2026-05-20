FROM docker/sandbox-templates:shell

ARG HERMES_REF=main
ARG CODEX_VERSION=0.118.0
ARG MICRO_VERSION=2.0.14

COPY docker-entrypoint.sh /usr/local/bin/hermes-entrypoint

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ffmpeg nano zsh zip \
    && ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
         amd64) MICRO_ASSET_SUFFIX=linux64 ;; \
         arm64) MICRO_ASSET_SUFFIX=linux-arm64 ;; \
         *) echo "unsupported architecture for micro: $ARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/zyedidia/micro/releases/download/v${MICRO_VERSION}/micro-${MICRO_VERSION}-${MICRO_ASSET_SUFFIX}.tar.gz" \
    | tar -xzf - -C /tmp \
    && mv "/tmp/micro-${MICRO_VERSION}/micro" /usr/local/bin/micro \
    && rm -rf "/tmp/micro-${MICRO_VERSION}" \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /home/agent/.hermes /home/agent/.local/bin \
    && chown -R agent:agent /home/agent/.hermes /home/agent/.local

USER agent
ENV HOME=/home/agent
ENV SHELL=/bin/zsh
ENV PATH="/home/agent/.local/bin:${PATH}"
WORKDIR /home/agent

RUN RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    && ZSH_CUSTOM="${HOME}/.oh-my-zsh/custom" \
    && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" \
    && sed -i 's/^plugins=(git)/plugins=(sudo history colored-man-pages zsh-autosuggestions zsh-syntax-highlighting)/' "${HOME}/.zshrc"

RUN curl -fsSL "https://raw.githubusercontent.com/NousResearch/hermes-agent/${HERMES_REF}/scripts/install.sh" \
    | bash -s -- --skip-setup --branch "${HERMES_REF}" --dir /home/agent/hermes-agent

RUN NPM_CONFIG_PREFIX=/home/agent/.local npm install -g \
    @openai/codex@${CODEX_VERSION} \
    @anthropic-ai/claude-code \
    opencode-ai

RUN cd /home/agent/hermes-agent \
    && (npm audit fix >/dev/null || [ $? -eq 1 ])

RUN cd /home/agent/hermes-agent/scripts/whatsapp-bridge \
    && (npm audit fix >/dev/null || [ $? -eq 1 ])

RUN HERMES_HOME=/home/agent/.hermes HOME=/home/agent hermes skills list >/dev/null

USER root
RUN mkdir -p /usr/local/share/hermes-home \
    && cp -a /home/agent/.hermes/. /usr/local/share/hermes-home/ \
    && chmod 755 /usr/local/bin/hermes-entrypoint \
    && chown -R agent:agent /usr/local/share/hermes-home \
    && chsh -s /bin/zsh agent

USER agent
WORKDIR /home/agent/workspace
VOLUME ["/home/agent/.hermes"]
ENTRYPOINT ["/usr/local/bin/hermes-entrypoint"]
