FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    medusa \
    enum4linux \
    smbclient \
    nmap \
    curl \
    lftp \
    net-tools \
    iputils-ping \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
