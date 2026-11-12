# Binaries are fetched on the build platform and verified against the checksums each upstream
# publishes next to its release, so the arm64 image needs no emulation for this stage.
FROM --platform=$BUILDPLATFORM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS download
ARG TARGETARCH
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    apk add \
        ca-certificates \
        curl

WORKDIR /download

# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION="1.37.2"
RUN curl -fsSLO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" && \
    echo "$(curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256")  kubectl" | sha256sum -c - && \
    install -m 0755 kubectl /usr/local/bin/kubectl

# s5cmd names its release archives by its own architecture labels, not Docker's.
# renovate: datasource=github-releases depName=peak/s5cmd
ARG S5CMD_VERSION="2.3.0"
RUN case "${TARGETARCH}" in \
        amd64) S5CMD_ARCH="Linux-64bit" ;; \
        arm64) S5CMD_ARCH="Linux-arm64" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    S5CMD_ARCHIVE="s5cmd_${S5CMD_VERSION}_${S5CMD_ARCH}.tar.gz" && \
    curl -fsSLO "https://github.com/peak/s5cmd/releases/download/v${S5CMD_VERSION}/${S5CMD_ARCHIVE}" && \
    curl -fsSLO "https://github.com/peak/s5cmd/releases/download/v${S5CMD_VERSION}/s5cmd_checksums.txt" && \
    grep " ${S5CMD_ARCHIVE}\$" s5cmd_checksums.txt | sha256sum -c - && \
    tar -xzf "${S5CMD_ARCHIVE}" s5cmd && \
    install -m 0755 s5cmd /usr/local/bin/s5cmd


# =======================================================================================================================================
FROM --platform=$TARGETPLATFORM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    apk add \
        bash \
        ca-certificates \
        curl \
        jq \
        sqlite

COPY --from=download /usr/local/bin/kubectl /usr/local/bin/s5cmd /usr/local/bin/

# Runs every binary on the target architecture, so a wrong-architecture download or a missing
# shared library fails the build instead of the first canary run.
RUN kubectl version --client && \
    s5cmd version && \
    jq --version && \
    sqlite3 --version && \
    curl --version && \
    bash --version

ENV LANG=C.UTF-8 \
    HOME=/tmp
USER 65532:65532
ENTRYPOINT ["/bin/bash"]
