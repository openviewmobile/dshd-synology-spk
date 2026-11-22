# Override the base image for amd64 or a domestic mirror:
#   docker build --platform linux/amd64 \
#     --build-arg NODE_IMAGE=node:24-bookworm-slim-amd64 \
#     --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
#     --build-arg APT_MIRROR=http://mirrors.aliyun.com .
ARG NODE_IMAGE=node:24-bookworm-slim
ARG NPM_REGISTRY=https://registry.npmmirror.com
ARG APT_MIRROR=http://mirrors.aliyun.com
FROM ${NODE_IMAGE}

ARG NPM_REGISTRY
ARG APT_MIRROR
ARG DSHD_VERSION=0.3.0

LABEL org.opencontainers.image.title="DSHD" \
      org.opencontainers.image.description="DeepSeek Harness (dsh) headless web host for Synology DSM" \
      org.opencontainers.image.version="${DSHD_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive
RUN if [ -n "$APT_MIRROR" ]; then \
      sed -i "s|http://deb.debian.org|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources; \
    fi \
 && apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      ca-certificates bash ripgrep tini curl git python3 jq unzip xz-utils procps less \
 && rm -rf /var/lib/apt/lists/*

RUN npm config set registry "$NPM_REGISTRY" \
 && npm i -g @deepseek-ai/dsh@0.2.2-rc.1 pnpm@11.28.5 \
      --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs \
      --no-audit --no-fund --registry "$NPM_REGISTRY" \
 && npm cache clean --force

RUN useradd --create-home --uid 1001 --shell /bin/bash dsh
USER dsh
WORKDIR /home/dsh
ENV HOME=/home/dsh

COPY --chown=dsh:dsh entrypoint.sh /usr/local/bin/dshd-entrypoint
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/dshd-entrypoint"]
