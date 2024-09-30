FROM golang:1.23.1-bookworm@sha256:dba79eb312528369dea87532a65dbe9d4efb26439a0feacc9e7ac9b0f1c7f607 AS gotools
ENV GOBIN=/bin
RUN go install github.com/drone/envsubst/cmd/envsubst@latest

# =======================================================================================================================================
FROM busybox:1.36.1@sha256:c230832bd3b0be59a6c47ed64294f9ce71e91b327957920b6929a0caa8353140
WORKDIR /

COPY --from=gotools --chown=root:root --chmod=755 /bin/envsubst /bin/envsubt

ENTRYPOINT ["/bin/sh"]
