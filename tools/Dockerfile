FROM ubuntu:noble@sha256:80dd3c3b9c6cecb9f1667e9290b3bc61b78c2678c02cbdae5f0fea92cc6734ab AS aqua
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /

RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends ca-certificates curl wget findutils

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
    aqua cp -o /dist $(find /root/.local/share/aquaproj-aqua/bin -type l -executable -not -name aqua -exec basename {} \;)


# =======================================================================================================================================
FROM busybox:1.37.0@sha256:2919d0172f7524b2d8df9e50066a682669e6d170ac0f6a49676d54358fe970b5
WORKDIR /

COPY --from=aqua --chown=root:root --chmod=755 /dist/* /usr/local/bin/

ENTRYPOINT ["/bin/sh"]


#22 0.053 btop
#22 0.053 dust
#22 0.053 procs
#22 0.053 flux2
#22 0.053 helm
#22 0.053 fzf
#22 0.053 kubectl
#22 0.053 krew
#22 0.053 kustomize
#22 0.053 yq
#22 0.053 duf
#22 0.053 bat
#22 0.053 fd
#22 0.053 hyperfine
#22 0.053 ripgrep
