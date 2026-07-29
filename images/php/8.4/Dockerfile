FROM ghcr.io/diegobvasco/github-runner:base

USER root

RUN apt-get update && \
    apt-get install -y php8.4 php8.4-cli php8.4-mbstring

USER runner