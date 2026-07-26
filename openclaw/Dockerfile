FROM --platform=$TARGETPLATFORM ghcr.io/openclaw/openclaw:2026.7.1-slim@sha256:6a31d44b2944e7adcd2b582bf6fb463111264ebca97a0201795b799135bd102c

# The WhatsApp/Baileys channel, diagnostics-prometheus, memory-lancedb, and lobster plugins are
# external ClawHub/npm packages, not bundled in any official tag (verified absent from both
# /app/dist/extensions and /app/extensions in this image). OpenClaw otherwise tries to
# `npm install` them at gateway startup, which fails under a locked-down deployment (read-only
# rootfs, no ClawHub/npm egress) and is treated as a fatal startup migration for a *configured*
# channel/plugin. Installing them here, where registry egress exists, removes that runtime
# dependency. memory-lancedb is a LanceDB-backed memory store; lobster is action-approval
# gating -- both are baked in here so they're available, but neither is enabled unless a
# deployment's config turns it on.
# Pin exact plugin versions for reproducibility/supply-chain. `npm:<scoped>@<version>` is the
# doc-confirmed form for scoped packages with an explicit version; `--pin` records the resolved
# exact version, and `--force` confirms the non-ClawHub (npm) source non-interactively during
# the build. Pinned to 2026.7.1 to match the base image + the deployed app version. (These are
# the same @openclaw/* artifacts ClawHub serves -- ClawHub installs fall back to npm anyway.)
RUN openclaw plugins install npm:@openclaw/whatsapp@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/diagnostics-prometheus@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/memory-lancedb@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/lobster@2026.7.1 --pin --force

# npm-source installs land plugin package state (npm/projects/*) and the pinned install records
# under $OPENCLAW_DATA_DIR (defaults to /home/node/.openclaw) -- exactly the path a deployment
# mounts an (initially empty) PVC over for gateway state, which shadows everything installed
# above. Keep an immutable seed copy of the whole data dir for docker-entrypoint.sh to restore
# missing entries into the mounted data dir at container start.
RUN cp -a /home/node/.openclaw /home/node/.openclaw-seed

COPY --chown=node:node --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Base image ENTRYPOINT (tini -s --) is left untouched for correct PID 1 signal handling;
# only CMD changes, to seed extensions before exec'ing the same upstream gateway command.
CMD ["/usr/local/bin/docker-entrypoint.sh"]
