# OpenClaw is built here from its npm package onto a first-party base rather than layered onto
# ghcr.io/openclaw/openclaw. The upstream image is itself node:24-bookworm-slim, so this is a
# re-parenting rather than a port -- what it buys is rebuild cadence: upstream publishes a tag
# once and never refreshes its OS layers, so its digest accumulates OS CVEs indefinitely, while
# a base pinned here rides this repo's existing Renovate digest-bump automerge (which turns over
# roughly monthly) and republishes the image each time.
#
# node:24-trixie-slim, specifically:
#   - Node and npm must ship together. `openclaw plugins install` resolves npm by path, at
#     `dirname(process.execPath)/../lib/node_modules/npm/bin/npm-cli.js`, and explicitly refuses
#     a bare `npm` found on PATH -- so grafting just the node binary onto a bare OS base breaks
#     plugin installs and `doctor --fix` in a way nothing in a build would catch.
#   - No distro ships a usable Node for this app. openclaw.mjs hard-exits on an unsupported
#     runtime (engines: >=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0); Debian trixie packages
#     20.19.2 and Ubuntu 26.04 packages 22.22.1 -- the latter two patch releases below the floor.
#   - The official Node image republishes same-day when either Debian slim or Node itself moves,
#     which is faster than the distro bases turn over on their own.
FROM --platform=$TARGETPLATFORM node:24-trixie-slim@sha256:50c3b2f6988dfc307b86e5301d69611af31f4789bdf232863b07d3b02fe55ae0
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Every native module in the dependency tree (lancedb, tree-sitter-bash, node-pty, sqlite-vec)
# ships a prebuilt binary whose ELF NEEDED set is satisfied by libc6/libgcc-s1/libstdc++6, all
# already in trixie-slim, and plugin installs run with a hardcoded --ignore-scripts -- so none of
# the packages below are pulled in for a compiler toolchain; there isn't one reachable from this
# build even in principle.
#   ca-certificates  node:*-slim ships without a CA bundle; without it there is no TLS to npm at
#                    build time or to any model provider at runtime
#   hostname         already present without being asked for -- ships in node:24-trixie-slim
#                    itself. Listed here explicitly anyway so a future base-image change can't
#                    silently drop it out from under this image; the fact that this line is
#                    currently redundant is not a reason to delete it as cleanup
#   openssl          also already present without being asked for -- arrives as a hard
#                    `Depends:` of ca-certificates above. Listed here for the same
#                    stated-not-inherited reason as hostname, and unlike hostname it is genuinely
#                    on the gateway's own path (`resolveSystemBin("openssl")`, used for TLS cert
#                    generation in both the gateway and the proxy CLI)
#   tini             this image owns PID 1 (upstream's ENTRYPOINT is gone with its base) and the
#                    gateway supervises a respawned child, so a reaper is load-bearing, not decor
#
# curl, git, lsof, procps and python3 are the five packages upstream installs that stay out
# deliberately. None sit on the gateway's startup or steady-state path; each buys an operator
# convenience or a skill probe this deployment doesn't use, at a measured cost that was not judged
# worth it (Trivy HIGH+CRITICAL across the four non-python3 packages ran 33 -> 72 on this base,
# with `git` alone -- and the Perl/GnuTLS closure it drags in -- responsible for most of that).
# Two of the five change observable behaviour, not just diagnostics, and stay live conditions
# worth knowing about rather than settled history:
#   lsof     without it, a second gateway contending for a busy port logs "Port is in use but
#            process details are unavailable (install lsof or run as an admin user)" instead of
#            naming the blocking process. Every call site catches the missing binary and degrades
#            to warn-and-skip, and both consumers (stale-gateway takeover on startup, `gateway
#            restart` health attribution) are unreachable with one gateway per pod -- this holds
#            only while nothing puts two gateways in one network namespace.
#   procps   process-reaper's Linux path shells out to `ps` to reap orphaned ACP agent process
#            trees; its caller catches the failure and returns
#            skippedReason: "process-list-unavailable". No ACP agent is installed today, so this
#            stays dropped -- but that is an argument from the deployment's current shape, not
#            from the code. Add a coding-agent skill (claude/codex/opencode) and orphans go
#            unreaped.
# `openclaw doctor` reports two more missing requirements here than on the upstream image
# (`notion` wants curl-or-ntn, `python-debugpy` wants python3) -- both are skill requirement
# probes for skills that don't belong on this gateway, so the count difference is expected, not a
# defect. If a deployment turns out to need one of the five, add it back here as a named line
# with its reason, rather than restoring the whole set.
RUN --mount=type=cache,target=/var/cache/apt,id=openclaw-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=openclaw-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=openclaw-lib-apt-${TARGETARCH} \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        ca-certificates \
        hostname \
        openssl \
        tini

