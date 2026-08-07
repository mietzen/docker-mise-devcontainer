# Mise Devcontainer

Base image for vscode devcontainers with mise, uv and zsh. The image is automatically built, released and pushed as soon as a new Debian base image, mise or uv release is available.

## Features:

- Debian `trixie` (slim)
- [mise](https://mise.jdx.dev/) pinned via `MISE_VERSION`, with **Node 24** and **usage** preinstalled
- [uv](https://docs.astral.sh/uv/) pinned via `UV_VERSION`
- zsh + oh-my-zsh with mise activated
- Non-root user `vscode` (uid/gid 1000)

## Persistent volume

Mount a persistent volume at `/home/vscode/.persist`. `vscode` can make it writable with a single sudo command:

```shell
sudo chown -R vscode:vscode /home/vscode/.persist
```

## Versioning

Every merged update PR creates a GitHub release. The bump level depends on the trigger: mise/uv updates bump the minor version, Debian base image updates bump the patch. The image is tagged with:

- `:1.2.3`
- `:1.2.3-mise-v2026.8.0-uv0.12.0`
- `:latest`

## How it works

The image is rebuilt and released automatically when one of the upstream inputs changes:

- Dependabot proposes updates for the Debian base image and the GitHub Actions.
- The auto-update workflows run daily and open a PR when a new mise or uv release is available.
- Auto-merge squash-merges the PR once the build check passes.
- `auto-release.yml` creates a GitHub release (minor for mise/uv, patch for the Debian base image).
- `docker-image.yml` builds and pushes the tags. On pull requests it only builds.

## Preparation

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

## Local build

```shell
docker build \
  --build-arg MISE_VERSION="$(cat MISE_VERSION)" \
  --build-arg UV_VERSION="$(cat UV_VERSION)" \
  -t mise-devcontainer:local .
```
