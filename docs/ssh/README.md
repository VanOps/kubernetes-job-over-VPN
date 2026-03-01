# 📚 Ansible + SSH + VPN Tunnels — Módulo Educativo

## 🎯 Audiencia

- DevOps Engineers con experiencia en Debian 12 Bookworm
- Infraestructura: microk8s, Docker, Ansible 2.16+
- VSCode con extensión Ansible
- Casos de uso: GitOps, Kubernetes Jobs, CI/CD

---

## 📖 Contenido del Módulo

### [01 — Principios SSH en Ansible](01-ansible-ssh-principles.md)

**Fundamentos core** de cómo Ansible gestiona conexiones SSH.

**Temas cubiertos**:

- Flujo de conexión SSH de Ansible
- Gestión de `known_hosts` y `StrictHostKeyChecking`
- ProxyJump para hosts intermedios (bastion)
- Configuración `ansible.cfg` y `ssh_config` (Debian-specific)
- Troubleshooting común (host key verification, permission denied, timeouts)

**Incluye**:

- ✅ Diagrama Mermaid: Secuencia completa conexión SSH Ansible → Remoto
- ✅ Checklist producción
- ✅ Ejemplos configuración Debian 12

---

### [02 — Lab Docker Compose: Ansible + SSH](02-docker-ansible-lab.md)

**Lab práctico ejecutable** con entorno multi-host usando Docker Compose.

**Arquitectura del Lab**:

- `ansible-control`: Container con Ansible
- `host-local`: Target SSH directo
- `bastion`: Host intermediario
- `host-remoto`: Target accesible vía ProxyJump

**Temas cubiertos**:

- Setup completo con Docker Compose
- Inventory Ansible multi-host
- Playbooks de testing
- ProxyJump vs ProxyCommand
- ControlMaster benchmarks

**Incluye**:

- ✅ Dockerfiles completos (Debian 12)
- ✅ Scripts de generación de claves SSH
- ✅ Diagrama Mermaid: Docker networking + SSH
- ✅ Comandos `make lab1-*` ejecutables
- ✅ Ejercicios propuestos (4 ejercicios)

---

### [03 — SSH sobre Túneles VPN: Fundamentos](03-ssh-vpn-basics.md)

**Teoría y práctica** de SSH sobre VPN en producción.

**Temas cubiertos**:

- ¿Por qué SSH sobre VPN? (ventajas vs SSH directo)
- Comparación técnica: WireGuard vs OpenVPN (2026)
- Arquitectura de layers (Application → VPN → Transport)
- Configuración WireGuard (cliente/servidor)
- Configuración OpenVPN
- SSH tunneling techniques (local/remote/dynamic forwarding)
- ProxyCommand para VPN gateways
- ControlPersist + VPN (performance)
- Networking Debian: interfaces, routing, DNS
- Hardening `sshd_config`
- iptables forwarding rules

**Incluye**:

- ✅ Configs completos WireGuard + OpenVPN
- ✅ Diagrama Mermaid: Control → VPN Pod → Remoto
- ✅ Troubleshooting VPN + SSH (9 problemas comunes)
- ✅ Benchmarks ControlMaster (8x speedup)

---

### [04 — Lab VPN Tunnel: WireGuard + Ansible](04-vpn-tunnel-lab.md)

**Lab avanzado ejecutable** que simula la arquitectura Kubernetes real con VPN sidecar.

**Arquitectura del Lab**:

- `wireguard-server`: VPN gateway (simula producción)
- `vpn-client`: Sidecar WireGuard client
- `ansible-control`: Comparte netns con vpn-client (simula K8s Pod)
- `bastion`, `target1`, `target2`: Hosts SSH en red privada VPN

**Características únicas**:

- ✅ Simula **native sidecar containers** de Kubernetes
- ✅ `network_mode: service:vpn-client` (shared netns)
- ✅ Healthcheck VPN antes de Ansible execution
- ✅ initContainers flow completo

**Temas cubiertos**:

- Setup completo WireGuard server/client con Docker
- Generación automática de keys WireGuard + SSH
- Scripts de validación de conectividad
- Alternativa OpenVPN (PKI setup)
- MTU optimization
- Latency simulation

**Incluye**:

- ✅ Diagrama Mermaid: Secuencia initContainers (30 steps)
- ✅ Scripts bash completos (generate-keys, test-connectivity)
- ✅ Comandos `make lab2-*` ejecutables
- ✅ Ejercicios avanzados (3 ejercicios: multi-subnet, latency, failover)

---

### [05 — SSH Parameters Reference](05-ssh-params-reference.md)

**Referencia técnica completa** de parámetros SSH para Ansible + VPN (2026).

**Secciones**:

