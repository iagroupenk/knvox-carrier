FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    rtpengine-daemon \
    rtpengine-utils \
    iproute2 \
    netcat-openbsd \
    tcpdump \
    procps \
    && rm -rf /var/lib/apt/lists/*

CMD ["rtpengine", "--help"]
