FROM ubuntu:noble@sha256:80dd3c3b9c6cecb9f1667e9290b3bc61b78c2678c02cbdae5f0fea92cc6734ab AS aqua
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends ca-certificates curl wget

# yq
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION="4.44.6"
ARG YQ_ARCH="amd64"
RUN wget --progress=dot:giga -c "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${YQ_ARCH}.tar.gz" -O - | tar -xzv -C /tmp && \
    install -o root -g root -m 0755 "/tmp/yq_linux_${YQ_ARCH}" /usr/local/sbin/yq && \
    rm -rf /tmp/* /var/log/* /var/tmp/*

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

RUN echo "Installing binaries with aqua..." && \
    aqua install --all

# hadolint ignore=SC2046
RUN mkdir -p /dist && \
    set -x && \
    aqua cp -o /dist $(yq '.packages[].name' /etc/aqua/aqua.yaml | cut -d'@' -f1 | cut -d'/' -f2) && \
    set +x


# =======================================================================================================================================
FROM busybox:1.37.0@sha256:2919d0172f7524b2d8df9e50066a682669e6d170ac0f6a49676d54358fe970b5
WORKDIR /

COPY --from=aqua --chown=root:root --chmod=755 /dist/* /usr/local/bin/

ENTRYPOINT ["/bin/sh"]
