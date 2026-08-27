# syntax=docker/dockerfile:1.5

# Default target: the mise devcontainer base image.
# Alternative target `did`: same image plus a Docker daemon (docker-in-docker).
# Building `--target did` resolves FROM base as a stage within the same build,
# so no image push/daemon load is needed between the two targets.
FROM debian:trixie-20260824-slim AS base

ARG MISE_VERSION
ARG UV_VERSION
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

# mise data/cache live under the non-root user's home.
ENV PATH="/home/${USERNAME}/.local/share/mise/shims:/home/${USERNAME}/.local/bin:${PATH}"

# non-root user setup
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git build-essential wget jq zsh sudo; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd --gid "${USER_GID}" "${USERNAME}"; \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" \
        --create-home --shell /usr/bin/zsh "${USERNAME}"; \
printf '%s\n' \
        "Defaults:${USERNAME} !authenticate" \
        "Defaults:${USERNAME} cmddenial_message=\"Only 'sudo chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.persist' is allowed.\"" \
        "${USERNAME} ALL=(root) NOPASSWD: /usr/bin/chown -R ${USERNAME}\\:${USERNAME} /home/${USERNAME}/.persist" \
        > "/etc/sudoers.d/${USERNAME}"; \
    chmod 0440 "/etc/sudoers.d/${USERNAME}";

# switch to non-root user
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --skip-chsh;
COPY --chown=${USER_UID}:${USER_GID} .zshrc /home/${USERNAME}/.zshrc

# mise
RUN set -eux; \
    curl -fsSL https://mise.jdx.dev/install.sh -o /tmp/mise-install.sh; \
    MISE_VERSION="${MISE_VERSION}" sh /tmp/mise-install.sh; \
    rm /tmp/mise-install.sh; \
    mise --version; \
    mise use --global usage@latest; \
    mise completion zsh > /home/${USERNAME}/.oh-my-zsh/lib/mise.zsh

# uv 
RUN set -eux; \
    curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" -o /tmp/uv-install.sh; \
    sh /tmp/uv-install.sh; \
    rm /tmp/uv-install.sh; \
    uv --version; \
    uv generate-shell-completion zsh > /home/${USERNAME}/.oh-my-zsh/lib/uv.zsh

# Persistent volume mountpoint
RUN mkdir -p /home/${USERNAME}/.persist;

CMD ["/usr/bin/zsh"]

# --- docker-in-docker variant ---------------------------------------------
FROM base AS did

ARG USERNAME=vscode
ARG DOCKER_VERSION

# dockerd must run as root; the exec'd command runs as vscode afterwards
# (docker-init.sh drops privileges via setpriv to the docker group).
USER root

# Docker Engine from the official repository (download.docker.com), pinned to
# DOCKER_VERSION. The Debian docker.io package lags upstream by many releases
# and ships no buildx/compose plugins.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        gnupg iptables erofs-utils; \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /tmp/docker.gpg; \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg /tmp/docker.gpg; \
    rm /tmp/docker.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian trixie stable" \
        > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    DOCKER_CE_VERSION=$(apt-cache madison docker-ce-cli | awk -v d="5:${DOCKER_VERSION}" '$0 ~ d {print $3; exit}'); \
    test -n "${DOCKER_CE_VERSION}"; \
    apt-get install -y --no-install-recommends \
        "docker-ce=${DOCKER_CE_VERSION}" \
        "docker-ce-cli=${DOCKER_CE_VERSION}" \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin; \
    rm -rf /var/lib/apt/lists/*; \
    usermod -aG docker "${USERNAME}";

# Only the docker CLI ships a "completion" subcommand; buildx and compose do not.
RUN docker completion zsh > /home/${USERNAME}/.oh-my-zsh/lib/docker.zsh \
    && chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.oh-my-zsh/lib/docker.zsh

# Start dockerd on container start, then run the container command as vscode.
COPY docker-init.sh /usr/local/share/docker-init.sh
RUN chmod +x /usr/local/share/docker-init.sh

ENTRYPOINT ["/usr/local/share/docker-init.sh"]
CMD ["/usr/bin/zsh"]

# Keep the default push target = the plain base image (docker build without
# --target builds the last stage).
FROM base