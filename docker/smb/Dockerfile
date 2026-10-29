FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    samba \
    samba-common-bin \
    smbclient \
    procps \
    passwd \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY smb.conf /etc/samba/smb.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 139 445

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
