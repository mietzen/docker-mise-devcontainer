# Mise Devcontainer

Base image for [devcontainers](https://containers.dev/overview) with [`mise`](https://mise.jdx.dev/), [`uv`](https://docs.astral.sh/uv/) and [`zsh`](https://github.com/zsh-users/zsh). The image is automatically built, released and pushed as soon as a new [Debian base image](https://hub.docker.com/_/debian), [`mise`](https://mise.jdx.dev/) or [`uv`](https://docs.astral.sh/uv/) release is available.

## Usage

Use this image as base for your [`mise`](https://mise.jdx.dev/) [devcontainer](https://containers.dev/):

```json
{
  "image": "mietzen/mise-devcontainer:latest"
}
```

## Docker-in-Docker image

A second image adds a Docker daemon to the same base: `mietzen/mise-devcontainer-did`. Use it when the devcontainer itself needs to run containers (e.g. to test the project's own Docker build).

It must run privileged:

```json
{
  "image": "mietzen/mise-devcontainer-did:latest",
  "runArgs": ["--privileged"]
}
```

The container starts as root only to boot `dockerd`, then drops to the `vscode` user. `vscode` reaches the daemon via the `docker` group — no sudo needed. `docker compose` is included.

## Features

- [`mise`](https://mise.jdx.dev/) pinned via `MISE_VERSION`, no tools preinstalled (add them per-project via a `.mise.toml` in your repo)
- [`uv`](https://docs.astral.sh/uv/) pinned via `UV_VERSION`
- [`zsh`](https://github.com/zsh-users/zsh) + [`oh-my-zsh`](https://github.com/ohmyzsh/ohmyzsh) with mise activated
- Non-root user `vscode` (uid/gid 1000), can only use `sudo` to own persistent volumes

## Persistent volume

Mount your persistent volume(s) at `/home/vscode/.persist`. `vscode` can make it writable with a single sudo command:

```shell
sudo chown -R vscode:vscode /home/vscode/.persist
```

In your [`postCreateCommand`](https://containers.dev/implementors/json_reference/#lifecycle-scripts).

## Auto updates

The image is rebuilt and released automatically when one of the upstream inputs changes:

- Dependabot proposes updates for the Debian base image and the GitHub Actions.
- The auto-update workflows run daily and open a PR when a new mise or uv release is available.
- Auto-merge squash-merges the PR once the build check passes.
- `auto-release.yml` creates a GitHub release (minor for mise/uv, patch for the Debian base image).
- `docker-image.yml` builds and pushes the tags. On pull requests it only builds.

## Forking

Feel free to fork this repository and edit it to your needs, to get CI running you will need the following:

### GitHub App

The workflows authenticate with a single GitHub App to create PRs, merge them and create releases. See [actions/create-github-app-token](https://github.com/actions/create-github-app-token) for the setup.

### Secrets

| Secret | Purpose |
|---|---|
| `APP_ID` | GitHub App ID |
| `APP_PRIVATE_KEY` | GitHub App private key |
| `DOCKER_HUB_DEPLOY_KEY` | Docker Hub token used for `docker login` |

**[Optional]** Add your DockerHub username and image name under variables:

| Variable | Purpose | Default |
|---|---|---|
| `DOCKER_HUB_USERNAME` | Docker Hub account to push under | `github.repository_owner` |
| `IMAGE_NAME` | Image name on Docker Hub | repo name (lowercased) |
