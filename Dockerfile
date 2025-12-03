FROM debian:stable-slim

ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="semantic-version-action"
LABEL org.opencontainers.image.license="MIT"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    jq \
    bash \
    curl \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /github/workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /github/workspace

ENTRYPOINT ["/entrypoint.sh"]
