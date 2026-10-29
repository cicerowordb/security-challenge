FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    vsftpd \
    procps \
    passwd \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY vsftpd.conf /etc/vsftpd.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && mkdir -p /var/run/vsftpd/empty

EXPOSE 21 40000-40100

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
