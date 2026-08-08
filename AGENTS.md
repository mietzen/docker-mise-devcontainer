# AGENTS.md

## What this repo is

A Docker Hub base image for vscode devcontainers. The repo is a build pipeline: it tracks four upstream inputs (Debian base image, mise, uv, docker), builds a multi-arch image from them, and publishes it — fully automated.

## Repo layout

- `Dockerfile` — multi-stage: `debian:trixie-slim` base stage (`base`) builds the mise/uv devcontainer image; a second stage (`did`) is the `-did` image with a Docker daemon. Default target is `base` (a trailing `FROM base` keeps plain `docker build` producing the base image). Build the `did` stage with `--target did` — `FROM base` resolves as a stage in the same solve, no registry/daemon round-trip between the two targets. `ARG MISE_VERSION` / `ARG UV_VERSION` / `ARG DOCKER_VERSION` are required build args. Installs mise and uv pinned to those args (no tools preinstalled — projects add them via `.mise.toml`), oh-my-zsh, non-root `vscode` user, `.persist` mountpoint, scoped sudo. The `did` stage installs Docker Engine from the official `download.docker.com` repo (not the Debian `docker.io` package) pinned to `DOCKER_VERSION`, plus the buildx and compose plugins.
- `.zshrc` — minimal config for the `vscode` user; activates mise. Copied into the image by the Dockerfile.
- `docker-init.sh` — ENTRYPOINT of the `did` stage: prepares the runtime (cgroup v2 nesting, tmpfs `/tmp`, securityfs, `--make-rshared /`), starts `dockerd` (`--host=unix:///var/run/docker.sock --group docker`) if no socket is present, then drops privileges to the `vscode` user (`setpriv`) and `exec`s the container command. Needs a privileged container at runtime.
- `MISE_VERSION` / `UV_VERSION` / `DOCKER_VERSION` — pinned versions of the tools. Sources of truth for the auto-update workflow and the Dockerfile build args.
- Image versioning comes from the GitHub release tag (computed by `auto-release.yml` from the latest release via the API); there is no `VERSION` file.
- `.github/workflows/` — the automation (below).
- `.github/platforms.yml` — build platforms (`linux/amd64`, `linux/arm64`), parsed with `yq` in the build workflow.

## The update pipeline (event chain)

1. `auto-update-mise.yml` / `auto-update-uv.yml` / `auto-update-docker.yml` — daily schedule. Compare upstream latest release against the version file; if newer, open a PR with the `auto-update` label. A mismatch or no update is a no-op (output `release=FALSE`, PR step skipped).
2. `auto-merge.yml` — squash-auto-merge for dependabot PRs and any PR with the `auto-update` label.
3. `auto-release.yml` — on merged auto-update PRs (or `workflow_dispatch`): compute the next patch version from the latest GitHub release via the API, then `gh release create` (API call, no commit/push to `main`).
4. `docker-image.yml` — on `release: published`: build multi-arch, push tags. On plain PRs: build only, no push.

## Non-obvious things that break silently

