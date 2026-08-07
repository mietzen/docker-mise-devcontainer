# syntax=docker/dockerfile:1.5

# Base for a vscode devcontainer: Debian + mise (with node + usage), uv,
# zsh/oh-my-zsh, and a non-root user with scoped sudo for a persistent volume.
#
# Build args are threaded in by the release workflow:
#   docker buildx build --build-arg MISE_VERSION=$(cat MISE_VERSION) --build-arg UV_VERSION=$(cat UV_VERSION) ...
FROM debian:trixie-20260803-slim

ARG MISE_VERSION
ARG UV_VERSION
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

# mise data/cache live under the non-root user's home.
ENV PATH="/home/${USERNAME}/.local/share/mise/shims:/home/${USERNAME}/.local/bin:${PATH}"

# 1) OS-level deps as root + non-root user + hardened sudo (single chown).
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

# 2) Everything runtime-related runs as the non-root user.
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# 3) mise (pinned) + built-in Node 24 + usage, installed via mise itself.
RUN set -eux; \
    curl -fsSL https://mise.jdx.dev/install.sh | MISE_VERSION="${MISE_VERSION}" sh; \
    export PATH="/home/${USERNAME}/.local/share/mise/shims:/home/${USERNAME}/.local/bin:${PATH}"; \
    mise use --global node@24; \
    mise use --global usage@latest; \
    mise install; \
    mise reshim;

# 4) uv (pinned) via its own installer. The version goes in the URL path, not
#    an env var (uv's installer hardcodes the version into the script).
RUN set -eux; \
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh;

# 5) Persistent volume mountpoint that the user may chown-ed via sudo.
RUN mkdir -p /home/${USERNAME}/.persist;

# 6) zsh + oh-my-zsh with a minimal mise-priming .zshrc.
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --skip-chsh;

COPY --chown=${USER_UID}:${USER_GID} .zshrc /home/${USERNAME}/.zshrc

CMD ["/usr/bin/zsh"]