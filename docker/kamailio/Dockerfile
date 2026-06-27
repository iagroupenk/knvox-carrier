FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    kamailio \
    kamailio-extra-modules \
    kamailio-utils-modules \
    kamailio-tls-modules \
    curl \
    jq \
    sngrep \
    tcpdump \
    iproute2 \
    dnsutils \
    netcat-openbsd \
    procps \
    && rm -rf /var/lib/apt/lists/*

CMD ["kamailio", "-DD", "-E", "-f", "/etc/kamailio/kamailio.cfg"]
