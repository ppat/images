# =======================================================================================================================================
# Builder stage. Runs on the BUILD platform: everything it does is a network fetch plus a tar
# extraction, and Obsidian ships a per-arch plain tarball of its Electron app directory
# (obsidian-<ver>.tar.gz / obsidian-<ver>-arm64.tar.gz). Fetching the tarball rather than the
# AppImage is deliberate -- an AppImage has to either be executed (`--appimage-extract`, which
# needs a matching-arch interpreter and would therefore drag the arm64 build under QEMU
# emulation) or mounted via libfuse (which needs FUSE in the container). The tarball has neither
# problem and its contents are byte-identical to what the AppImage unpacks to, so the arm64
# image is assembled without emulating a single instruction here.
FROM --platform=$BUILDPLATFORM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818 AS builder
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /tmp

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Cache mount ids carry ${TARGETARCH}: buildx instantiates this stage once per target platform
# and cache mounts default to sharing=shared, so a single id would put two concurrent apt runs on
# the same /var/lib/apt and one of them would die on the lock.
RUN --mount=type=cache,target=/var/cache/apt,id=obsidian-cache-apt-builder-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=obsidian-cache-debconf-builder-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=obsidian-lib-apt-builder-${TARGETARCH} \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        ca-certificates \
        curl

# STABLE channel, deliberately. Obsidian also has a beta/insider channel (1.13.x at time of
# writing) and some community plugins already declare minAppVersion 1.13.0 -- Templater and
# QuickAdd among them -- so a future maintainer will eventually be tempted to bump this to beta to
# make a plugin load. Don't, without re-taking the decision: this container is the single writer
# of the authoritative vault and the component everything else in the system stands on, and
# tracking a pre-release channel there trades that stability for plugins whose value is to a human
# sitting at the GUI. The REST API plugin this image exists to serve declares minAppVersion 1.8.7,
# so the critical path has room to spare on stable.
# Renovate can't drift this onto beta on its own: insider builds are not published as GitHub
# releases in obsidianmd/obsidian-releases at all, so the datasource below only ever sees stable.
# renovate: datasource=github-releases depName=obsidianmd/obsidian-releases
ARG OBSIDIAN_VERSION="1.12.7"
RUN --mount=type=tmpfs,target=/tmp \
    case "${TARGETARCH}" in \
        amd64) ARCH_SUFFIX="" ;; \
        arm64) ARCH_SUFFIX="-arm64" ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /tmp/obsidian.tar.gz \
        "https://github.com/obsidianmd/obsidian-releases/releases/download/v${OBSIDIAN_VERSION}/obsidian-${OBSIDIAN_VERSION}${ARCH_SUFFIX}.tar.gz" && \
    mkdir -p /opt/obsidian && \
    tar -xzf /tmp/obsidian.tar.gz -C /opt/obsidian --strip-components=1 && \
    test -x /opt/obsidian/obsidian

# The Local REST API plugin is what the whole image exists to serve: it's the only way anything
# outside this container is allowed to touch the vault. Upstream publishes the three built plugin
# artifacts as GitHub release assets, so baking it in is a download, not a build from source.
# These land in a seed directory rather than straight into the vault because the vault is an
# externally-mounted volume at runtime -- see docker-entrypoint.sh for how the seed is applied.
# renovate: datasource=github-releases depName=coddingtonbear/obsidian-local-rest-api
ARG LOCAL_REST_API_VERSION="5.0.3"
RUN mkdir -p /opt/obsidian-seed/plugins/obsidian-local-rest-api && \
    for asset in main.js manifest.json styles.css; do \
        curl -fsSL -o "/opt/obsidian-seed/plugins/obsidian-local-rest-api/${asset}" \
            "https://github.com/coddingtonbear/obsidian-local-rest-api/releases/download/${LOCAL_REST_API_VERSION}/${asset}"; \
    done && \
    grep -q '"id": "obsidian-local-rest-api"' /opt/obsidian-seed/plugins/obsidian-local-rest-api/manifest.json

# The rest of the ratified community plugin set (ppat/images#538): Tasks and Dataview, and
# nothing else -- Templater, QuickAdd, Linter, Frontmatter Date Manager, Kanban, and any
# validation plugin were all considered and dropped; see the issue for why each one specifically.
# Fetched the same way as the REST API plugin above: prebuilt release assets into the seed, not
# built from source. Whether a given plugin ends up actually turned ON in a vault is decided at
# runtime, not here -- see docker-entrypoint.sh for why the REST API plugin and these two are
# seeded identically but enabled differently.
#
# minAppVersion checked against this image's pinned stable release (1.12.7) rather than assumed
# -- this is exactly the check that disqualified Templater and QuickAdd (both declare 1.13.0,
# today's beta/insider channel only). Tasks' latest release declares minAppVersion 1.8.7, well
# under 1.12.7.
# renovate: datasource=github-releases depName=obsidian-tasks-group/obsidian-tasks
ARG TASKS_VERSION="8.3.0"
RUN mkdir -p /opt/obsidian-seed/plugins/obsidian-tasks-plugin && \
    for asset in main.js manifest.json styles.css; do \
        curl -fsSL -o "/opt/obsidian-seed/plugins/obsidian-tasks-plugin/${asset}" \
            "https://github.com/obsidian-tasks-group/obsidian-tasks/releases/download/${TASKS_VERSION}/${asset}"; \
    done && \
    grep -q '"id": "obsidian-tasks-plugin"' /opt/obsidian-seed/plugins/obsidian-tasks-plugin/manifest.json

