FROM golang:1.23.2-bookworm@sha256:2341ddffd3eddb72e0aebab476222fbc24d4a507c4d490a51892ec861bdb71fc AS gotools
ENV GOBIN=/bin
RUN go install github.com/drone/envsubst/cmd/envsubst@latest

# =======================================================================================================================================
FROM busybox:1.37.0@sha256:768e5c6f5cb6db0794eec98dc7a967f40631746c32232b78a3105fb946f3ab83
WORKDIR /

COPY --from=gotools --chown=root:root --chmod=755 /bin/envsubst /bin/envsubt

ENTRYPOINT ["/bin/sh"]
