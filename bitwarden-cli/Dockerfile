FROM --platform=$BUILDPLATFORM debian:bookworm-slim@sha256:6ac2c08566499cc2415926653cf2ed7c3aedac445675a013cc09469c9e118fdd AS builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/cache/debconf \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends wget unzip

# renovate: datasource=github-releases depName=bitwarden/clients extractVersion=^cli-v(?<version>.*)$
ARG BW_CLI_VERSION="2025.6.1"
WORKDIR /tmp
RUN --mount=type=tmpfs,target=/tmp \
    wget -nv --no-check-certificate "https://github.com/bitwarden/clients/releases/download/cli-v${BW_CLI_VERSION}/bw-linux-${BW_CLI_VERSION}.zip" -O /tmp/bw.zip && \
    unzip bw.zip && \
    mv /tmp/bw /bw
WORKDIR /

# =======================================================================================================================================
# Bitwarden CLI requires various libs not available under a small base image such as busybox/alpine.
FROM --platform=$TARGETPLATFORM debian:bookworm-slim@sha256:6ac2c08566499cc2415926653cf2ed7c3aedac445675a013cc09469c9e118fdd
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

COPY --from=builder --chown=root:root --chmod=755 /bw /bw
COPY --link --chown=root:root --chmod=755 entrypoint.sh /entrypoint.sh

ENV BW_HOST=""
ENV BW_USER=""
ENV BW_PASSWORD=""

ENTRYPOINT ["/entrypoint.sh"]
CMD [ "serve", "--hostname=0.0.0.0", "--port=8087" ]
