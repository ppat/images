# openclaw

An [OpenClaw](https://docs.openclaw.ai/) gateway image, built on top of the official
[`ghcr.io/openclaw/openclaw`](https://github.com/openclaw/openclaw) `-slim` tag, with eight
plugins installed at build time:

| Plugin | Purpose |
| --- | --- |
| `@openclaw/whatsapp` | WhatsApp/Baileys channel |
| `@openclaw/diagnostics-prometheus` | Prometheus metrics exporter |
| `@openclaw/memory-lancedb` | LanceDB-backed long-term memory store |
| `@openclaw/lobster` | Action-approval gating |
| `@openclaw/brave-plugin` | Brave Search web-search provider (needs `BRAVE_API_KEY`) |
| `@openclaw/searxng-plugin` | Self-hosted SearXNG web-search provider (no third-party key) |
| `@openclaw/diffs` | Read-only diff viewer / file renderer for agents |
| `@openclaw/voice-call` | Twilio/Telnyx/Plivo calling (available, not wired -- see below) |

No official OpenClaw tag bundles these plugins -- they're external ClawHub/npm packages
that OpenClaw otherwise installs itself the first time a gateway references them, which
requires a writable home directory and network access to ClawHub/npm at startup. This image
installs them ahead of time so a gateway with a read-only root filesystem and no outbound
network access can still use them. Only the WhatsApp channel is expected to be on by default;
everything else is available but inert until a deployment's config allowlists it -- a non-empty
`plugins.allow` is a hard gate, so an installed plugin missing from it never loads.

## Plugins deliberately *not* installed here

`duckduckgo`, `document-extract`, `web-readability` and `xai` are already bundled in the base
image under `/app/dist/extensions`. They need allowlisting in the deployment config, not an
install -- don't add redundant install lines for them.

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

`docker-entrypoint.sh` (invoked via `CMD`, with the base image's `tini -s --` staying PID 1 as
`ENTRYPOINT`) does four things before `exec`-ing the upstream gateway command:

- **State seeding**: restores the build-time plugin/state seed (`/home/node/.openclaw-seed`)
  into the mounted state dir (`OPENCLAW_STATE_DIR`/`OPENCLAW_DATA_DIR`, default
  `/home/node/.openclaw`) via `cp -n`, so a deployment mounting external storage (PVC, bind
  mount) over that dir doesn't shadow what's baked into the image, while anything an operator
  already persisted there wins.
- **Config seeding**: if both `OPENCLAW_CONFIG_SEED` (e.g. a read-only ConfigMap mount) and
  `OPENCLAW_CONFIG_PATH` are set and the target doesn't already exist, copies the seed to the
  config path and `chmod 600`s it, so the gateway's own CLI can write the file back (channels
  login, doctor) without hitting `EBUSY` against a read-only mount. This is a no-op when
  `OPENCLAW_CONFIG_SEED` is unset, so it's backwards-compatible with deployments that seed
  config another way (e.g. a separate init container). Copy-if-absent means an in-place edit in
  a writable volume always wins.
- **`umask 077`**: everything the gateway *creates* this boot lands owner-only (files 600, dirs
  700), satisfying OpenClaw's `fs.config.perms_world_readable` audit check and keeping fresh
  state tight.
- **State perms re-tighten**: on a Kubernetes `fsGroup`-mounted PVC the kubelet re-adds group
  `rw` to every existing file at each mount (before this container starts), which `umask` can't
  prevent for state persisted from a prior boot — so the entrypoint recursively `chmod go-rwx`s
  the sensitive `<state>/credentials` and `<state>/agents` trees on every start (uid 1000 owns
  them, so it keeps owner access). This is what makes the fix stick across restarts and clears
  `fs.credentials_dir.perms_writable` / `fs.auth_profiles.perms_writable` /
  `fs.sessions_store.perms_readable`. The state-dir root stays group-writable (kubelet-owned
  mount point, not chmod-able by uid 1000) and remains audit-suppressed by the deployment's
  config.

## Architectures

`linux/amd64` only, unlike the repo's other (multi-arch) images. `@openclaw/memory-lancedb`
carries a large native library that makes the emulated (QEMU) `arm64` build exceed this image's
build timeout; the target homelab node is x64/amd64, so `arm64` isn't built. Restore
`linux/amd64,linux/arm64` in `test-build-openclaw.yaml`/`publish-openclaw.yaml` if a native
`arm64` builder becomes available.
