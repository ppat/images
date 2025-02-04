FROM alpine:3.21.2@sha256:56fa17d2a7e7f168a043a2712e63aed1f8543aeafdcee47c58dcffe38ed51099 AS aqua

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    apk add \
        bash \
        ca-certificates \
        curl \
        findutils \
        wget \
        xz

# upx
# renovate: datasource=github-releases depName=upx/upx
ARG UPX_VERSION="4.2.4"
ARG TARGETARCH="amd64"
WORKDIR /tmp
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=tmpfs,target=/var/log \
    --mount=type=tmpfs,target=/var/tmp \
    wget  --progress=dot:giga "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${TARGETARCH}_linux.tar.xz" -O /tmp/upx.tar.xz && \
    mkdir -p /usr/local/sbin && \
    xz -d /tmp/upx.tar.xz && \
    tar xvf upx.tar -C /usr/local/sbin --strip-components 1 "upx-${UPX_VERSION}-${TARGETARCH}_linux/upx"

# renovate: datasource=github-releases depName=aquaproj/aqua-installer
ARG AQUA_INSTALLER_VERSION="3.1.1"
RUN curl -sSfL -O https://raw.githubusercontent.com/aquaproj/aqua-installer/v${AQUA_INSTALLER_VERSION}/aqua-installer && \
    chmod +x aqua-installer

# renovate: datasource=github-releases depName=aquaproj/aqua
ARG AQUA_VERSION="2.43.1"
RUN ./aqua-installer -v v${AQUA_VERSION}

ENV PATH=/root/.local/share/aquaproj-aqua/bin:$PATH
ENV AQUA_GLOBAL_CONFIG=/etc/aqua/aqua.yaml
COPY aqua.yaml aqua-checksums.json /etc/aqua/

# hadolint ignore=SC2046
RUN aqua install --all && \
    mkdir -p /dist && \
    aqua cp -o /dist $(find /root/.local/share/aquaproj-aqua/bin -type l -executable -not -name aqua -exec basename {} \;) && \
    upx $(find /dist  -type f -executable)


# =======================================================================================================================================
FROM alpine:3.21.2@sha256:56fa17d2a7e7f168a043a2712e63aed1f8543aeafdcee47c58dcffe38ed51099

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
apk add \
        acl \
        attr \
        bash \
        bind-tools \
        btrfs-progs \
        ca-certificates \
        cryptsetup \
        curl \
        dmidecode \
        dosfstools \
        e2fsprogs \
        e2fsprogs-extra \
        findutils \
        gnupg \
        hdparm \
        iproute2 \
        iptables \
        iputils \
        jq \
        less \
        libcap \
        lsof \
        lvm2 \
        lz4 \
        mtr \
        netcat-openbsd \
        net-tools \
        nmap \
        nvme-cli \
        openssl \
        parted \
        procps \
        pv \
        screen \
        smartmontools \
        strace \
        sysstat \
        tcpdump \
        traceroute \
        unzip \
        util-linux \
        util-linux-misc \
        vim \
        wget \
        xz \
        zstd

COPY --from=aqua --chown=root:root --chmod=755 /dist/* /usr/local/bin/

ENV LANG=C.UTF-8
ENTRYPOINT ["/bin/bash"]
