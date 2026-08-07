FROM --platform=$TARGETPLATFORM ghcr.io/openclaw/openclaw:2026.7.1-slim@sha256:6a31d44b2944e7adcd2b582bf6fb463111264ebca97a0201795b799135bd102c

# Every plugin below is an external ClawHub/npm package, not bundled in any official tag
# (verified absent from both /app/dist/extensions and /app/extensions in this image). OpenClaw
# otherwise tries to `npm install` them at gateway startup, which fails under a locked-down
# deployment (read-only rootfs, no ClawHub/npm egress) and is treated as a fatal startup
# migration for a *configured* channel/plugin. Installing them here, where registry egress
# exists, removes that runtime dependency. They're baked in so they're *available*; each stays
# dormant unless the deployment's config allowlists it (a non-empty `plugins.allow` is a hard
# gate -- an installed-or-bundled plugin absent from it never loads).
#   brave-plugin            - Brave Search web-search provider (needs BRAVE_API_KEY)
#   diagnostics-prometheus  - Prometheus metrics exporter
#   lobster                 - action-approval gating
#   memory-lancedb          - LanceDB-backed memory store
#   searxng-plugin          - self-hosted SearXNG web-search provider (no third-party API key;
#                             unlike key-free providers it can win provider auto-detection)
#   voice-call              - Twilio/Telnyx/Plivo outbound calling. Baked in but NOT wired yet:
#                             notify-mode outbound needs no public webhook (the initial <Say>
#                             TwiML ships inside the create-call request), so it suits this
#                             ingress-free gateway -- but the plugin exposes no destination
#                             allowlist, so a deployment enabling it must pin `toNumber` and
#                             keep the `voice_call` tool denied to the agent.
#   whatsapp                - WhatsApp/Baileys channel
# NOT installed here, deliberately: duckduckgo, document-extract, web-readability and xai are
# ALREADY bundled in the base image under /app/dist/extensions. They need allowlisting in the
# deployment config, not an install -- don't add redundant install lines for them. (xai in
# particular cannot be "removed" from this image without deleting an upstream extension
# directory; it is inert while the deployment leaves it out of `plugins.allow`.)
# Pin exact plugin versions for reproducibility/supply-chain. `npm:<scoped>@<version>` is the
# doc-confirmed form for scoped packages with an explicit version; `--pin` records the resolved
# exact version, and `--force` confirms the non-ClawHub (npm) source non-interactively during
# the build. Pinned to 2026.7.1 to match the base image + the deployed app version. (These are
# the same @openclaw/* artifacts ClawHub serves -- ClawHub installs fall back to npm anyway.)
# Do NOT switch these to `clawhub:` to chase supply-chain metadata: the npm source already
# records an integrity hash. The `plugins.installs_missing_integrity` finding from
# `openclaw status --deep` is not caused by the install source -- see the assertion below and
# the README for what actually drops those hashes.
RUN openclaw plugins install npm:@openclaw/brave-plugin@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/diagnostics-prometheus@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/lobster@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/memory-lancedb@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/searxng-plugin@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/voice-call@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/whatsapp@2026.7.1 --pin --force

# Assert every install record above carries an integrity hash, so a regression in what the build
# records is caught here rather than surfacing later as the warn-level `status --deep` finding
# `plugins.installs_missing_integrity`. Nothing backfills integrity onto an existing record --
# the only documented remedy is reinstalling, which a deployed gateway cannot do (read-only
# rootfs, no registry egress, OPENCLAW_OFFLINE=1) -- so build time is the only place it can be
# guaranteed. This also pins down what the npm source actually records, which is the evidence
# the missing-integrity investigation needs.
COPY --chmod=644 assert-plugin-integrity.mjs /tmp/assert-plugin-integrity.mjs
RUN openclaw plugins inspect --all --json > /tmp/plugins.json \
    && node /tmp/assert-plugin-integrity.mjs /tmp/plugins.json \
    && rm -f /tmp/plugins.json /tmp/assert-plugin-integrity.mjs

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
