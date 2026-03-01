# ══════════════════════════════════════════════════════════════════════
# VPN Server (Test Lab) – WireGuard server for local development
# Simulates the real WireGuard VPN server your Kubernetes Job connects to.
# NOT intended for production use.
# ══════════════════════════════════════════════════════════════════════
FROM debian:bookworm-slim AS final

ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="WireGuard VPN Server (Test Lab)" \
      org.opencontainers.image.description="WireGuard server that simulates a real VPN for local dev/testing"

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iproute2 \
    iptables \
    iputils-ping \
    procps \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV TZ="Europe/Madrid"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

RUN mkdir -p /etc/wireguard && chmod 700 /etc/wireguard

COPY entrypoint.sh   /usr/local/bin/entrypoint.sh
COPY healthcheck.sh  /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# WireGuard UDP port
EXPOSE 51820/udp

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
