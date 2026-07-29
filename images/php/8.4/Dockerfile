FROM ghcr.io/diegobvasco/github-runner:base

USER root

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:ondrej/php && \
    apt-get update && \
    apt-get install -y php8.4 php8.4-cli php8.4-mbstring php8.4-curl php8.4-xml

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

USER runner