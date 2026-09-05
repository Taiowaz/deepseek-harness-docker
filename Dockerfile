FROM node:24-bookworm-slim

ARG DSH_VERSION=0.1.2-rc.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        g++ \
        git \
        make \
        openssh-client \
        python3 \
        ripgrep \
    && npm install --global --omit=dev "@deepseek-ai/dsh@${DSH_VERSION}" \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data/home /data/cache/npm /workspace \
    && chown -R node:node /data /workspace

ENV NODE_ENV=production \
    DSH_HOME=/data \
    HOME=/data/home \
    NPM_CONFIG_CACHE=/data/cache/npm

WORKDIR /workspace
USER node

ENTRYPOINT ["node", "--expose-internals", "/usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"]
CMD ["web", "--port", "3080"]
