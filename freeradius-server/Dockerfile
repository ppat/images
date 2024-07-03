FROM --platform=$TARGETPLATFORM ubuntu:noble@sha256:2e863c44b718727c860746568e1d54afd13b2fa71b160f5cd9058fc436217b30 AS builder
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install build tooling
RUN --mount=type=cache,target=/var/cache/apt,id=var-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=var-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=var-lib-apt-${TARGETARCH} \
    --mount=type=tmpfs,target=/tmp \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        devscripts \
        equivs \
        git \
        quilt \
        gcc

# renovate: datasource=github-releases depName=FreeRADIUS/freeradius-server extractVersion=^(?<version>release_\\d+_\\d+_\\d+)$
ARG FREERADIUS_VERSION="3.2.3"
# Shallow clone the FreeRADIUS source
WORKDIR /usr/local/src/repositories
RUN export RELEASE_TAG="$(echo "release_${FREERADIUS_VERSION}" | sed -E 's/\./_/g')" && \
    git clone --depth 1 --single-branch --branch $RELEASE_TAG https://github.com/FreeRADIUS/freeradius-server.git
WORKDIR /usr/local/src/repositories/freeradius-server/

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN --mount=type=cache,target=/var/cache/apt,id=var-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=var-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=var-lib-apt-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    if [ -e ./debian/control.in ]; then \
        debian/rules debian/control; \
    fi; \
    echo 'y' | mk-build-deps -irt'apt-get -yV' debian/control

# Build the server
RUN --mount=type=cache,target=/var/cache/apt,id=var-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=var-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=var-lib-apt-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    debian/rules debian/control \
    && dpkg-buildpackage --jobs=auto -b -uc


# =======================================================================================================================================
FROM --platform=$TARGETPLATFORM ubuntu:noble@sha256:2e863c44b718727c860746568e1d54afd13b2fa71b160f5cd9058fc436217b30
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

ARG FREERADIUS_UID=1001
ARG FREERADIUS_GID=1001

# Create user
RUN groupadd -g $FREERADIUS_GID -r freeradius && \
    useradd -u $FREERADIUS_UID \
        -g freeradius \
        --system \
        --no-create-home \
        --no-log-init \
        --home-dir /etc/freeradius \
        --shell /usr/sbin/nologin \
        freeradius

# Install the debian package from builder stage
RUN --mount=type=bind,from=builder,source=/usr/local/src/repositories/*.deb,target=/tmp \
    --mount=type=cache,target=/var/cache/apt,id=var-cache-apt-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=var-cache-debconf-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=var-lib-apt-${TARGETARCH} \
    --mount=type=tmpfs,target=/var/tmp \
    --mount=type=tmpfs,target=/var/log \
    export DEBIAN_FRONTEND="noninteractive" && \
    apt-get update && \
    apt-get install -yq tzdata && \
    apt-get install -y /tmp/*.deb && \
    ln -s /etc/freeradius /etc/raddb

EXPOSE 1812/udp 1813/udp
ENTRYPOINT ["/usr/sbin/freeradius"]
CMD ["-f"]