1. **Ansible SSH Variables**: Todas las variables Ansible que controlan SSH
2. **OpenSSH Client Options**: Referencia completa de `ssh_config`
3. **Multiplexing y Performance**: ControlMaster deep dive
4. **Timeouts y Keepalives**: Cálculos y valores óptimos VPN
5. **Security Hardening**: Configs 2026 (ChaCha20-Poly1305, Ed25519)
6. **VPN-Specific Parameters**: Optimizaciones WireGuard vs OpenVPN
7. **ExternalSecrets Integration**: Vault → ESO → K8s Secret → Pod
8. **Debian 12 Troubleshooting**: 7 problemas comunes y soluciones
9. **Tabla Resumen**: Valores recomendados producción 2026
10. **Ejemplos Completos**: Inventories, playbooks, debug

**Incluye**:

- ✅ 30+ tablas de parámetros con valores recomendados
- ✅ Diagramas ExternalSecrets flow
- ✅ Scripts automation (generate-known-hosts, upload-to-vault)
- ✅ Checklist final producción (13 items)

---

## 🚀 Quick Start

### Prerequisitos

```bash
# Debian 12 Bookworm
sudo apt-get update
sudo apt-get install -y \
    docker.io \
    docker-compose-plugin \
    make \
    wireguard \
    wireguard-tools \
    openssh-client \
    ansible-core

# Verificar versiones
docker --version          # 24.0+
ansible --version         # 2.16+
wg --version              # WireGuard tools
```

### Lab 1: Docker SSH Basic

```bash
# Clonar repo
git clone https://github.com/YOURORG/kubernetes-job-over-VPN.git
cd kubernetes-job-over-VPN

# Generar claves SSH (necesario la primera vez)
make lab-setup

# Levantar containers SSH
make ssh-lab-up

# Test de conexión SSH manual
make ssh-test-connection

# Test Ansible ping
make ssh-test-ansible

# Shell interactivo en el cliente SSH
make ssh-lab-shell
```

### Lab 2: VPN Tunnel Advanced

```bash
# Setup Lab 2 (genera claves WireGuard + SSH)
make lab-setup

# Levantar VPN + remote-host
make lab-up

# Test conectividad SSH sobre VPN
make lab-test

# Shell en remote-host (host destino Ansible)
make lab-shell

# Shell en contenedor Ansible (para ejecutar playbooks)
make dev-shell

# Ver logs
make lab-logs

# Limpiar
make lab-down
make lab-clean
```

---

## 🛠️ Comandos Make Disponibles

### Lab 1 (Docker SSH Basic)

| Comando                    | Descripción                                       |
| -------------------------- | ------------------------------------------------- |
| `make lab-setup`           | Setup inicial (genera SSH keys, ejecutar una vez) |
| `make ssh-lab-up`          | Inicia containers (servidor + cliente SSH)        |
| `make ssh-test-connection` | Test de conexión SSH manual                       |
| `make ssh-test-ansible`    | Test Ansible ping module                          |
| `make ssh-lab-shell`       | Shell interactivo en ssh-client                   |
| `make ssh-lab-down`        | Para containers                                   |
| `make ssh-lab-reset`       | Reinicia containers (down + up)                   |
| `make ssh-lab-logs`        | Sigue logs en tiempo real                         |

### Lab 2 (VPN Tunnel Advanced)

| Comando              | Descripción                                     |
| -------------------- | ----------------------------------------------- |
| `make lab-setup`     | Setup completo (SSH + WireGuard keys + configs) |
| `make lab-up`        | Inicia stack completo (VPN server + remote-host)|
| `make lab-test`      | Test conectividad VPN (ping through WireGuard)  |
| `make lab-shell`     | Shell en remote-host (host destino Ansible)     |
| `make dev-shell`     | Shell en contenedor Ansible (ejecutar playbooks)|
| `make lab-vpn-status`| Estado WireGuard (`wg show`)                    |
| `make lab-down`      | Para todos los servicios                        |
| `make lab-clean`     | Limpia todo (keys + configs + containers)       |
| `make lab-logs`      | Logs combinados en tiempo real                  |

---

## 📊 Diagramas Mermaid

Todos los documentos incluyen **diagramas Mermaid editables** visualizando:

1. **Flujo SSH Ansible**: Secuencia completa desde inventory parsing hasta task execution
2. **Docker Networking**: Bridge networks, network_mode, port mapping
3. **VPN Architecture**: Layers OSI, encapsulation IP-in-UDP
4. **InitContainers Flow**: Simulación K8s native sidecars con Docker Compose
5. **ExternalSecrets**: Vault → ESO → K8s Secret → Pod mounting

---

## 🎓 Progresión de Aprendizaje

### Nivel 1: Fundamentos (1-2 horas)

1. Leer [01-ansible-ssh-principles.md](01-ansible-ssh-principles.md)
2. Ejecutar Lab 1: `make ssh-lab-up && make ssh-test-connection`
3. Experimentar con variables Ansible en inventory

**Objetivo**: Entender flujo SSH básico de Ansible

---

