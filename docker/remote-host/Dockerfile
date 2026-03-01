# ══════════════════════════════════════════════════════════════════════
# Remote Host (Test Lab) – Simulated Debian server behind the VPN
# Only reachable at 10.10.20.10 via the WireGuard tunnel.
# Runs an SSH daemon and accepts connections from the Ansible executor.
# NOT intended for production use.
# ══════════════════════════════════════════════════════════════════════
FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="Remote Host (Test Lab)" \
      org.opencontainers.image.description="Simulated Debian host accessible only via VPN tunnel"

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    python3 \
    python3-apt \
    sudo \
    iproute2 \
    iputils-ping \
    curl \
    procps \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV TZ="Europe/Madrid"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# Create the ansible user (mirrors what Ansible expects on real hosts)
RUN useradd -m -s /bin/bash ansible \
    && echo "ansible ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ansible \
    && chmod 440 /etc/sudoers.d/ansible \
    && mkdir -p /home/ansible/.ssh \
    && chmod 700 /home/ansible/.ssh \
    && chown ansible:ansible /home/ansible/.ssh

# Harden SSH: key-only auth, no root login
RUN mkdir -p /run/sshd \
    && sed -i \
        -e 's/#PasswordAuthentication yes/PasswordAuthentication no/' \
        -e 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' \
        -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' \
        /etc/ssh/sshd_config

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 \
    CMD test -S /var/run/sshd.pid || pgrep sshd > /dev/null

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
