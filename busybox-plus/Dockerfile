FROM golang:1.23.2-bookworm@sha256:2341ddffd3eddb72e0aebab476222fbc24d4a507c4d490a51892ec861bdb71fc AS gotools
ENV GOBIN=/bin
RUN go install github.com/drone/envsubst/cmd/envsubst@latest

# =======================================================================================================================================
FROM busybox:1.36.1@sha256:c230832bd3b0be59a6c47ed64294f9ce71e91b327957920b6929a0caa8353140
WORKDIR /

COPY --from=gotools --chown=root:root --chmod=755 /bin/envsubst /bin/envsubt

ENTRYPOINT ["/bin/sh"]