# Dataview's latest (and, as of this pin, only recent) release declares minAppVersion 0.13.11,
# also comfortably under 1.12.7. This is upstream's last release: no commits to `master` since
# 2025-04-08, so there is nothing newer to weigh -- see #538 ("Bases is primary, Dataview is
# minimised") for why it's kept anyway (inline task-line queries, which Bases cannot serve at
# all, being metadata-only) and for the residual that comes with depending on a dormant plugin.
# Note the manifest.json shipped inside this release still self-reports "version": "0.5.68" even
# though the release is tagged 0.5.70 -- an upstream packaging slip, confirmed against upstream's
# own versions.json (which maps 0.5.70 -> minAppVersion 0.13.11). Not a mismatch introduced here;
# don't "fix" it by re-pinning to 0.5.68, which is an older, different release.
# renovate: datasource=github-releases depName=blacksmithgu/obsidian-dataview
ARG DATAVIEW_VERSION="0.5.70"
RUN mkdir -p /opt/obsidian-seed/plugins/dataview && \
    for asset in main.js manifest.json styles.css; do \
        curl -fsSL -o "/opt/obsidian-seed/plugins/dataview/${asset}" \
            "https://github.com/blacksmithgu/obsidian-dataview/releases/download/${DATAVIEW_VERSION}/${asset}"; \
    done && \
    grep -q '"id": "dataview"' /opt/obsidian-seed/plugins/dataview/manifest.json


# =======================================================================================================================================
# Final stage. Debian rather than Alpine because Obsidian is a stock glibc-linked Electron build;
# it is not rebuilt against musl and there is no upstream musl artifact.
#
# Deliberately NOT derived from linuxserver/obsidian or sytone/obsidian-remote. Both are the same
# vanilla-binary pattern on a desktop-streaming base (selkies / KasmVNC) whose GUI ships with
# passwordless sudo -- linuxserver's own README says anyone reaching the GUI is root in the
# container. This container holds the read-write mount of the authoritative vault and its GUI is
# deliberately reachable for configuration and repair, so inheriting that is not acceptable.
# Building from scratch also drops s6-overlay, the start-as-root-then-drop dance, and a
# continuously-running desktop stack we don't need. The cost is owning the Electron dependency
# set below, which is bounded: it is exactly the DT_NEEDED list of /opt/obsidian/obsidian.
FROM --platform=$TARGETPLATFORM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

ARG OBSIDIAN_UID=1000
ARG OBSIDIAN_GID=1000

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# The libs below are the resolved Debian packages for the shared objects Obsidian's Electron
# binary actually links against (readelf -d /opt/obsidian/obsidian), plus:
#   - xvfb            the virtual display Obsidian renders into; there is no real one here
#   - x11vnc          installed but never started -- see README, "GUI access"
#   - python3-websocket  the Chrome DevTools Protocol client used by auto-trust.py speaks
#                     WebSocket; Debian packages websocket-client so nothing needs pip at build
#                     or run time
#   - libsecret-1-0   dlopen()ed by Electron's safeStorage; absent it logs and degrades
#   - fonts-dejavu-core  without any font installed the GUI renders empty boxes, which matters
#                     only for the occasional operator VNC session but is cheap to prevent
#   - tini            this image owns PID 1 (no s6-overlay, no init supervisor); tini reaps the
#                     Xvfb/auto-trust children the entrypoint backgrounds and forwards signals
RUN --mount=type=cache,target=/var/cache/apt,id=obsidian-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=obsidian-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=obsidian-lib-apt-${TARGETARCH} \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        ca-certificates \
        curl \
        fonts-dejavu-core \
        libasound2 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libatspi2.0-0 \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libexpat1 \
        libgbm1 \
        libglib2.0-0 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libsecret-1-0 \
        libudev1 \
        libx11-6 \
        libxcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        python3 \
        python3-websocket \
        tini \
        x11vnc \
        xvfb

RUN groupadd -g $OBSIDIAN_GID -r obsidian && \
    useradd -u $OBSIDIAN_UID \
        -g obsidian \
        --system \
        --create-home \
        --home-dir /home/obsidian \
        --no-log-init \
        --shell /usr/sbin/nologin \
        obsidian

COPY --from=builder --chown=root:root /opt/obsidian /opt/obsidian
COPY --from=builder --chown=root:root /opt/obsidian-seed /opt/obsidian-seed
COPY --chown=root:root --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY --chown=root:root --chmod=755 auto-trust.py /usr/local/bin/auto-trust.py

# /vault is the vault itself (a volume at runtime); /config is Electron's userData directory,
# which holds obsidian.json AND the localStorage LevelDB where Obsidian records that community
# plugins are trusted -- persist it or the auto-trust step (which is idempotent, so this is a
# cost not a correctness problem) has to redo its work on every restart.
RUN install -d -o obsidian -g obsidian -m 0750 /vault /config

ENV XDG_CONFIG_HOME=/config \
    XDG_CACHE_HOME=/home/obsidian/.cache \
    OBSIDIAN_VAULT_DIR=/vault \
    DISPLAY=:99 \
    OBSIDIAN_SCREEN_GEOMETRY=1920x1080x24

# 27124 is the plugin's HTTPS listener (self-signed cert generated by the plugin on first run).
# The plaintext listener on 27123 is left disabled -- the plugin defaults it off and nothing in
# this design needs it. Note that 9222 (Chrome DevTools Protocol, used by auto-trust.py) is
# NOT exposed and Chromium binds it to 127.0.0.1 only.
EXPOSE 27124

USER obsidian
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
