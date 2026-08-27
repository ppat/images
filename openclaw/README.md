# openclaw

An [OpenClaw](https://docs.openclaw.ai/) gateway image, built from the `openclaw` npm package
onto `node:24-trixie-slim`, with seven plugins installed at build time:

| Plugin | Purpose |
| --- | --- |
| `@openclaw/brave-plugin` | Brave Search web-search provider (needs `BRAVE_API_KEY`) |
| `@openclaw/diagnostics-prometheus` | Prometheus metrics exporter |
| `@openclaw/lobster` | Action-approval gating |
| `@openclaw/memory-lancedb` | LanceDB-backed long-term memory store |
| `@openclaw/searxng-plugin` | Self-hosted SearXNG web-search provider (no third-party key) |
| `@openclaw/voice-call` | Twilio/Telnyx/Plivo calling (available, not wired -- see below) |
| `@openclaw/whatsapp` | WhatsApp/Baileys channel |

No official OpenClaw distribution bundles these -- they're external ClawHub/npm packages that
OpenClaw otherwise installs itself the first time a gateway references them, which requires a
writable home directory and network access to ClawHub/npm at startup. This image installs them
ahead of time so a gateway with a read-only root filesystem and no outbound network access can
still use them. Only the WhatsApp channel is expected to be on by default; everything else is
available but inert until a deployment's config allowlists it -- a non-empty `plugins.allow` is a
hard gate, so an installed plugin missing from it never loads.

## Why this isn't built on `ghcr.io/openclaw/openclaw`

The upstream image is itself `node:24-bookworm-slim`, so nothing about it is exotic -- but a
published upstream tag is built once and its OS layers are never refreshed, so its digest
accumulates OS CVEs for as long as the tag exists. Building from the npm package onto a base
pinned in this repo puts the image on this repo's own Renovate digest-bump cadence, and every
bump republishes it.

Two consequences worth knowing:

- **The install is deterministic.** The npm package ships `npm-shrinkwrap.json`, so the
  dependency tree resolves identically on every build -- which layering onto a prebuilt image
  never gave us.
- **Two bundled extensions are deliberately absent.** Upstream's published tag adds `codex` and
  `diagnostics-otel` on top of the package's bundled set via a build arg. Neither is used here,
  and `diagnostics-prometheus` above covers the metrics role `diagnostics-otel` would fill.
  Everything else upstream bundles is in the npm package and therefore in this image.

## Plugins deliberately *not* installed here

`duckduckgo`, `document-extract`, `web-readability` and `xai` are already bundled in the npm
package under `dist/extensions`. They need allowlisting in the deployment config, not an
install -- don't add redundant install lines for them.

## OS packages

`ca-certificates`, `hostname`, `openssl`, `tini`. Every native module in the tree -- LanceDB,
tree-sitter, node-pty, sqlite-vec -- ships a prebuilt binary satisfied by the C/C++ runtime
already in the base, and plugin installs run with a hardcoded `--ignore-scripts`, so no compiler
toolchain is involved in any of this.

- **`ca-certificates`**: the base ships no CA bundle, so nothing can speak TLS -- to npm at build
  time, or to any model provider at runtime -- without it.
- **`hostname`**: already present without being asked for -- ships in `node:24-trixie-slim`
  itself. Listed here explicitly anyway so a future base-image change can't silently drop it out
  from under this image; the fact that this line is currently redundant is not a reason to
  delete it as cleanup.
- **`openssl`**: also already present without being asked for -- arrives as a hard `Depends:` of
  `ca-certificates` above. Listed for the same stated-not-inherited reason as `hostname`, and
  unlike `hostname` it's genuinely on the gateway's own path (`resolveSystemBin("openssl")`, used
  for TLS cert generation in both the gateway and the proxy CLI).
- **`tini`**: PID 1; the gateway supervises a respawned child, so reaping is load-bearing, not
  decor.

`curl`, `git`, `lsof`, `procps` and `python3` are the five packages upstream installs that stay
out deliberately. None sit on the gateway's startup or steady-state path; each buys an operator
convenience or a skill probe this deployment doesn't use, at a measured cost that wasn't judged
worth it -- Trivy HIGH+CRITICAL across the four non-`python3` packages ran 33 to 72 on this base,
with `git` alone (and the Perl/GnuTLS dependency closure it drags in) responsible for most of
that. Two of the five change observable behaviour, not just diagnostics, and are live conditions
worth knowing about rather than settled history:

- **`lsof`**: without it, a second gateway contending for a busy port logs `Port is in use but
  process details are unavailable (install lsof or run as an admin user)` instead of naming the
  blocking process. Every call site catches the missing binary and degrades to warn-and-skip, and
  both consumers (stale-gateway takeover on startup, `gateway restart` health attribution) are
  unreachable with one gateway per pod -- this holds only while nothing puts two gateways in one
  network namespace.
- **`procps`**: `process-reaper`'s Linux path shells out to `ps` to reap orphaned ACP agent
  process trees; its caller catches the failure and returns a `skippedReason` instead of
  throwing. No ACP agent is installed today, so this stays dropped -- but that's an argument from
  the deployment's current shape, not from the code. Adding a coding-agent skill
  (`claude`/`codex`/`opencode`) means orphans go unreaped.

`openclaw doctor` reports two more missing requirements here than on the upstream image
(`notion` wants `curl` or `ntn`, `python-debugpy` wants `python3`) -- both are skill requirement
probes for skills that don't belong on this gateway, so the count difference is expected, not a
defect. If a deployment turns out to need one of the five, add it back as a named line with its
reason rather than restoring the set.

## `voice-call` caveats

Baked in for availability; wiring is left to the deployment. Two things to know before
enabling it:

- **Outbound notify mode needs no public webhook.** Twilio notify-mode calls carry their
  initial `<Say>` TwiML inside the create-call request, so a gateway with no public ingress can
  still place alert calls. Inbound calls, multi-turn conversation, status callbacks and
  realtime media streams *do* require a publicly reachable webhook URL.
- **There is no outbound destination allowlist.** The `voice_call` tool takes a free-form `to`
  argument, so an agent holding it can dial arbitrary numbers. A deployment enabling this should
  pin `toNumber`, add `voice_call` to `tools.deny`, and drive alerts from its automation layer
  via the `voicecall.initiate` gateway RPC with `to` omitted (it falls back to `toNumber`).

## Entrypoint wrapper

`tini -s --` is `ENTRYPOINT`/PID 1; `docker-entrypoint.sh` is invoked via `CMD` and does four
things before `exec`-ing the gateway command:

- **State seeding**: restores the build-time plugin/state seed (`/home/node/.openclaw-seed`)
  into the state dir via `cp -n`, so a deployment mounting external storage (PVC, bind mount)
  over that dir doesn't shadow what's baked into the image, while anything an operator already
  persisted there wins. The state dir is resolved the same way the gateway resolves it:
  `OPENCLAW_STATE_DIR`, else the directory holding `OPENCLAW_CONFIG_PATH`, else
  `$HOME/.openclaw`. (`OPENCLAW_DATA_DIR` is not a variable OpenClaw reads -- honouring it here
  would seed one directory while the gateway read another.)
- **Config seeding**: if both `OPENCLAW_CONFIG_SEED` (e.g. a read-only ConfigMap mount) and
  `OPENCLAW_CONFIG_PATH` are set and the target doesn't already exist, copies the seed to the
  config path and `chmod 600`s it, so the gateway's own CLI can write the file back (channels
  login, doctor) without hitting `EBUSY` against a read-only mount. This is a no-op when
  `OPENCLAW_CONFIG_SEED` is unset. Copy-if-absent means an in-place edit in a writable volume
  always wins.