- **`curl ... | sh` masks curl failures in the Dockerfile.** A pipeline's exit status is the *last* command's (`sh`), which exits 0 on empty stdin — so a 404 from `curl -f` yields a "successful" build that installed nothing. Always download to a temp file (`curl -fsSL URL -o /tmp/x; sh /tmp/x; rm /tmp/x`) and verify the tool runs after (`uv --version`).
- **`jq -r .tag_name` on a rate-limited/error API body prints the literal string `null`**, which the old version check then mistook for a real version and wrote into `MISE_VERSION`/`UV_VERSION`. Fetch with `curl -f`, read with `jq -r '.tag_name // empty'`, and treat an empty result as a no-op (`release=FALSE`) — a failed fetch must never open a bump PR.
- **The auto-update flows must `git add` the version file before committing.** `auto-update-*.yml` write the new version, `git switch -c` a branch, then commit — omitting `git add MISE_VERSION` / `git add UV_VERSION` fails with `changes not staged for commit` and errors the run.
- **The auto-update flows must push the new branch with `-u origin HEAD`.** A freshly created branch has no upstream, so a bare `git push` fails with `the current branch ... has no upstream branch`.
- **The auto-update flows must be idempotent and reuse existing branches.** The branch name is deterministic (`mise-upgrade-$VERSION`). Re-running collides with a leftover remote branch and `git push` is rejected (`fetch first`). The flow must (1) skip if an open PR for that branch already exists, and (2) reuse the branch if it already exists — `git fetch` + `git switch` + `git pull --ff-only` (not `git switch -c`), else create it fresh.
- **uv version pin goes in the URL path**, not an env var: `curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" -o /tmp/uv-install.sh; sh /tmp/uv-install.sh`. uv's installer hardcodes its version into the script; `UV_VERSION=... sh` is ignored.
- mise's installer *does* honor `MISE_VERSION` (and strips the `v` itself).
- **The `did` stage must not use Debian's `docker.io` package.** trixie's `docker.io` lags upstream by many releases (security postures included) and ships no buildx/compose plugins. It installs `docker-ce`/`docker-ce-cli` from the official `download.docker.com` repo. The version is pinned via `apt-cache madison` matching `5:${DOCKER_VERSION}` (Docker's Debian packages carry an `5:` epoch prefix), so a `DOCKER_VERSION` bump must land in the repo before the package exists or the build fails.
- **dockerd's socket appears before the daemon is ready.** `docker-init.sh` waits on `docker info`, not on the socket file's existence — dockerd binds the socket before network setup, and a daemon that dies there (e.g. iptables without privileges) leaves a stale socket that a `[ -S ]` check would mistake for success. Run the `did` image with `--privileged`; anything less makes dockerd fail on iptables and the init dumps the dockerd log and exits.
- The GitHub App token action is `actions/create-github-app-token@v3` — the old `create-github-generate-token` name does not exist and fails at workflow parse. The input is `client-id` (an alias for the App ID — `app-id` is deprecated and emits a warning).
- One GitHub App for everything: `APP_ID` + `APP_PRIVATE_KEY`. No separate merge app.
- `docker-image.yml` reads the version from the release event (`github.event.release.tag_name`) — the release is created before the build workflow runs, so the tag is always present. `MISE_VERSION` / `UV_VERSION` / `DOCKER_VERSION` still come from the files at checkout; do not bump versions in the build workflow.

## Conventions

- **Branch protection is enabled on `main` — nothing is pushed to it directly. Every change goes through a new branch + pull request.** The auto-update flows follow this same path (feature branch → commit → push → PR).

- Version files are single-line, no trailing spaces: `MISE_VERSION` keeps its `v` prefix (`v2026.8.0`), `UV_VERSION` and `DOCKER_VERSION` do not (`0.12.0`, `29.7.2`).
- PRs opened by automation carry the `auto-update` label and are assigned to `${{ github.repository_owner }}` (the workflow uses a template expression so it stays valid across forks).
- Image tags: `:${VERSION}`, `:${VERSION}-mise-${MISE_VERSION}-uv-${UV_VERSION}`, `:latest`, where `VERSION` is the release tag. The DiD variant gets the same tags on `${IMAGE_NAME}-did`. Both images are built in the same matrix job, each from its own `--target` (`base` / `did`) of the same Dockerfile — the `did` stage `FROM base` resolves in the same solve, so the base never has to exist on a registry for the DiD build.
- Release tags carry a `v` prefix (`v0.1.0`); image tags do not (`0.1.0`). `docker-image.yml` strips the `v` via `${TAG#v}`.
- Release bump level depends on the trigger: mise/uv/docker updates (`auto-update` label) bump **minor**; dependabot docker base image updates (and manual `workflow_dispatch`) bump **patch**.
- Release notes are auto-generated (`--generate-notes`).

## Required secrets/vars

Secrets: `APP_ID`, `APP_PRIVATE_KEY` (GitHub App), `DOCKER_HUB_DEPLOY_KEY`. Vars: `DOCKER_HUB_USERNAME`, `IMAGE_NAME` (both optional, sensible defaults).

## README writing style

Follow the style of the owner's other repos (github.com/mietzen) — the README must not read like it was written by an AI. Rules learned from those repos:

- Opening line states what the image does, in one sentence, plain. E.g. `docker-redsocks-proxy`: "With this container, you can redirect all TCP traffic through a SOCKS5 proxy..."
- No AI-tell headings like `What's inside`, `How updates flow`, `Features and benefits`. Use the owner's actual headings: `## Features:`, `## Usage`, `## Preparation`, `## How it works`, `## Docker Compose`.
- Short sections, few words. No filler adjectives (`robust`, `seamless`, `streamlined`), no em-dash embellishment, no emojis, no "get started" fluff.
- Code blocks carry the weight: config snippets, commands, tables. Tables for secrets/vars.
- `[Optional] ...` callout style for optional setup (see `docker-ci-template`).
- Before writing, check the owner's repo list for the closest analog repo and mirror its section names and tone.

## Validating changes

- Dockerfile: build locally with the version files as build args; run the image and check mise/uv versions, the `vscode` user, and the sudo rule.
- Dockerfile `did` target: build locally with `--target did` (resolves `FROM base` in-solve); run privileged (`docker run --privileged`) and check `docker info`, a nested `docker run`, `docker compose version`, and that the exec'd command runs as `vscode` (it starts as root only to boot dockerd, then `setpriv`s down).
- Workflows: the YAML must parse. Check version output names (`version`/`mise`/`uv`) match what the build step consumes.
