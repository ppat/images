# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A monorepo of independently-versioned, independently-released Docker images published to Docker
Hub as `ppatlabs/<image>` — currently `bitwarden-cli`, `freeradius-server`, and `tools` (see
[README.md](README.md) for the catalog). There is no shared application code or package manager;
each top-level directory is a self-contained image: `Dockerfile`, `metadata.yaml`, `README.md`,
plus whatever else that image needs (e.g. `entrypoint.sh`, `aqua.yaml`).

For the reasoning behind the CI/release structure and per-image trade-offs, see
[DESIGN.md](DESIGN.md). Most of this repo's commit history is Renovate-authored dependency bumps,
not hand-written changes — expect a typical task here to be a version bump, a small Dockerfile
edit, or adding a new image, not application feature work.

## Commands

### Build an image locally

```
docker build -t <image>:test ./<image>
```

Multi-arch build matching CI (requires buildx + binfmt for the non-native arch):

```
docker buildx build --platform linux/amd64,linux/arm64 ./<image>
```

### Lint

```
pre-commit run --all-files
```

Run one hook against specific files:

```
pre-commit run hadolint --files tools/Dockerfile
pre-commit run yamllint --files freeradius-server/metadata.yaml
```

Hooks (`.pre-commit-config.yaml`): standard pre-commit-hooks (large files, shebangs, private
keys, EOF/CRLF), `yamllint --strict`, `markdownlint-cli2 --fix`, `shellcheck`, and `hadolint`
(`--failure-threshold=warning`; DL3008/DL3018/DL4001/SC2155 are ignored repo-wide per
`.hadolint.yaml` — don't flag these). `commitlint` also runs as a hook but only at the
`commit-msg` stage, so it won't fire under `--all-files`.

### How a change is verified

There is no unit/integration test suite. Confidence comes from static analysis (the hooks above,
plus CI's `lint.yaml`, which mirrors them and adds a GitHub Actions linter) followed by an actual
build: on a PR touching `<image>/**`, `test-build-<image>.yaml` runs a real multi-arch
(`linux/amd64,linux/arm64`) `docker buildx build` via the shared `build-docker-image.yaml`
workflow (from the external `ppat/github-workflows` repo) — without pushing anywhere. A
successful build on both architectures **is** the test. There's no local equivalent of the
private-registry-cached CI build; the `docker buildx build` command above is the closest local
approximation. See [DESIGN.md](DESIGN.md#decisions-and-trade-offs) for why this repo relies on
build-as-test instead of a test suite.

### Commit messages

Conventional Commits, enforced by commitlint (`commitlint.config.js`) via both the `commit-msg`
pre-commit hook and CI (`lint.yaml` → commit-messages job). Header ≤ 120 chars. `scope` must be
one of the fixed values in `commitlint.config.js`'s `scope-enum`: empty, `aqua`, `bitwarden-cli`,
`build`, `dev-tools`, `freeradius-server`, `github-actions`, `release`, `renovate`, `tools`.

## Adding a new image

Follow the existing per-image pattern (any of `bitwarden-cli`/`freeradius-server`/`tools` is a
reference):

1. Create `<name>/Dockerfile`, `<name>/metadata.yaml` (`image_version`, `label_title`,
   `label_description`, `build_timeout` — read by `load-metadata.yaml`), `<name>/README.md`.
2. Copy an existing image's `.github/workflows/test-build-<image>.yaml` and
   `publish-<image>.yaml` pair, changing only the image name / context path. (These aren't a
   single parameterized matrix workflow because GitHub Actions `paths:` trigger filters must be
   static per file — see [DESIGN.md](DESIGN.md#decisions-and-trade-offs).)
3. Add `<name>` to the `scope-enum` in `commitlint.config.js`.
4. Add a row to the table in root [README.md](README.md).
5. If the image pins versions via `# renovate: datasource=... depName=...` comments, confirm
   Renovate's custom regex manager (`.github/renovate.json`) picks them up; add an
   image-specific rule set under `.github/renovate/` only if it needs non-default
   automerge/grouping behavior (see `image-updates-bitwarden-cli.json` /
   `image-updates-freeradius-server.json` for the pattern).

## Conventions specific to this repo

- Base images are pinned by digest (e.g. `debian:bookworm-slim@sha256:...`,
  `alpine:3.24.1@sha256:...`); builder stages use `--platform=$BUILDPLATFORM` and final stages
  use `$TARGETPLATFORM` to keep cross-compilation correct.
- A version pin only gets Renovate-managed if it carries a
  `# renovate: datasource=... depName=...` comment directly above the `ARG`/YAML key —
  omitting it silently opts that pin out of automated updates.
- `metadata.yaml` is the single source of truth for an image's version and labels; don't
  hardcode these in workflow files.
