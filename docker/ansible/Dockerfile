# ══════════════════════════════════════════════════════════════════════
# Stage 1 – python-builder: compile Python packages with build deps
# Base: python:3.12-slim (Debian Bookworm, stable CPython 3.12)
# ══════════════════════════════════════════════════════════════════════
FROM python:3.12-slim AS python-builder

ARG ANSIBLE_CORE_VERSION=2.17.7
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libffi-dev \
    libssl-dev \
    libkrb5-dev \
    openssh-client \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install to a dedicated target dir so we can COPY it to the final stage
RUN pip install --no-cache-dir --upgrade pip==24.3.1 && \
    pip install --no-cache-dir \
      ansible-core==${ANSIBLE_CORE_VERSION} \
      boto3==1.35.88 \
      botocore==1.35.88 \
      jmespath==1.0.1 \
      netaddr==1.3.0 \
      cryptography==44.0.0 \
      paramiko==3.5.0 \
      passlib==1.7.4 \
      pywinrm==0.5.0 \
    --prefix=/install \
    --no-warn-script-location

# Install Ansible collections so they are baked into the image (no runtime network needed)
COPY ansible/requirements.yml /tmp/requirements.yml
RUN PATH="/install/bin:$PATH" PYTHONPATH="/install/lib/python3.12/site-packages" \
    ansible-galaxy collection install \
      --requirements-file /tmp/requirements.yml \
      --collections-path /install/ansible/collections \
      --no-cache

# ══════════════════════════════════════════════════════════════════════
# Stage 2 – final: minimal runtime image
# ══════════════════════════════════════════════════════════════════════
FROM python:3.12-slim AS final

ARG ANSIBLE_CORE_VERSION=2.17.7

LABEL org.opencontainers.image.title="Ansible Executor" \
      org.opencontainers.image.description="Ansible playbook executor for Kubernetes Jobs via WireGuard VPN" \
      org.opencontainers.image.version="${ANSIBLE_CORE_VERSION}" \
      org.opencontainers.image.base.name="python:3.12-slim"

ENV TZ="Europe/Madrid" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="/install/lib/python3.12/site-packages" \
    PATH="/install/bin:$PATH" \
    ANSIBLE_HOME=/ansible \
    ANSIBLE_CONFIG=/ansible/ansible.cfg \
    ANSIBLE_STDOUT_CALLBACK=default \
    ANSIBLE_RESULT_FORMAT=yaml \
    ANSIBLE_COLLECTIONS_PATH=/install/ansible/collections:/ansible/collections \
    VPN_WAIT_TIMEOUT=60 \
    VPN_INTERFACE=wg0
# ANSIBLE_VAULT_PASSWORD_FILE and ANSIBLE_HOST_KEY_CHECKING are intentionally
# NOT set here — they are runtime concerns injected via docker-compose/Helm env vars.
# Setting secret-adjacent paths in image ENV triggers linter warnings (hadolint DL3002)
# and couples the image to a specific secret mount path.

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    iputils-ping \
    iproute2 \
    git \
    curl \
    jq \
    tzdata \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled Python packages from builder
COPY --from=python-builder /install /install

# Create non-root ansible user
RUN groupadd -g 1000 ansible && \
    useradd -u 1000 -g ansible -m -s /bin/bash ansible && \
    mkdir -p /ansible /ansible/playbooks /ansible/inventories /ansible/roles \
              /home/ansible/.ssh /run/secrets && \
    chmod 700 /home/ansible/.ssh && \
    chown -R ansible:ansible /ansible /home/ansible

# Scripts
COPY docker/ansible/scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# SSH client hardening
COPY docker/ansible/ssh_config /home/ansible/.ssh/config
RUN chown ansible:ansible /home/ansible/.ssh/config && chmod 600 /home/ansible/.ssh/config

VOLUME ["/ansible"]

USER ansible
WORKDIR /ansible

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["playbooks/test-connectivity.yml"]
