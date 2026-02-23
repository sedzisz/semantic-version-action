FROM debian:stable-slim
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="semantic-version-action"
LABEL org.opencontainers.image.license="MIT"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    python3 \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /github/workspace

COPY entrypoint.py /entrypoint.py
RUN chmod +x /entrypoint.py

WORKDIR /github/workspace
ENTRYPOINT ["python3", "/entrypoint.py"]