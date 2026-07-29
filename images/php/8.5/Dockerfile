FROM ghcr.io/diegobvasco/github-runner:base

USER root

RUN apt-get update && \
    apt-get install -y php8.5 php8.5-cli php8.5-mbstring

USER runner