# The npm package carries dist/extensions with the same 70 bundled extensions the upstream image
# has, plus an npm-shrinkwrap.json -- so this install is dependency-for-dependency deterministic,
# which layering on a prebuilt image never was. Upstream's published tag adds two more extensions
# (codex, diagnostics-otel) via a build arg; both are deliberately omitted here, the metrics role
# of diagnostics-otel being covered by the diagnostics-prometheus plugin installed below.
#
# npm installs every platform variant of a package's optional native dependencies and nothing
# removes them afterwards. The prune below has to run inside this same RUN, not a later one: a
# Docker layer is an additive diff, so deleting a file in a *subsequent* RUN only writes a
# whiteout marker into that later layer -- the bytes from the unpruned install are already
# committed to this layer and still get pulled, stored and scanned regardless of what a later
# layer deletes. Root owns this tree (`/usr/local/lib/node_modules`), so the prune has to happen
# here too, before `USER node` -- the node user can't rm it later even if it wanted to.
# renovate: datasource=npm depName=openclaw
ARG OPENCLAW_VERSION="2026.7.1"
RUN --mount=type=cache,target=/root/.npm,id=openclaw-npm-root-${TARGETARCH} \
    npm install -g "openclaw@${OPENCLAW_VERSION}" && \
    openclaw --version && \
    find /usr/local/lib/node_modules -type d \
        \( -name '*-win32-*' \
        -o -name '*-darwin-*' \
        -o -name '*-linux-arm64*' \
        -o -name '*-linux-x64-musl*' \
        -o -name '*-linuxmusl-*' \
        -o -name '*-android-*' \
        -o -name '*-freebsd-*' \) \
        -prune -exec rm -rf {} +

USER node
WORKDIR /home/node

