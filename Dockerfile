ARG OPENCLAW_VERSION_TAG

FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION_TAG}

USER root
RUN apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*
USER node
