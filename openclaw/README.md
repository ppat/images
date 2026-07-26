# openclaw

An [OpenClaw](https://docs.openclaw.ai/) gateway image, built on top of the official
[`ghcr.io/openclaw/openclaw`](https://github.com/openclaw/openclaw) `-slim` tag, with four
plugins installed at build time: the WhatsApp channel (`@openclaw/whatsapp`),
diagnostics-prometheus (`@openclaw/diagnostics-prometheus`), a LanceDB-backed memory store
(`@openclaw/memory-lancedb`), and action-approval gating (`@openclaw/lobster`).

No official OpenClaw tag bundles these plugins -- they're external ClawHub/npm packages
that OpenClaw otherwise installs itself the first time a gateway references them, which
requires a writable home directory and network access to ClawHub/npm at startup. This image
installs them ahead of time so a gateway with a read-only root filesystem and no outbound
network access can still use them. memory-lancedb and lobster are baked in and available but
not enabled unless a deployment's config turns them on.

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
