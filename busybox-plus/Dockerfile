FROM golang:1.23.1-bookworm AS gotools
ENV GOBIN=/bin
RUN go install github.com/drone/envsubst/cmd/envsubst@latest

# =======================================================================================================================================
FROM busybox:1.36.1
WORKDIR /

COPY --from=gotools --chown=root:root --chmod=755 /bin/envsubst /bin/envsubt

ENTRYPOINT ["/bin/sh"]
