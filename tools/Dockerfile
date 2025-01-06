FROM ubuntu:noble@sha256:80dd3c3b9c6cecb9f1667e9290b3bc61b78c2678c02cbdae5f0fea92cc6734ab AS aqua
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        ca-certificates \
        curl \
        findutils \
        wget \
        xz-utils

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
ARG AQUA_INSTALLER_VERSION="3.1.0"
RUN curl -sSfL -O https://raw.githubusercontent.com/aquaproj/aqua-installer/v${AQUA_INSTALLER_VERSION}/aqua-installer && \
    chmod +x aqua-installer

# renovate: datasource=github-releases depName=aquaproj/aqua
ARG AQUA_VERSION="2.42.0"
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
FROM debian:bookworm-slim
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/debconf,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        dnsutils \
        findutils \
        fio \
        git \
        gnupg \
        jq \
        inetutils-tools \
        iotop \
        iputils-ping \
        iputils-tracepath \
        less \
        locales \
        lsof \
        netcat-openbsd \
        net-tools \
        nmap \
        psmisc \
        screen \
        strace \
        sysstat \
        traceroute \
        tzdata \
        vim \
        watch \
        wget \
        xz-utils \
        && \
    find /usr -name __pycache__ -exec rm -rf {} +

# generate locales (needed for many applications, specially python)
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    locale-gen en_US.UTF-8
# Make typing unicode characters in the terminal work.
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
RUN echo 'LC_ALL=en_US.UTF-8' >> /etc/environment && \
    echo 'LANG=en_US.UTF-8' >> /etc/environment

COPY --from=aqua --chown=root:root --chmod=755 /dist/* /usr/local/bin/

ENTRYPOINT ["/bin/bash"]
