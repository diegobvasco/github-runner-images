FROM ghcr.io/diegobvasco/github-runner:base

USER root

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:ondrej/php && \
    apt-get update && \
    apt-get install -y \
    php8.5 \
    php8.5-cli \
    php8.5-mbstring \
    php8.5-curl \
    php8.5-xml \
    php8.5-pcov \
    php8.5-mysql && \
    php8.5-sqlite3 \
    rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

USER runner