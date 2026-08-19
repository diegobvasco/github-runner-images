FROM ghcr.io/diegobvasco/github-runner:base

SHELL ["/bin/bash", "-c"]

ARG PHP_VERSIONS="8.1 8.2 8.3 8.4 8.5"

USER root

RUN apt-get update && \
    apt-get install -y software-properties-common

RUN apt-get install -y \
        software-properties-common \
        zip \
        pkg-config \
        autoconf \
        libssl-dev \
        libcurl4-openssl-dev \
        libxml2-dev \
        libzip-dev \
        libsqlite3-dev \
        libpq-dev \
        default-mysql-client \
        postgresql-client \
        sqlite3 \
        openssh-client \
        rsync \
        procps \
        lsof \
        netcat-openbsd \
        dnsutils

RUN add-apt-repository ppa:ondrej/php && \
    apt-get update \
    && \
    for version in ${PHP_VERSIONS}; do \
        apt-get install -y \
            php${version} \
            php${version}-cli \
            php${version}-common \
            php${version}-dev \
            php${version}-mbstring \
            php${version}-curl \
            php${version}-xml \
            php${version}-zip \
            php${version}-bcmath \
            php${version}-intl \
            php${version}-readline \
            php${version}-opcache \
            php${version}-mysql \
            php${version}-pgsql \
            php${version}-sqlite3 \
            php${version}-pcov \
            php${version}-redis \
            php${version}-xdebug \
        && \
        update-alternatives --install \
            /usr/bin/php \
            php \
            /usr/bin/php${version} \
            ${version//./}; \
    done && \
    rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

USER runner
