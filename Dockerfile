# syntax=docker/dockerfile:1.5
FROM debian:trixie-20260803-slim

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