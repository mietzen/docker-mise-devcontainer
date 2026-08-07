# AGENTS.md

## What this repo is

A Docker Hub base image for vscode devcontainers. The repo is a build pipeline: it tracks three upstream inputs (Debian base image, mise, uv), builds a multi-arch image from them, and publishes it — fully automated.

## Repo layout

- `Dockerfile` — single-stage `debian:trixie-slim` image. `ARG MISE_VERSION` / `ARG UV_VERSION` are required build args. Installs mise (with node@24 + usage) and uv pinned to those args, oh-my-zsh, non-root `vscode` user, `.persist` mountpoint, scoped sudo.
- `.zshrc` — minimal config for the `vscode` user; activates mise. Copied into the image by the Dockerfile.
- `MISE_VERSION` / `UV_VERSION` — pinned versions of the tools. The source of truth for the auto-update workflow and the Dockerfile build args.
- `VERSION` — semver image release. Bumped by `release.yml` on every merged auto-update PR.
- `.github/workflows/` — the automation (below).
- `.github/platforms.json` — build platforms (`linux/amd64`, `linux/arm64`).

## The update pipeline (event chain)

1. `auto-update-mise.yml` / `auto-update-uv.yml` — daily schedule. Compare upstream latest release against the version file; if newer, open a PR with the `auto-update` label. A mismatch or no update is a no-op (output `release=FALSE`, PR step skipped).
2. `auto-merge-dependabot.yml` — squash-auto-merge for dependabot PRs and any PR with the `auto-update` label.
3. `release.yml` — on merged auto-update PRs: bump `VERSION` (patch), commit, push, `gh release create`.
4. `docker-image.yml` — on `release: published`: build multi-arch, push tags. On plain PRs: build only, no push.

## Non-obvious things that break silently

- **uv version pin goes in the URL path**, not an env var: `curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh"`. uv's installer hardcodes its version into the script; `UV_VERSION=... sh` is ignored.
- mise's installer *does* honor `MISE_VERSION` (and strips the `v` itself).
- The GitHub App token action is `actions/create-github-app-token@v3` — the old `create-github-generate-token` name does not exist and fails at workflow parse.
- One GitHub App for everything: `APP_ID` + `APP_PRIVATE_KEY`. No separate merge app.
- `docker-image.yml` reads `VERSION`, `MISE_VERSION`, `UV_VERSION` from the files at checkout — the release event fires after `release.yml` has already committed the bump, so `cat VERSION` is correct; do not bump again in the build workflow.

## Conventions

- Version files are single-line, no trailing spaces: `MISE_VERSION` keeps its `v` prefix (`v2026.8.0`), `UV_VERSION` does not (`0.12.0`).
- PRs opened by automation carry the `auto-update` label and are assigned to `@mietzen`.
- Image tags: `:${VERSION}`, `:${VERSION}-mise-${MISE_VERSION}-uv-${UV_VERSION}`, `:latest`.
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

- Dockerfile: build locally with the version files as build args; run the image and check mise/uv/node/usage versions, the `vscode` user, and the sudo rule.
- Workflows: the YAML must parse. Check version output names (`version`/`mise`/`uv`) match what the build step consumes.
