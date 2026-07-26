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
