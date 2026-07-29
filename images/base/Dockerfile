FROM ghcr.io/actions/actions-runner:latest

USER root

RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    sudo \
    ca-certificates \
    jq \
    make \
    build-essential \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

USER runner