# Every plugin below is an external ClawHub/npm package, not bundled in the npm distribution
# (verified absent from dist/extensions). OpenClaw otherwise tries to `npm install` them at
# gateway startup, which fails under a locked-down deployment (read-only rootfs, no ClawHub/npm
# egress) and is treated as a fatal startup migration for a *configured* channel/plugin.
# Installing them here, where registry egress exists, removes that runtime dependency. They're
# baked in so they're *available*; each stays dormant unless the deployment's config allowlists
# it (a non-empty `plugins.allow` is a hard gate -- an installed-or-bundled plugin absent from it
# never loads).
#   brave-plugin            - Brave Search web-search provider (needs BRAVE_API_KEY)
#   diagnostics-prometheus  - Prometheus metrics exporter
#   lobster                 - action-approval gating
#   memory-lancedb          - LanceDB-backed memory store. Also the single largest thing in the
#                             image: one 153 MB prebuilt native library, about a third of the
#                             payload. Drop this plugin before optimising anything else here.
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
# ALREADY bundled in the npm package under dist/extensions. They need allowlisting in the
# deployment config, not an install -- don't add redundant install lines for them.
# Plugins track ${OPENCLAW_VERSION} rather than carrying their own pins: they are published in
# lockstep with the app, and a plugin with no matching version fails the build loudly here
# instead of drifting apart from the gateway silently. `npm:<scoped>@<version>` is the
# doc-confirmed form for scoped packages with an explicit version; `--pin` records the resolved
# exact version, and `--force` confirms the non-ClawHub (npm) source non-interactively.
#
# npm installs every platform variant of each plugin's optional native dependencies and nothing
# prunes them afterwards. In this tree that is not a rounding error: LanceDB alone ships darwin,
# win32 (x64 + arm64), linux-arm64 and musl builds of a ~140 MB library, none of which can load on
# a linux/amd64 glibc image, and the seed copy below would duplicate every byte. The find/prune
# below is the single largest size lever in this Dockerfile, and it MUST run inside this same RUN
# rather than a later one: a Docker layer is an additive diff, so deleting a file in a subsequent
# RUN only writes a whiteout marker into that later layer -- the bytes from the unpruned install
# are already committed to this layer and still get pulled, stored and scanned regardless.
# Splitting the prune back into its own RUN (it reads like a cleaner diff) silently re-inflates
# this layer from ~309 MB to ~1.11 GB without changing anything visible at runtime.
#
# The glob deliberately does not match `-linux-x64` (no suffix) or `-linux-x64-gnu`, which are the
# variants this image actually loads; the assertion afterwards is what turns a future upstream
# renaming from a silently broken memory plugin into a failed build.
RUN --mount=type=cache,target=/home/node/.npm,uid=1000,gid=1000,id=openclaw-npm-node-${TARGETARCH} \
    openclaw plugins install "npm:@openclaw/brave-plugin@${OPENCLAW_VERSION}" --pin --force && \
    openclaw plugins install "npm:@openclaw/diagnostics-prometheus@${OPENCLAW_VERSION}" --pin --force && \
    openclaw plugins install "npm:@openclaw/lobster@${OPENCLAW_VERSION}" --pin --force && \
    openclaw plugins install "npm:@openclaw/memory-lancedb@${OPENCLAW_VERSION}" --pin --force && \
    openclaw plugins install "npm:@openclaw/searxng-plugin@${OPENCLAW_VERSION}" --pin --force && \
    openclaw plugins install "npm:@openclaw/voice-call@${OPENCLAW_VERSION}" --pin --force && \
    openclaw plugins install "npm:@openclaw/whatsapp@${OPENCLAW_VERSION}" --pin --force && \
    find /home/node/.openclaw -type d \
        \( -name '*-win32-*' \
        -o -name '*-darwin-*' \
        -o -name '*-linux-arm64*' \
        -o -name '*-linux-x64-musl*' \
        -o -name '*-linuxmusl-*' \
        -o -name '*-android-*' \
        -o -name '*-freebsd-*' \) \
        -prune -exec rm -rf {} + && \
    test -n "$(find /home/node/.openclaw -type d -name 'lancedb-linux-x64-gnu' -print -quit)"

USER root

# Plugin installs land package state (npm/projects/*) and the pinned install records under the
# state dir, which resolves to $HOME/.openclaw here -- exactly the path a deployment mounts an
# (initially empty) PVC over for gateway state, which shadows everything installed above. Keep an
# immutable seed copy for docker-entrypoint.sh to restore missing entries into the mounted state
# dir at container start. Run as root with `cp -a` so the seed keeps node:node ownership.
RUN cp -a /home/node/.openclaw /home/node/.openclaw-seed

COPY --chown=root:root --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
USER node

# NODE_ENV is not set by the base image and the gateway is a production deployment; upstream sets
# it the same way.
ENV NODE_ENV=production

# tini runs as PID 1 with -s (subreaper) for signal forwarding and child reaping. The gateway
# command lives in CMD rather than being hardcoded into the entrypoint script so it stays
# explicit and overridable; the script seeds state/config, then `exec "$@"`s it. It is invoked
# through the `openclaw` CLI on PATH rather than `node openclaw.mjs`, which only resolved because
# upstream's base set WORKDIR to the app directory.
ENTRYPOINT ["/usr/bin/tini", "-s", "--"]
CMD ["/usr/local/bin/docker-entrypoint.sh", "openclaw", "gateway"]
