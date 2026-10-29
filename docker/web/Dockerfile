FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    apache2 \
    mariadb-server \
    mariadb-client \
    php \
    php-mysqli \
    php-gd \
    php-xml \
    php-mbstring \
    php-curl \
    libapache2-mod-php \
    git \
    curl \
    ca-certificates \
    procps \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch 2.5 https://github.com/digininja/DVWA.git /var/www/html/DVWA

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