### Nivel 2: VPN Integration (2-3 horas)

1. Leer [03-ssh-vpn-basics.md](03-ssh-vpn-basics.md)
2. Comparar WireGuard vs OpenVPN
3. Practicar configs WireGuard manuales

**Objetivo**: Comprender arquitectura VPN + SSH

---

### Nivel 3: Hands-On VPN Lab (3-4 horas)

1. Leer [04-vpn-tunnel-lab.md](04-vpn-tunnel-lab.md)
2. Ejecutar Lab 2 completo: `make lab-setup && make lab-up`
3. Analizar estado WireGuard: `make lab-vpn-status`
4. Hacer ejercicios avanzados (latency simulation, multi-subnet)

**Objetivo**: Dominar troubleshooting VPN + Ansible

---

### Nivel 4: Producción (2-3 horas)

1. Leer [05-ssh-params-reference.md](05-ssh-params-reference.md)
2. Implementar ExternalSecrets integration
3. Aplicar hardening configs (sshd_config + ssh_config)
4. Setup monitoring (journalctl → Fluentd/Loki)

**Objetivo**: Deployment production-ready

---

## 🔧 Troubleshooting

### Problema: Docker no puede cargar module wireguard

```bash
sudo modprobe wireguard
lsmod | grep wireguard

# Si falla, instalar headers:
sudo apt-get install linux-headers-$(uname -r) wireguard-dkms
```

### Problema: Permisos denegados en SSH keys

```bash
# Las claves deben tener permisos 600
chmod 600 lab1/ssh-keys/id_ed25519
chmod 600 lab2/keys/ssh/id_ed25519
```

### Problema: Containers no arrancan

```bash
# Ver logs detallados
docker compose -f lab2/docker-compose.yml logs

# Verificar networks
docker network ls
docker network inspect lab2_private-net

# Recrear todo
make lab2-down
make lab2-clean
make lab2-setup
make lab2-up
```

---

## 📚 Referencias Externas

- [Ansible Official Docs](https://docs.ansible.com/)
- [WireGuard Official](https://www.wireguard.com/)
- [OpenSSH Man Pages](https://man.openbsd.org/)
- [Debian Networking Guide](https://www.debian.org/doc/manuals/debian-reference/ch05.en.html)
- [External Secrets Operator](https://external-secrets.io/)
- [Kubernetes Native Sidecars](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)

---

## 🤝 Contribuciones

Este es un **repositorio educativo**. Contribuciones bienvenidas:

1. Fork del repo
2. Crear branch: `git checkout -b feature/mejora-lab2`
3. Commit cambios: `git commit -am 'Add: ejercicio VPN failover'`
4. Push: `git push origin feature/mejora-lab2`
5. Crear Pull Request

---

## 📝 Licencia

Ver [LICENSE](../../LICENSE) en la raíz del repositorio.

---

## ✅ Checklist Completitud Labs

### Lab 1: Docker SSH

- [x] Dockerfiles (ansible-control, ssh-target)
- [x] docker-compose.yml
- [x] Script generate-keys.sh
- [x] Inventory Ansible
- [x] Playbook test-ssh.yml
- [x] Targets Makefile
- [x] Documentación completa
- [x] Diagrama Mermaid

### Lab 2: VPN Tunnel

- [x] Dockerfiles (wireguard-server, vpn-client, ansible-control, ssh-target)
- [x] docker-compose.yml con network_mode
- [x] Scripts generación keys WireGuard
- [x] Scripts generación configs WireGuard
- [x] Healthcheck VPN
- [x] wait-for-vpn.sh script
- [x] Inventory Ansible VPN
- [x] Playbook test-vpn.yml
- [x] Targets Makefile
- [x] Documentación completa
- [x] Diagrama Mermaid secuencia initContainers
- [x] Alternativa OpenVPN
- [x] Troubleshooting guide

### Documentación

- [x] 01-ansible-ssh-principles.md (fundamentos + diagrama)
- [x] 02-docker-ansible-lab.md (lab básico + diagrama)
- [x] 03-ssh-vpn-basics.md (VPN theory + configs + diagrama)
- [x] 04-vpn-tunnel-lab.md (lab VPN avanzado + diagrama + ejercicios)
- [x] 05-ssh-params-reference.md (referencia completa + ExternalSecrets)
- [x] README.md (este archivo índice)

---

## 🎯 Próximos Pasos

Después de completar este módulo, explora:

1. **Integración K8s real**: Migrar Lab 2 a Kubernetes con Helm charts
2. **ArgoCD GitOps**: Setup pipeline CI/CD completo
3. **Monitoring**: Prometheus + Grafana dashboards para SSH metrics
4. **Security**: Implementar cert-based SSH (no keys)
5. **Multi-VPN**: Failover entre múltiples VPN gateways

---

**¡Happy Learning! 🚀**

Para preguntas o issues, abre un issue en el repositorio GitHub.
