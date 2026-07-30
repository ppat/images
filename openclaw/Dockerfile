FROM --platform=$TARGETPLATFORM ghcr.io/openclaw/openclaw:2026.7.1-slim@sha256:6a31d44b2944e7adcd2b582bf6fb463111264ebca97a0201795b799135bd102c

# Every plugin below is an external ClawHub/npm package, not bundled in any official tag
# (verified absent from both /app/dist/extensions and /app/extensions in this image). OpenClaw
# otherwise tries to `npm install` them at gateway startup, which fails under a locked-down
# deployment (read-only rootfs, no ClawHub/npm egress) and is treated as a fatal startup
# migration for a *configured* channel/plugin. Installing them here, where registry egress
# exists, removes that runtime dependency. They're baked in so they're *available*; each stays
# dormant unless the deployment's config allowlists it (a non-empty `plugins.allow` is a hard
# gate -- an installed-or-bundled plugin absent from it never loads).
#   whatsapp                - WhatsApp/Baileys channel
#   diagnostics-prometheus  - Prometheus metrics exporter
#   memory-lancedb          - LanceDB-backed memory store
#   lobster                 - action-approval gating
#   brave-plugin            - Brave Search web-search provider (needs BRAVE_API_KEY)
#   searxng-plugin          - self-hosted SearXNG web-search provider (no third-party API key;
#                             unlike key-free providers it can win provider auto-detection)
#   diffs                   - read-only diff viewer / file renderer for agents
#   voice-call              - Twilio/Telnyx/Plivo outbound calling. Baked in but NOT wired yet:
#                             notify-mode outbound needs no public webhook (the initial <Say>
#                             TwiML ships inside the create-call request), so it suits this
#                             ingress-free gateway -- but the plugin exposes no destination
#                             allowlist, so a deployment enabling it must pin `toNumber` and
#                             keep the `voice_call` tool denied to the agent.
# NOT installed here, deliberately: duckduckgo, document-extract, web-readability and xai are
# ALREADY bundled in the base image under /app/dist/extensions. They need allowlisting in the
# deployment config, not an install -- don't add redundant install lines for them.
# Pin exact plugin versions for reproducibility/supply-chain. `npm:<scoped>@<version>` is the
# doc-confirmed form for scoped packages with an explicit version; `--pin` records the resolved
# exact version, and `--force` confirms the non-ClawHub (npm) source non-interactively during
# the build. Pinned to 2026.7.1 to match the base image + the deployed app version. (These are
# the same @openclaw/* artifacts ClawHub serves -- ClawHub installs fall back to npm anyway.)
RUN openclaw plugins install npm:@openclaw/whatsapp@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/diagnostics-prometheus@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/memory-lancedb@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/lobster@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/brave-plugin@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/searxng-plugin@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/diffs@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/voice-call@2026.7.1 --pin --force

# npm-source installs land plugin package state (npm/projects/*) and the pinned install records
# under $OPENCLAW_DATA_DIR (defaults to /home/node/.openclaw) -- exactly the path a deployment
# mounts an (initially empty) PVC over for gateway state, which shadows everything installed
# above. Keep an immutable seed copy of the whole data dir for docker-entrypoint.sh to restore
# missing entries into the mounted data dir at container start.
RUN cp -a /home/node/.openclaw /home/node/.openclaw-seed

COPY --chown=node:node --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Base image ENTRYPOINT (tini -s --) is left untouched for correct PID 1 signal handling and
# stays PID 1. The upstream gateway command now lives in CMD (explicit/overridable) instead of
# being hardcoded in the entrypoint script, which seeds state/config then `exec "$@"`s it.
CMD ["/usr/local/bin/docker-entrypoint.sh", "node", "openclaw.mjs", "gateway"]