- **`umask 077`**: everything the gateway *creates* this boot lands owner-only (files 600, dirs
  700), satisfying OpenClaw's `fs.config.perms_world_readable` audit check and keeping fresh
  state tight.
- **State perms re-tighten**: on a Kubernetes `fsGroup`-mounted PVC the kubelet re-adds group
  `rw` to every existing file at each mount (before this container starts), which `umask` can't
  prevent for state persisted from a prior boot -- so the entrypoint recursively `chmod go-rwx`s
  the sensitive `<state>/credentials` and `<state>/agents` trees on every start (uid 1000 owns
  them, so it keeps owner access). This is what makes the fix stick across restarts and clears
  `fs.credentials_dir.perms_writable` / `fs.auth_profiles.perms_writable` /
  `fs.sessions_store.perms_readable`. The state-dir root stays group-writable (kubelet-owned
  mount point, not chmod-able by uid 1000) and remains audit-suppressed by the deployment's
  config.

The gateway is started through the `openclaw` CLI on `PATH` rather than
`node openclaw.mjs gateway`, which only resolved because the upstream base image set `WORKDIR`
to its application directory.

## Architectures

`linux/amd64` only, unlike the repo's other (multi-arch) images. `@openclaw/memory-lancedb`
carries a large native library that makes the emulated (QEMU) `arm64` build exceed this image's
build timeout; the target homelab node is x64/amd64, so `arm64` isn't built. Restore
`linux/amd64,linux/arm64` in `test-build-openclaw.yaml`/`publish-openclaw.yaml` if a native
`arm64` builder becomes available.

## Security scanning

`scan-openclaw.yaml` runs Trivy, Dockle and an SBOM generator against this image on every PR
touching it and weekly on a schedule, currently report-only (findings surface in PR logs and the
Security tab without failing a build). Accepted findings are documented in the repo-root
`.trivyignore`.
