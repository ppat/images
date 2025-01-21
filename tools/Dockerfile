FROM alpine:3.21.2 as aqua

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    apk add \
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
    xz -d /tmp/upx.tar.xz && \
    tar xvf upx.tar -C /usr/local/sbin --strip-components 1 "upx-${UPX_VERSION}-${TARGETARCH}_linux/upx"

# renovate: datasource=github-releases depName=aquaproj/aqua-installer
ARG AQUA_INSTALLER_VERSION="3.1.1"
RUN curl -sSfL -O https://raw.githubusercontent.com/aquaproj/aqua-installer/v${AQUA_INSTALLER_VERSION}/aqua-installer && \
    chmod +x aqua-installer

# renovate: datasource=github-releases depName=aquaproj/aqua
ARG AQUA_VERSION="2.42.2"
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
FROM alpine:3.21.2

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    apk add \
        bash \
        bind-tools \
        ca-certificates \
        curl \
        e2fsprogs \
        e2fsprogs-extra \
        findutils \
        gnupg \
        iputils \
        jq \
        less \
        libcap \
        lsof \
        lz4 \
        musl-locales \
        netcat-openbsd \
        net-tools \
        nmap \
        openssl \
        parted \
        procps \
        pv \
        screen \
        strace \
        traceroute \
        unzip \
        util-linux \
        util-linux-misc \
        vim \
        wget \
        xz \
        zstd

# generate locales
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    locale-gen en_US.UTF-8
# Make unicode characters work in terminal
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
RUN echo 'LC_ALL=en_US.UTF-8' >> /etc/environment && \
    echo 'LANG=en_US.UTF-8' >> /etc/environment

COPY --from=aqua --chown=root:root --chmod=755 /dist/* /usr/local/bin/

ENTRYPOINT ["/bin/bash"]
