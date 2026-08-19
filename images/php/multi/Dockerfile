FROM ghcr.io/diegobvasco/github-runner:base

SHELL ["/bin/bash", "-c"]

ARG PHP_VERSIONS="8.1 8.2 8.3 8.4 8.5"
ARG PHP_EXTENSIONS="cli common dev mbstring curl xml zip bcmath intl readline opcache mysql pgsql sqlite3 pcov redis xdebug"

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
        packages="php${version}"; \
        for extension in ${PHP_EXTENSIONS}; do \
            package="php${version}-${extension}"; \
            if apt-cache show "${package}" >/dev/null 2>&1; then \
                packages="${packages} ${package}"; \
            fi; \
        done; \
        apt-get install -y ${packages} \
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
