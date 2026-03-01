# 05 — SSH Parameters Reference para Ansible + VPN (2026)

**Entorno**: con Ansible 2.16+, OpenSSH 9.x, Debian 12  
**Objetivo**: Referencia técnica completa de parámetros SSH útiles para Ansible sobre VPN tunnels, incluyendo integración con ExternalSecrets y troubleshooting Debian-específico.

---

## 📋 Tabla de Contenidos

1. [Ansible SSH Variables](#ansible-vars)
2. [OpenSSH Client Config Options](#openssh-options)
3. [Multiplexing y Performance](#multiplexing)
4. [Timeouts y Keepalives](#timeouts)
5. [Security Hardening](#security)
6. [VPN-Specific Parameters](#vpn-params)
7. [ExternalSecrets Integration](#external-secrets)
8. [Debian 12 Troubleshooting](#debian-troubleshooting)
9. [Tabla Resumen: Valores Recomendados 2026](#tabla-resumen)
10. [Ejemplos Completos](#ejemplos)

---

## <a id="ansible-vars"></a>1. Ansible SSH Variables

Variables que controlan el comportamiento SSH de Ansible. Se pueden definir en:

- Inventory (`host_vars`, `group_vars`)
- Playbook (`vars`, `set_fact`)
- CLI (`-e` extra vars)
- `ansible.cfg`

### Core SSH Variables

| Variable                       | Tipo | Default            | Descripción                            | Ejemplo                       |
| ------------------------------ | ---- | ------------------ | -------------------------------------- | ----------------------------- |
| `ansible_host`                 | str  | inventory_hostname | IP/hostname del target                 | `10.10.0.50`                  |
| `ansible_port`                 | int  | `22`               | Puerto SSH                             | `2222`                        |
| `ansible_user`                 | str  | current user       | Usuario SSH                            | `ansible`, `deploy`           |
| `ansible_ssh_private_key_file` | path | `~/.ssh/id_rsa`    | Ruta a clave privada                   | `/run/secrets/ssh-key`        |
| `ansible_ssh_pass`             | str  | None               | Password SSH (⚠️ inseguro, usar vault) | `{{ vault_ssh_password }}`    |
| `ansible_become_pass`          | str  | None               | Password sudo (usar vault)             | `{{ vault_become_password }}` |
| `ansible_connection`           | str  | `ssh`              | Connection plugin                      | `ssh`, `local`, `paramiko`    |
| `ansible_python_interpreter`   | path | `/usr/bin/python`  | Python en target                       | `/usr/bin/python3`            |

### SSH Behavior Variables

| Variable                  | Tipo | Default | Descripción                                 | Ejemplo                     |
| ------------------------- | ---- | ------- | ------------------------------------------- | --------------------------- |
| `ansible_ssh_common_args` | str  | None    | Args SSH para **todos** los hosts           | `-o ControlMaster=auto`     |
| `ansible_ssh_extra_args`  | str  | None    | Args SSH para **este host específico**      | `-o ProxyJump=bastion`      |
| `ansible_scp_extra_args`  | str  | None    | Args para SCP transfers                     | `-l 8192` (limit bandwidth) |
| `ansible_sftp_extra_args` | str  | None    | Args para SFTP transfers                    | `-o Compression=yes`        |
| `ansible_ssh_pipelining`  | bool | `False` | Habilita pipelining (requiere sudo sin tty) | `True`                      |
| `ansible_ssh_retries`     | int  | `0`     | Reintentos en conexión fallida              | `3`                         |
| `ansible_ssh_timeout`     | int  | `10`    | Timeout conexión SSH (segundos)             | `30`, `60`                  |

### Authentication Variables

| Variable                        | Tipo | Default | Descripción                                       | Ejemplo              |
| ------------------------------- | ---- | ------- | ------------------------------------------------- | -------------------- |
| `ansible_ssh_host_key_checking` | bool | `True`  | **Deprecated** — usar `ANSIBLE_HOST_KEY_CHECKING` | `False` (solo dev)   |
| `ansible_ssh_executable`        | path | `ssh`   | Path al binario SSH                               | `/usr/local/bin/ssh` |

---

### Ejemplo Inventory con Variables

```yaml
---
# inventories/prod/group_vars/all.yml

ansible_connection: ssh
ansible_user: ansible
ansible_ssh_private_key_file: /run/secrets/ssh-key
ansible_python_interpreter: /usr/bin/python3

# SSH args comunes para todos los hosts
ansible_ssh_common_args: >-
  -o ControlMaster=auto
  -o ControlPersist=300s
  -o ControlPath=/tmp/ansible-ssh-%h-%p-%r
  -o ServerAliveInterval=60
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/root/.ssh/known_hosts

# Pipelining para performance
ansible_ssh_pipelining: true

# Timeouts para VPN con alta latencia
ansible_ssh_timeout: 60
ansible_ssh_retries: 3
```

```yaml
---
# inventories/prod/host_vars/db-server.yml

ansible_host: 10.10.0.10
ansible_port: 2222

# ProxyJump específico para este host
ansible_ssh_extra_args: -o ProxyJump=bastion.vpn.int
```

---

## <a id="openssh-options"></a>2. OpenSSH Client Config Options

Opciones de `/etc/ssh/ssh_config` o `~/.ssh/config`. Se pueden pasar via `-o` en command line o en `ansible_ssh_common_args`.

### Connection Options

| Option                     | Values      | Default         | Descripción                                    |
| -------------------------- | ----------- | --------------- | ---------------------------------------------- |
| `Host`                     | pattern     | N/A             | Match hostname (wildcards: \*, ?)              |
| `HostName`                 | hostname/IP | Host value      | Real hostname/IP to connect                    |
| `Port`                     | 1-65535     | `22`            | SSH port                                       |
| `User`                     | username    | current user    | Login username                                 |
| `IdentityFile`             | path        | ~/.ssh/id\_\*   | Private key file                               |
| `IdentitiesOnly`           | yes/no      | `no`            | Only use keys from IdentityFile (no ssh-agent) |
| `PreferredAuthentications` | methods     | pubkey,password | Authentication methods order                   |
| `PubkeyAuthentication`     | yes/no      | `yes`           | Enable pubkey auth                             |
| `PasswordAuthentication`   | yes/no      | `yes`           | Enable password auth                           |

### Proxy & Jump Options

| Option         | Values           | Default | Descripción                              |
| -------------- | ---------------- | ------- | ---------------------------------------- |
| `ProxyJump`    | user@host[:port] | None    | Jump host (OpenSSH 7.3+)                 |
| `ProxyCommand` | command          | None    | Command to establish connection (legacy) |

**Ejemplo ProxyJump**:

```
Host *.private.lan
    ProxyJump bastion.vpn.int
```

**Ejemplo ProxyCommand**:

```
Host *.private.lan
    ProxyCommand ssh -W %h:%p bastion.vpn.int
```

---

### Security Options

| Option                  | Values                | Default            | Descripción                          |
| ----------------------- | --------------------- | ------------------ | ------------------------------------ |
| `StrictHostKeyChecking` | yes/no/accept-new/ask | `ask`              | Host key verification policy         |
| `UserKnownHostsFile`    | path                  | ~/.ssh/known_hosts | Known hosts file path                |
| `VerifyHostKeyDNS`      | yes/no/ask            | `no`               | Verify host key via DNSSEC           |
| `HashKnownHosts`        | yes/no                | `no`               | Hash hostnames in known_hosts        |
| `CheckHostIP`           | yes/no                | `yes`              | Check host IP in known_hosts         |
| `Ciphers`               | cipher-list           | (secure defaults)  | Encryption algorithms allowed        |
| `MACs`                  | mac-list              | (secure defaults)  | Message authentication codes allowed |
| `KexAlgorithms`         | kex-list              | (secure defaults)  | Key exchange algorithms              |
| `HostKeyAlgorithms`     | alg-list              | (secure defaults)  | Host key algorithms                  |

**Valores Recomendados 2026 (Debian 12)**:

```
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
```

---

### Performance Options

| Option             | Values | Default | Descripción                            |
| ------------------ | ------ | ------- | -------------------------------------- |
| `Compression`      | yes/no | `no`    | Enable compression (útil en VPN lento) |
| `CompressionLevel` | 1-9    | `6`     | Gzip compression level                 |
| `TCPKeepAlive`     | yes/no | `yes`   | Send TCP keepalive packets             |

---

## <a id="multiplexing"></a>3. Multiplexing y Performance

SSH ControlMaster permite **reutilizar conexiones TCP** para múltiples sesiones SSH, reduciendo handshakes.

### ControlMaster Options

| Option           | Values                  | Default | Descripción                                     |
| ---------------- | ----------------------- | ------- | ----------------------------------------------- |
| `ControlMaster`  | yes/no/ask/auto/autoask | `no`    | Enable connection multiplexing                  |
| `ControlPath`    | path with tokens        | None    | Socket path (tokens: %h, %p, %r, %C)            |
| `ControlPersist` | time/yes/no             | `no`    | Keep master connection alive after last session |

### Valores Recomendados

```
ControlMaster auto
ControlPath /tmp/ssh-control-%C
ControlPersist 600s
```

**Tokens ControlPath**:

- `%C`: Hash of %l%h%p%r (unique identifier)
- `%h`: Remote hostname
- `%p`: Remote port
- `%r`: Remote username
- `%L`: Local hostname
- `%%`: Literal %

### Benchmark: Con vs Sin ControlMaster

| Métrica                 | Sin ControlMaster | Con ControlMaster | Mejora  |
| ----------------------- | ----------------- | ----------------- | ------- |
| Primera conexión        | 250ms             | 250ms             | 0%      |
| Conexiones subsecuentes | 250ms             | 30ms              | **88%** |
| 100 tasks Ansible       | 35s               | 12s               | **66%** |

### Troubleshooting ControlMaster

```bash
# Ver sockets activos
ls -lh /tmp/ssh-control-*

# Verificar socket funcional
ssh -O check -S /tmp/ssh-control-C-hash user@host

# Cerrar master connection
ssh -O exit -S /tmp/ssh-control-C-hash user@host

# Limpiar sockets huérfanos
rm -f /tmp/ssh-control-*
```

---

## <a id="timeouts"></a>4. Timeouts y Keepalives

Crítico para VPN con NAT/firewalls que cierran conexiones idle.

### Timeout Options

| Option                | Values (seconds)  | Default   | Descripción                                   |
| --------------------- | ----------------- | --------- | --------------------------------------------- |
| `ConnectTimeout`      | int               | None (OS) | Timeout para TCP connect                      |
| `ServerAliveInterval` | int               | `0`       | Intervalo keepalive client→server             |
| `ServerAliveCountMax` | int               | `3`       | Max keepalives sin respuesta antes de timeout |
| `LoginGraceTime`      | int (server-side) | `120`     | Tiempo para completar auth (sshd_config)      |
| `ClientAliveInterval` | int (server-side) | `0`       | Keepalive server→client (sshd_config)         |
| `ClientAliveCountMax` | int (server-side) | `3`       | Max keepalives sin respuesta (sshd_config)    |

### Cálculo Total Timeout

**Client-side timeout** (antes de desconexión automática):

```
Total = ServerAliveInterval * (ServerAliveCountMax + 1)
```

Ejemplo:

```
ServerAliveInterval 60
ServerAliveCountMax 3

Total timeout = 60 * (3 + 1) = 240 segundos (4 minutos)
```

### Valores Recomendados para VPN

```ini
# Cliente SSH (ansible-control)
ServerAliveInterval 60       # Enviar keepalive cada 60s
ServerAliveCountMax 3        # 3 fallos = disconnect (total 240s)
ConnectTimeout 30            # Max 30s para TCP handshake
TCPKeepAlive yes             # TCP-level keepalive (adicional)
```

```ini
# Servidor SSH (targets en VPN)
ClientAliveInterval 60       # Enviar keepalive cada 60s
ClientAliveCountMax 3        # 3 fallos = kill session
```

### Ansible-Specific Timeouts

```yaml
# ansible.cfg
[defaults]
timeout = 60  # SSH connection timeout (seconds)
command_timeout = 300  # Command execution timeout (seconds)

[ssh_connection]
ssh_args = -o ConnectTimeout=30 -o ServerAliveInterval=60
```

---

## <a id="security"></a>5. Security Hardening

### Client-Side Hardening (~/.ssh/config)

```
Host *
    # ── Authentication ─────────────────────────────────────────────
    PubkeyAuthentication yes
    PasswordAuthentication no
    ChallengeResponseAuthentication no

    # ── Host Key Verification ──────────────────────────────────────
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
    VerifyHostKeyDNS no

    # ── Modern Crypto (2026) ───────────────────────────────────────
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
    KexAlgorithms curve25519-sha256,diffie-hellman-group18-sha512
    HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

    # ── Disable Weak Features ──────────────────────────────────────
    ForwardAgent no
    ForwardX11 no
    PermitLocalCommand no

    # ── Identity ───────────────────────────────────────────────────
    IdentitiesOnly yes
    IdentityFile ~/.ssh/id_ed25519
```

### Server-Side Hardening (/etc/ssh/sshd_config)

```
# ══════════════════════════════════════════════════════════════════
# /etc/ssh/sshd_config — Hardened for Production 2026
# ══════════════════════════════════════════════════════════════════

# ── Listening ──────────────────────────────────────────────────────
Port 22
AddressFamily inet
ListenAddress 10.10.0.50  # VPN IP only (no internet exposure)

# ── Authentication ─────────────────────────────────────────────────
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# ── Root Login ─────────────────────────────────────────────────────
PermitRootLogin prohibit-password  # Solo con key (mejor: no)

# ── User Restrictions ──────────────────────────────────────────────
AllowUsers ansible deploy
#AllowGroups sshusers

# ── Crypto (2026) ──────────────────────────────────────────────────
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# ── Logging ────────────────────────────────────────────────────────
SyslogFacility AUTH
LogLevel VERBOSE  # Captura fingerprints (VERBOSE en prod, DEBUG solo debug)

# ── Timeouts ───────────────────────────────────────────────────────
ClientAliveInterval 60
ClientAliveCountMax 3
LoginGraceTime 60
MaxAuthTries 3
MaxSessions 10

# ── Tunneling ──────────────────────────────────────────────────────
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no
X11Forwarding no
AllowAgentForwarding no

# ── Environment ────────────────────────────────────────────────────
PermitUserEnvironment no
AcceptEnv LANG LC_*  # Solo locales

# ── Subsystems ─────────────────────────────────────────────────────
Subsystem sftp /usr/lib/openssh/sftp-server  # Necesario para Ansible

# ── Banners ────────────────────────────────────────────────────────
Banner /etc/ssh/banner.txt  # Legal warning (opcional)

# ── Modern Features (OpenSSH 9.x) ──────────────────────────────────
RequiredRSASize 2048  # Min RSA key size
```

### Validar Config

```bash
# Test syntax
sudo sshd -t

# Test crypto suite
ssh -Q cipher
ssh -Q mac
ssh -Q kex
ssh -Q key

# Scan server SSH config (externo)
ssh-audit 10.10.0.50
```

---

## <a id="vpn-params"></a>6. VPN-Specific Parameters

### SSH sobre WireGuard

```yaml
# group_vars/vpn_hosts.yml

# VPN-specific SSH args
ansible_ssh_common_args: >-
  -o ControlMaster=auto
  -o ControlPersist=600s
  -o ServerAliveInterval=60
  -o ServerAliveCountMax=3
  -o ConnectTimeout=30
  -o Compression=no

# No compression: WireGuard ya está encriptado y comprimido
# Compression adicional → overhead sin beneficio
```

### SSH sobre OpenVPN

```yaml
# OpenVPN típicamente tiene más latencia → aumentar timeouts

ansible_ssh_common_args: >-
  -o ControlMaster=auto
  -o ControlPersist=600s
  -o ServerAliveInterval=90
  -o ServerAliveCountMax=5
  -o ConnectTimeout=45
  -o Compression=yes

# Compression=yes: OpenVPN puede beneficiarse si link es lento
```

### MTU Optimization

```bash
# Verificar MTU PATH
ssh user@10.10.0.50 'ip route get 8.8.8.8 | grep mtu'

# Test fragmentación
ping -M do -s 1400 10.10.0.50

# Ajustar WireGuard MTU si hay fragmentación
# /etc/wireguard/wg0.conf:
[Interface]
MTU = 1380  # Default 1420, restar 40 si hay nested tunnels
```

---

## <a id="external-secrets"></a>7. ExternalSecrets Integration

### Arquitectura: Vault → ESO → K8s Secret → Pod

```
┌──────────────────────────────────────────────────────────────────┐
│  AWS Secrets Manager / HashiCorp Vault                           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ ansible-vpn/prod/ssh-key         (PEM private key)         │  │
│  │ ansible-vpn/prod/known-hosts     (SSH fingerprints)        │  │
│  │ ansible-vpn/prod/vault-password  (Ansible Vault password)  │  │
│  └────────────────────────────────────────────────────────────┘  │
└───────────────────────────┬──────────────────────────────────────┘
                            │ External Secrets Operator (ESO)
                            ▼
                  ┌──────────────────────┐
                  │ Kubernetes Secret    │
                  │ ansible-secrets      │
                  │ ├─ ssh-key           │
                  │ ├─ known_hosts       │
                  │ └─ vault-password    │
                  └──────────┬───────────┘
                            │ Volume mount
                            ▼
                  ┌──────────────────────┐
                  │ Ansible Job Pod      │
                  │ /run/secrets/        │
                  │ ├─ ssh-key           │
                  │ ├─ known_hosts       │
                  │ └─ vault-password    │
                  └──────────────────────┘
```

---

### ExternalSecret Manifest

```yaml
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ansible-secrets
  namespace: ansible-jobs-prod
spec:
  refreshInterval: 1h  # Sync cada hora

  secretStoreRef:
    name: aws-secretsmanager  # SecretStore name
    kind: SecretStore

  target:
    name: ansible-secrets  # K8s Secret name
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # SSH private key
        ssh-key: |
{{ .sshkey | nindent 10 }}

        # Known hosts file
        known_hosts: |
{{ .knownhosts | nindent 10 }}

        # Ansible Vault password
        vault-password: "{{ .vaultpassword }}"

  dataFrom:
    - extract:
        key: ansible-vpn/prod  # AWS Secrets Manager path
        property: ssh-key
        rewrite:
          - source: ssh-key
            target: sshkey

    - extract:
        key: ansible-vpn/prod
        property: known-hosts
        rewrite:
          - source: known-hosts
            target: knownhosts

    - extract:
        key: ansible-vpn/prod
        property: vault-password
        rewrite:
          - source: vault-password
            target: vaultpassword
```

---

### Job Manifest usando Secret

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: ansible-deploy
  namespace: ansible-jobs-prod
spec:
  template:
    spec:
      restartPolicy: Never

      # Init container: VPN sidecar
      initContainers:
        - name: vpn-sidecar
          image: ghcr.io/yourorg/k8s-vpn-sidecar:latest
          # ... VPN config ...

      containers:
        - name: ansible-executor
          image: ghcr.io/yourorg/k8s-ansible-executor:latest

          env:
            - name: ANSIBLE_VAULT_PASSWORD_FILE
              value: /run/secrets/vault-password
            - name: ANSIBLE_SSH_PRIVATE_KEY_FILE
              value: /run/secrets/ssh-key

          volumeMounts:
            # Mount secrets como archivos
            - name: ansible-secrets
              mountPath: /run/secrets
              readOnly: true

            # Mount known_hosts en SSH default location
            - name: ansible-secrets
              mountPath: /root/.ssh/known_hosts
              subPath: known_hosts
              readOnly: true

      volumes:
        - name: ansible-secrets
          secret:
            secretName: ansible-secrets
            defaultMode: 0600 # Permisos SSH key
            items:
              - key: ssh-key
                path: ssh-key
                mode: 0600
              - key: known_hosts
                path: known_hosts
                mode: 0644
              - key: vault-password
                path: vault-password
                mode: 0600
```

---

### Poblar known_hosts desde Targets

Script para generar known_hosts y subir a Vault:

```bash
#!/usr/bin/env bash
# generate-known-hosts.sh

set -euo pipefail

KNOWN_HOSTS_FILE="/tmp/known_hosts.tmp"
> "${KNOWN_HOSTS_FILE}"

# Lista de hosts en VPN
HOSTS=(
  "10.10.0.30"  # bastion
  "10.10.0.50"  # target1
  "10.10.0.51"  # target2
  "10.10.0.10"  # db-server
)

echo "Scanning SSH host keys..."

for host in "${HOSTS[@]}"; do
  echo "  → ${host}"
  ssh-keyscan -H "${host}" >> "${KNOWN_HOSTS_FILE}" 2>/dev/null || echo "    ⚠ Failed to scan ${host}"
done

echo "✓ Known hosts collected"

# Upload to AWS Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id ansible-vpn/prod \
  --secret-string "$(jq -n \
    --arg kh "$(cat ${KNOWN_HOSTS_FILE})" \
    '{
      "ssh-key": env.SSH_KEY,
      "known-hosts": $kh,
      "vault-password": env.VAULT_PASSWORD
    }')"

echo "✓ Uploaded to AWS Secrets Manager"

# Cleanup
rm -f "${KNOWN_HOSTS_FILE}"
```

---

## <a id="debian-troubleshooting"></a>8. Debian 12 Troubleshooting

### Problema: SELinux/AppArmor interfiere con SSH

**Debian 12 default**: AppArmor habilitado, SELinux no.

```bash
# Verificar AppArmor status
sudo aa-status

# Ver denials
sudo journalctl -xe | grep -i apparmor | grep -i ssh

# Temporalmente deshabilitar (desarrollo)
sudo systemctl stop apparmor
sudo systemctl disable apparmor

# Mejor: Crear policy específica
sudo aa-complain /usr/sbin/sshd
```

---

### Problema: resolv.conf sobrescrito por VPN

**Causa**: NetworkManager o systemd-resolved sobrescribe DNS después de levantar VPN.

```bash
# Ver DNS actual
cat /etc/resolv.conf

# Debian 12 usa systemd-resolved
systemd-resolve --status

# Forzar DNS en WireGuard config
# /etc/wireguard/wg0.conf:
[Interface]
DNS = 10.10.0.1
PostUp = echo "nameserver 10.10.0.1" > /etc/resolv.conf
PostDown = systemctl restart systemd-resolved
```

**Alternativa**: Usar resolvconf

```bash
sudo apt-get install resolvconf

# WireGuard config:
[Interface]
DNS = 10.10.0.1
# resolvconf automático
```

---

### Problema: "SSH: no matching cipher found"

**Causa**: Cliente y servidor no tienen ciphers en común.

```bash
# Ver ciphers disponibles en cliente
ssh -Q cipher

# Ver ciphers en servidor
sudo sshd -T | grep ciphers

# Temporalmente forzar cipher específico
ssh -c aes256-ctr user@host

# Permanente: Añadir cipher legacy (no recomendado)
# ~/.ssh/config:
Ciphers +aes256-cbc
```

---

### Problema: Python interpreter no encontrado

```bash
# Ansible error:
# fatal: [host]: FAILED! => {"msg": "/bin/sh: 1: /usr/bin/python: not found"}
```

**Causa**: Debian 12 solo tiene Python 3, no Python 2.

**Solución**:

```yaml
# inventory
ansible_python_interpreter: /usr/bin/python3

# O auto-detect (Ansible 2.8+)
ansible_python_interpreter: auto_silent
```

---

### Problema: Locales warnings

```bash
# perl: warning: Setting locale failed.
# perl: warning: Please check that your locale settings
```

**Solución Debian 12**:

```bash
# Instalar locales
sudo apt-get install locales

# Generar locales
sudo dpkg-reconfigure locales
# Seleccionar: en_US.UTF-8 UTF-8

# Verificar
locale

# Exportar en shell profile
echo 'export LC_ALL=en_US.UTF-8' >> ~/.bashrc
echo 'export LANG=en_US.UTF-8' >> ~/.bashrc
source ~/.bashrc

# En Ansible playbook:
- name: Set locales
  ansible.builtin.lineinfile:
    path: /etc/environment
    line: "{{ item }}"
  loop:
    - "LC_ALL=en_US.UTF-8"
    - "LANG=en_US.UTF-8"
```

---

### Problema: Connection timeout en VPN

```bash
# Verificar VPN interface UP
ip link show wg0

# Ping VPN gateway
ping -c 3 10.10.0.1

# Ver routing
ip route get 10.10.0.50

# tcpdump en VPN interface
sudo tcpdump -i wg0 -n 'port 22'

# Ver WireGuard handshake
sudo wg show wg0 latest-handshakes

# Verificar iptables no bloquea
sudo iptables -L -n -v | grep wg0
```

---

## <a id="tabla-resumen"></a>9. Tabla Resumen: Valores Recomendados 2026

### ansible.cfg

```ini
[defaults]
inventory           = inventories/prod
timeout             = 60
forks               = 20
gathering           = smart
host_key_checking   = True

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=600s -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new
control_path = /tmp/ansible-ssh-%%C
pipelining = True
transfer_method = smart
ssh_retries = 3
```

### ~/.ssh/config (Client)

```
Host *.vpn.int
    User ansible
    IdentityFile /run/secrets/ssh-key
    IdentitiesOnly yes

    # Multiplexing
    ControlMaster auto
    ControlPersist 600s
    ControlPath /tmp/ssh-control-%C

    # Timeouts
    ConnectTimeout 30
    ServerAliveInterval 60
    ServerAliveCountMax 3

    # Security
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts

    # Modern crypto
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
    KexAlgorithms curve25519-sha256,diffie-hellman-group18-sha512
    HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

    # Performance
    Compression no
    TCPKeepAlive yes
```

### /etc/ssh/sshd_config (Server)

```
ListenAddress 10.10.0.50
Port 22

PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password

AllowUsers ansible deploy

Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,diffie-hellman-group18-sha512

ClientAliveInterval 60
ClientAliveCountMax 3
LoginGraceTime 60
MaxAuthTries 3

LogLevel VERBOSE

AllowTcpForwarding no
X11Forwarding no
AllowAgentForwarding no

Subsystem sftp /usr/lib/openssh/sftp-server
```

---

## <a id="ejemplos"></a>10. Ejemplos Completos

### Ejemplo 1: Inventory Multi-Entorno

```yaml
---
# inventories/prod/hosts.yml

all:
  vars:
    ansible_connection: ssh
    ansible_user: ansible
    ansible_ssh_private_key_file: /run/secrets/ssh-key
    ansible_python_interpreter: /usr/bin/python3

    ansible_ssh_common_args: >-
      -o ControlMaster=auto
      -o ControlPersist=600s
      -o ControlPath=/tmp/ansible-ssh-%C
      -o ServerAliveInterval=60
      -o ServerAliveCountMax=3
      -o ConnectTimeout=30
      -o StrictHostKeyChecking=accept-new

    ansible_ssh_pipelining: true
    ansible_ssh_timeout: 60
    ansible_ssh_retries: 3

  children:
    vpn_direct:
      hosts:
        gateway:
          ansible_host: 10.10.0.1
        bastion:
          ansible_host: 10.10.0.30

    vpn_via_bastion:
      vars:
        ansible_ssh_extra_args: -o ProxyJump=bastion
      hosts:
        web1:
          ansible_host: 10.10.0.50
        web2:
          ansible_host: 10.10.0.51
        db1:
          ansible_host: 10.10.0.10
          ansible_port: 2222 # Non-standard port
```

---

### Ejemplo 2: Playbook con Debug SSH

```yaml
---
- name: Debug SSH Connection
  hosts: all
  gather_facts: false
  tasks:
    - name: Show Ansible SSH command
      ansible.builtin.debug:
        msg: |
          SSH Command: ssh {{ ansible_ssh_common_args | default('') }} {{ ansible_ssh_extra_args | default('') }} -i {{ ansible_ssh_private_key_file | default('~/.ssh/id_rsa') }} {{ ansible_user }}@{{ ansible_host }}

    - name: Test SSH with verbose
      ansible.builtin.command:
        cmd: ssh -vvv -o ConnectTimeout=10 {{ ansible_host }} 'echo SSH_OK'
      delegate_to: localhost
      register: ssh_test
      changed_when: false
      failed_when: false

    - name: Show SSH output
      ansible.builtin.debug:
        var: ssh_test.stdout_lines

    - name: Actual ping
      ansible.builtin.ping:
```

---

### Ejemplo 3: PreTask Setup SSH

```yaml
---
- name: Production Deploy
  hosts: all

  pre_tasks:
    - name: Wait for SSH
      ansible.builtin.wait_for_connection:
        timeout: 60
        delay: 5
      tags: always

    - name: Verify Python
      ansible.builtin.raw: python3 --version
      register: python_check
      changed_when: false
      tags: always

    - name: Show Python version
      ansible.builtin.debug:
        msg: "Target Python: {{ python_check.stdout }}"
      tags: always

  tasks:
    # ... deployment tasks ...
```

---

## 🔗 Referencias

- [Ansible SSH Connection Plugin](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/ssh_connection.html)
- [OpenSSH Config Man Page](https://man.openbsd.org/ssh_config.5)
- [OpenSSH Server Config](https://man.openbsd.org/sshd_config.5)
- [Mozilla SSH Guidelines](https://infosec.mozilla.org/guidelines/openssh)
- [Debian SSH Hardening](https://wiki.debian.org/SSH)
- [External Secrets Operator](https://external-secrets.io/)
- [AWS Secrets Manager with K8s](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html)

---

## 📝 Checklist Final

- [ ] `ControlMaster=auto` + `ControlPersist=600s` habilitado
- [ ] `ServerAliveInterval=60` + `ServerAliveCountMax=3`
- [ ] `StrictHostKeyChecking=accept-new` (producción) o `no` (dev)
- [ ] `ansible_python_interpreter=/usr/bin/python3`
- [ ] `Pipelining=True` + `Defaults !requiretty` en sudoers
- [ ] Modern ciphers: ChaCha20-Poly1305, AES-256-GCM
- [ ] SSH keys con permisos `600`
- [ ] Known hosts pre-poblado desde ExternalSecrets
- [ ] VPN MTU optimizado (1380-1420)
- [ ] Locales UTF-8 instalados en Debian
- [ ] AppArmor/SELinux policy revisada
- [ ] DNS resolution funcional en VPN
- [ ] Logs SSH en `VERBOSE` para auditoria

---

**Fin del módulo educativo SSH + Ansible + VPN**

Para profundizar, explora los labs prácticos:

- [Lab 1](02-docker-ansible-lab.md): Docker Compose SSH Multi-Host
- [Lab 2](04-vpn-tunnel-lab.md): WireGuard + OpenVPN + Ansible
