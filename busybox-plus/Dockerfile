FROM golang:1.23.4-bookworm@sha256:2e838582004fab0931693a3a84743ceccfbfeeafa8187e87291a1afea457ff7a AS gotools
ENV GOBIN=/bin
RUN go install github.com/drone/envsubst/cmd/envsubst@latest

# =======================================================================================================================================
FROM busybox:1.37.0@sha256:2919d0172f7524b2d8df9e50066a682669e6d170ac0f6a49676d54358fe970b5
WORKDIR /

COPY --from=gotools --chown=root:root --chmod=755 /bin/envsubst /bin/envsubt

ENTRYPOINT ["/bin/sh"]
