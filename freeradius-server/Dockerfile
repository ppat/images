FROM --platform=$TARGETPLATFORM debian:bookworm-slim@sha256:936abff852736f951dab72d91a1b6337cf04217b2a77a5eaadc7c0f2f1ec1758 AS builder

ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND="noninteractive"
WORKDIR /

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install build tooling
RUN apt-get update && \
    apt-get install -yq --no-install-recommends \
        devscripts \
        equivs \
        git \
        quilt \
        gcc

# renovate: datasource=docker depName=freeradius/freeradius-server
ARG FREERADIUS_VERSION="3.2.8"
# Shallow clone the FreeRADIUS source
WORKDIR /usr/local/src/repositories
RUN export RELEASE_TAG="$(echo "release_${FREERADIUS_VERSION}" | sed -E 's/\./_/g')" && \
    git clone --depth 1 --single-branch --branch "$RELEASE_TAG" https://github.com/FreeRADIUS/freeradius-server.git
WORKDIR /usr/local/src/repositories/freeradius-server/

# Install build dependencies
RUN --mount=type=tmpfs,target=/var/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    if [ -e ./debian/control.in ]; then \
        debian/rules debian/control; \
    fi; \
    echo 'y' | mk-build-deps -irt'apt-get -yV' debian/control

# Build the server
RUN --mount=type=tmpfs,target=/var/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    debian/rules debian/control \
    && dpkg-buildpackage --jobs=auto -b -uc && \
    mkdir -p "/build/${TARGETARCH}" && \
    find /usr/local/src/repositories -name '*.deb' -exec mv -t "/build/${TARGETARCH}" {} + && \
    echo "Built *.deb files:" && \
    find "/build/${TARGETARCH}/" -name '*.deb' | pr -t -o 4


# =======================================================================================================================================
FROM --platform=$TARGETPLATFORM debian:bookworm-slim@sha256:936abff852736f951dab72d91a1b6337cf04217b2a77a5eaadc7c0f2f1ec1758
ARG TARGETARCH
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

ARG FREERADIUS_UID=101
ARG FREERADIUS_GID=101

# Create user
RUN groupadd -g $FREERADIUS_GID -r freerad && \
    useradd -u $FREERADIUS_UID \
        -g freerad \
        --system \
        --no-create-home \
        --no-log-init \
        --home-dir /etc/freeradius \
        --shell /usr/sbin/nologin \
        freerad

# Install system dependencies for freeradius
RUN --mount=type=cache,target=/var/cache/apt,id=cache-apt-deps-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-deps-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-deps-${TARGETARCH} \
    ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime && \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        adduser \
        ca-certificates \
        openssl \
        readline-common \
        ssl-cert \
        tzdata

# Install the debian package from builder stage
# hadolint ignore=SC2086,DL3003,SC2035
RUN --mount=type=bind,from=builder,source=/build/${TARGETARCH},target=/build \
    --mount=type=cache,target=/var/cache/apt,id=cache-apt-install-${TARGETARCH} \
    --mount=type=cache,target=/var/cache/debconf,id=cache-debconf-install-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,id=lib-apt-install-${TARGETARCH} \
    apt-get update && \
    export DEBIAN_FRONTEND="noninteractive" && \
    apt-get install -y --no-install-recommends \
        /build/freeradius-common*.deb \
        /build/libfreeradius3_*.deb \
        /build/freeradius-utils_*.deb && \
    apt-get install -y --no-install-recommends \
        /build/freeradius_*.deb \
        /build/freeradius-config_*.deb \
        /build/freeradius-dbg_*.deb \
        /build/freeradius-dhcp_*.deb \
        /build/freeradius-freetds_*.deb \
        /build/freeradius-krb5_*.deb \
        /build/freeradius-ldap_*.deb \
        /build/freeradius-memcached_*.deb \
        /build/freeradius-mysql_*.deb \
        /build/freeradius-perl-util_*.deb \
        /build/freeradius-postgresql_*.deb \
        /build/freeradius-python3_*.deb \
        /build/freeradius-redis_*.deb \
        /build/freeradius-rest_*.deb \
        /build/freeradius-unbound_*.deb \
        /build/freeradius-unixodbc_*.deb \
        /build/freeradius-yubikey_*.deb && \
    ln -s /etc/freeradius /etc/raddb

EXPOSE 1812/udp 1813/udp
ENTRYPOINT ["/usr/sbin/freeradius"]
CMD ["-f"]
