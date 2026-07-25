FROM --platform=$TARGETPLATFORM ghcr.io/openclaw/openclaw:2026.7.1-slim@sha256:6a31d44b2944e7adcd2b582bf6fb463111264ebca97a0201795b799135bd102c

# The WhatsApp/Baileys channel and diagnostics-prometheus plugins are external ClawHub/npm
# packages, not bundled in any official tag (verified absent from both /app/dist/extensions
# and /app/extensions in this image). OpenClaw otherwise tries to `npm install` them at
# gateway startup, which fails under a locked-down deployment (read-only rootfs, no ClawHub/
# npm egress) and is treated as a fatal startup migration for a *configured* channel plugin.
# Installing them here, where registry egress exists, removes that runtime dependency.
# Pin exact plugin versions for reproducibility/supply-chain. `npm:<scoped>@<version>` is the
# doc-confirmed form for scoped packages with an explicit version; `--pin` records the resolved
# exact version, and `--force` confirms the non-ClawHub (npm) source non-interactively during
# the build. Pinned to 2026.7.1 to match the base image + the deployed app version. (These are
# the same @openclaw/* artifacts ClawHub serves -- ClawHub installs fall back to npm anyway.)
RUN openclaw plugins install npm:@openclaw/whatsapp@2026.7.1 --pin --force && \
    openclaw plugins install npm:@openclaw/diagnostics-prometheus@2026.7.1 --pin --force

# `openclaw plugins install` lands packages under $OPENCLAW_DATA_DIR/extensions (the managed
# plugin root, defaults to ~/.openclaw/extensions) -- the same path operators typically mount
# a persistent volume over for gateway state. A freshly-mounted volume starts empty and would
# hide what was just installed above, so keep an immutable copy for docker-entrypoint.sh to
# reseed from at container start.
RUN cp -a /home/node/.openclaw/extensions /home/node/.openclaw-extensions.baked

COPY --chown=node:node --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Base image ENTRYPOINT (tini -s --) is left untouched for correct PID 1 signal handling;
# only CMD changes, to seed extensions before exec'ing the same upstream gateway command.
CMD ["/usr/local/bin/docker-entrypoint.sh"]
