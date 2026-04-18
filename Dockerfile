FROM alpine:3.19

ARG VAULT_VERSION=1.15.4

RUN apk add --no-cache curl unzip gnupg && \
    curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -o /tmp/vault.zip && \
    unzip /tmp/vault.zip -d /usr/local/bin/ && \
    rm /tmp/vault.zip && \
    chmod +x /usr/local/bin/vault

RUN addgroup -S vault && adduser -S vault -G vault

USER vault

EXPOSE 8202

ENTRYPOINT ["vault"]
