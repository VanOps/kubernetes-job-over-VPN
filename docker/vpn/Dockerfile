# ══════════════════════════════════════════════════════════════════════
# Stage 1 – builder: install WireGuard + networking tools
# Base: debian:bookworm-slim (Debian 12, LTS, widely tested)
# ══════════════════════════════════════════════════════════════════════
FROM debian:bookworm-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iproute2 \
    iptables \
    nftables \
    iputils-ping \
    procps \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ══════════════════════════════════════════════════════════════════════
# Stage 2 – final: minimal runtime image (no build tools)
# ══════════════════════════════════════════════════════════════════════
FROM debian:bookworm-slim AS final

ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="WireGuard VPN Sidecar" \
      org.opencontainers.image.description="WireGuard VPN sidecar for Kubernetes Jobs" \
      org.opencontainers.image.base.name="debian:bookworm-slim"

# Install only runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iproute2 \
    iptables \
    iputils-ping \
    procps \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Default timezone (overridable via TZ env var)
ENV TZ="Europe/Madrid"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# WireGuard config directory (secret will be mounted here)
RUN mkdir -p /etc/wireguard && chmod 700 /etc/wireguard

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# NOTE: Container requires securityContext.capabilities.add: [NET_ADMIN, SYS_MODULE]
# and sysctls: net.ipv4.ip_forward=1

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
