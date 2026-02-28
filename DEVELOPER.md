# Developer Guide

Guía de referencia para contribuir y trabajar con el proyecto localmente. Para arquitectura general y quick start consulta [README.md](README.md).

---

## Tabla de contenidos

1. [Entorno de desarrollo](#1-entorno-de-desarrollo)
2. [Flujo Git y ramas](#2-flujo-git-y-ramas)
3. [Desarrollo local con Docker Compose](#3-desarrollo-local-con-docker-compose)
4. [Modificar playbooks Ansible](#4-modificar-playbooks-ansible)
5. [Modificar el chart Helm](#5-modificar-el-chart-helm)
6. [Modificar las imágenes Docker](#6-modificar-las-imágenes-docker)
7. [Añadir un nuevo entorno](#7-añadir-un-nuevo-entorno)
8. [Debugging](#8-debugging)
9. [Convenciones y estándares](#9-convenciones-y-estándares)
10. [CI/CD explicado](#10-cicd-explicado)

---

## 1. Entorno de desarrollo

### Herramientas requeridas

| Herramienta    | Versión mínima     | Uso                             |
| -------------- | ------------------ | ------------------------------- |
| Docker         | 24+                | Build + dev local               |
| docker compose | v2 (plugin)        | Simular Pod K8s localmente      |
| helm           | 3.14+              | Lint y render de templates      |
| kubectl        | 1.28+              | Interacción con cluster         |
| yq             | 4+                 | Actualizar tags en values files |
| argocd CLI     | 2.10+              | Sync y diff contra cluster      |
| ansible        | ansible-core 2.17+ | vault-edit local (opcional)     |

```bash
# macOS
brew install helm kubectl yq argocd docker

# Debian/Ubuntu
apt install wireguard-tools
snap install kubectl --classic
snap install helm --classic
```

### Variables de entorno opcionales

Crea un archivo `.env` en la raíz (está en `.gitignore`) para sobreescribir defaults del Makefile:

```bash
# .env  — NO commitear
ARGOCD_SERVER=argocd.mi-cluster.example.com
ARGOCD_TOKEN=<token>
ANSIBLE_PLAYBOOK=playbooks/site.yml
ANSIBLE_VERBOSITY=3
```

El Makefile no carga `.env` automáticamente; expórtalo antes o prefíjalo:

```bash
export $(cat .env | xargs) && make dev-up
# o
ARGOCD_SERVER=argocd.mi-cluster.com make argocd-status
```

---

## 2. Flujo Git y ramas

### Modelo de ramas

```
main      ← producción (sync MANUAL en ArgoCD)
staging   ← staging (sync automático con gate de aprobación)
develop   ← dev (sync automático, prune + selfHeal)
feature/* ← ramas de trabajo → merge a develop vía PR
fix/*     ← bug fixes → merge a develop vía PR
```

### Flujo típico

```bash
# 1. Crear rama de feature desde develop
git checkout develop && git pull
git checkout -b feature/mi-cambio

# 2. Desarrollar + probar localmente
make dev-up

# 3. Validar
make ci                     # helm lint + yamllint

# 4. PR a develop → se dispara sync automático en dev
git push origin feature/mi-cambio
# Abrir PR en GitHub contra develop

# 5. Promover a staging
git checkout staging && git merge develop && git push
# CI gate: requiere 1 revisor en GH Environment "staging"

# 6. Promover a prod
git checkout main && git merge staging && git push
# CI gate: requiere 2 revisores + wait timer 5min
make prod-approve           # confirma diff + sync interactivo
```

### Commits

Usar [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new Ansible role for nginx
fix: correct WireGuard healthcheck timeout
chore: bump ansible-core to 2.17.8
ci: update image tags to abc1234 [skip ci]   ← generado automáticamente por CI
```

---

## 3. Desarrollo local con Docker Compose

El `docker-compose.yml` replica la arquitectura del Pod K8s: el contenedor `ansible` comparte el namespace de red del contenedor `vpn` (`network_mode: service:vpn`), igual que en Kubernetes.

### Primer setup (una sola vez)

```bash
make dev-setup
# Crea test/vpn/wg0.conf y test/secrets/vault-password desde los .example
# ⚠  Luego crea test/secrets/ssh-private-key (ver abajo)

ssh-keygen -t ed25519 -f test/secrets/ssh-private-key -N ""
# O copia una clave existente:
cp ~/.ssh/ansible_ed25519 test/secrets/ssh-private-key && chmod 600 test/secrets/ssh-private-key
```

### Modo no-op (sin servidor WireGuard)

El sidecar VPN entra automáticamente en modo no-op si `wg0.conf` contiene placeholders. No es necesario ninguna configuración extra:

```bash
make dev-up
# VPN: modo no-op (sleep, healthcheck pasa vía /tmp/vpn-ready)
# Ansible: ejecuta playbook, falla en SSH (hosts no accesibles) — comportamiento esperado
```

### Modo completo (con servidor WireGuard real)

```bash
# Editar test/vpn/wg0.conf con valores reales
make dev-up
make dev-vpn-status    # verifica interfaz wg0
```

### Comandos útiles en dev

```bash
make dev-logs          # logs combinados (vpn + ansible)
make dev-shell         # bash en ansible-executor con VPN activa
make dev-down          # para y limpia contenedores

# Ejecutar un playbook distinto sin rebuild:
ANSIBLE_PLAYBOOK=playbooks/site.yml make dev-up

# Aumentar verbosity:
ANSIBLE_VERBOSITY=4 make dev-up
```

### Perfiles Docker Compose

| Perfil | Servicio                                    | Uso                                        |
| ------ | ------------------------------------------- | ------------------------------------------ |
| `dev`  | `vpn` + `ansible` (restart: unless-stopped) | Desarrollo interactivo                     |
| `run`  | `vpn` + `ansible-run` (restart: no)         | One-shot, reproduce comportamiento K8s Job |

```bash
# One-shot (más parecido al Job K8s):
docker compose --profile run up --abort-on-container-exit
```

---

## 4. Modificar playbooks Ansible

### Estructura

```
ansible/
├── ansible.cfg                     # configuración global
├── requirements.yml                # colecciones pre-instaladas en imagen
├── inventories/
│   ├── dev/hosts.ini + group_vars/
│   ├── staging/
│   └── prod/
├── playbooks/
│   ├── test-connectivity.yml       # smoke test
│   └── site.yml                    # playbook principal
├── roles/common/
└── vault/secrets.yml               # cifrado con ansible-vault (NO .example)
```

### Añadir un playbook nuevo

1. Crear `ansible/playbooks/mi-playbook.yml`
2. Probar localmente:
   ```bash
   ANSIBLE_PLAYBOOK=playbooks/mi-playbook.yml make dev-up
   ```
3. Si debe ejecutarse por defecto, actualizar `helm/ansible-job/values.yaml`:
   ```yaml
   ansible:
     playbook: playbooks/mi-playbook.yml
   ```
4. Para un entorno específico, actualizar el values file del entorno:
   ```yaml
   # helm/ansible-job/values-staging.yaml
   ansible:
     playbook: playbooks/mi-playbook.yml
   ```

### Añadir una colección Ansible

```yaml
# ansible/requirements.yml
collections:
  - name: community.general
    version: ">=9.0"
  - name: mi.coleccion # nueva
    version: "1.2.3"
```

La colección se instalará en el próximo build de imagen (stage `python-builder`). **No** se necesita acceso a red en runtime.

### Secretos con ansible-vault

```bash
make vault-edit            # abre editor con decrypt/re-encrypt automático
make vault-view            # muestra contenido sin escribir a disco

# Referenciar en playbook:
- name: Use secret
  debug:
    msg: "{{ vault_my_secret }}"
```

El fichero `ansible/vault/secrets.yml` está en `.gitignore` **sin cifrar**. Solo commitear la versión cifrada (ansible-vault produce el mismo fichero en su lugar).

---

## 5. Modificar el chart Helm

### Render y lint

```bash
make helm-lint                  # lint todos los entornos
make helm-template-dev          # render dev → stdout (revisar antes de aplicar)
make helm-template-staging
make helm-template-prod

# Diff contra ArgoCD (requiere cluster):
make argocd-diff-dev
```

### Estructura de values

Los values se fusionan en orden: `values.yaml` (base) ← `values-ENV.yaml` (override).

```yaml
# values.yaml — defaults comunes a todos los entornos
job:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 2

vpn:
  image:
    repository: ghcr.io/VanOps/k8s-vpn-sidecar
    tag: latest # ← CI actualiza este campo vía yq

ansible:
  image:
    repository: ghcr.io/VanOps/k8s-ansible-executor
    tag: latest
  playbook: playbooks/test-connectivity.yml
```

```yaml
# values-prod.yaml — solo overrides de prod
job:
  ttlSecondsAfterFinished: 86400 # 24h audit trail
ansible:
  inventory: inventories/prod
  playbook: playbooks/site.yml
```

### Añadir una variable nueva al chart

1. Añadir el valor con default en `values.yaml`
2. Referenciar en el template correspondiente (`templates/job.yaml`, etc.)
3. Overridear en los values files de entorno si es necesario
4. Ejecutar `make helm-lint` para validar

---

## 6. Modificar las imágenes Docker

### VPN sidecar (`docker/vpn/`)

- Base: Debian 12 slim + wireguard-tools
- Capabilities requeridas: `NET_ADMIN`, `SYS_MODULE`
- El `entrypoint.sh` detecta modo no-op automáticamente (placeholders en wg0.conf o `SKIP_VPN=true`)
- El `healthcheck.sh` comprueba `/tmp/vpn-ready` (funciona en modo no-op y real)

```bash
make build-vpn                  # build local con tag = git SHA corto
docker run --rm --cap-add NET_ADMIN k8s-vpn-sidecar:local wg --version
```

### Ansible executor (`docker/ansible/`)

- Base: Python 3.12 slim, multi-stage
- **Contexto de build**: raíz del repo (necesita acceder a `ansible/requirements.yml`)
- Las colecciones se instalan en stage `python-builder` → copiadas a `final`
- Usuario no-root UID 1000, capabilities: DROP ALL

```bash
make build-ansible
docker run --rm k8s-ansible-executor:local ansible --version
docker run --rm k8s-ansible-executor:local ansible-galaxy collection list
```

### Build multi-arch (CI)

CI construye `linux/amd64,linux/arm64` con `docker/build-push-action`. Para build local multi-arch:

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t k8s-vpn-sidecar:test ./docker/vpn
```

---

## 7. Añadir un nuevo entorno

Ejemplo: añadir entorno `qa`.

**1. Inventario Ansible**

```bash
mkdir -p ansible/inventories/qa
# Crear hosts.ini y group_vars/all.yml siguiendo el patrón de dev/
```

**2. Values Helm**

```bash
cp helm/ansible-job/values-dev.yaml helm/ansible-job/values-qa.yaml
# Editar: namespace, inventory, ttl, etc.
```

**3. ArgoCD Application**

```bash
cp argocd/apps/dev.yaml argocd/apps/qa.yaml
# Editar: name, namespace, targetRevision (rama), values file
```

**4. ExternalSecrets (si aplica)**

```bash
cp k8s/external-secrets/dev-external-secret.yaml k8s/external-secrets/qa-external-secret.yaml
# Editar: namespace, secretPath en AWS SM
```

**5. Lint**

```bash
helm lint helm/ansible-job/ -f helm/ansible-job/values-qa.yaml
```

**6. GitHub Environment** (Settings → Environments → New): `qa` con protecciones apropiadas.

---

## 8. Debugging

### Pod no arranca en K8s

```bash
# Ver estado del Job y del Pod
kubectl get jobs,pods -n ansible-jobs-dev
kubectl describe pod <pod-name> -n ansible-jobs-dev

# Logs por contenedor
make k8s-logs-dev           # ansible-executor
make k8s-logs-vpn-dev       # vpn-sidecar

# Si el Pod está en Pending: revisar resources/nodeSelector
kubectl get events -n ansible-jobs-dev --sort-by=.lastTimestamp
```

### VPN sidecar no pasa a healthy

```bash
# Local
docker compose --profile dev logs vpn

# K8s
kubectl logs -n ansible-jobs-dev <pod> -c vpn-sidecar

# Causas comunes:
# - wg0.conf con valores reales pero servidor inalcanzable → timeout
# - Falta CAP NET_ADMIN → "Operation not permitted"
# - Módulo wireguard no cargado en nodo → modprobe wireguard en el host
```

### Ansible falla con "Unreachable"

```bash
# Verificar conectividad desde el contenedor
make dev-shell
ping <ip-host-objetivo>       # debe responder por wg0
ssh -i /run/secrets/ssh-private-key ansible@<ip> -p 22

# Revisar inventario
cat ansible/inventories/dev/hosts.ini
cat ansible/inventories/dev/group_vars/all.yml
```

### ExternalSecrets no sincroniza

```bash
kubectl get externalsecret -n ansible-jobs-dev
kubectl describe externalsecret vpn-secrets -n ansible-jobs-dev
# Buscar: "store not ready" → revisar SecretStore + IRSA
# Buscar: "secret not found" → verificar path en AWS SM
```

### Helm diff inesperado en ArgoCD

```bash
make helm-template-dev | kubectl diff -f -
# o
make argocd-diff-dev
```

---

## 9. Convenciones y estándares

### YAML

- Indentación: **2 espacios** (sin tabs)
- Línea máxima: 160 caracteres (configurado en yamllint en `make ci`)
- Separador entre documentos en ficheros multi-doc: `---`

### Helm templates

- Labels estándar en todos los recursos: `app.kubernetes.io/*` (generados por `_helpers.tpl`)
- Nombres de recursos: `{{ include "ansible-job.fullname" . }}`
- Nunca hardcodear namespaces en templates; usar `.Release.Namespace`

### Seguridad — qué NO commitear

| Fichero                                  | Motivo                          |
| ---------------------------------------- | ------------------------------- |
| `test/vpn/wg0.conf`                      | Claves WireGuard reales         |
| `test/secrets/vault-password`            | Contraseña vault                |
| `test/secrets/ssh-private-key`           | Clave SSH privada               |
| `ansible/vault/secrets.yml` (sin cifrar) | Secretos Ansible                |
| `.argocd-token`                          | Token ArgoCD                    |
| `helm/ansible-job/values-local.yaml`     | Posibles overrides con secretos |

El `.gitignore` ya cubre todos estos casos. Revisar `git status` antes de cada commit.

### Imágenes Docker

- Siempre multi-stage: stage `builder` (compilación/instalación) → stage `final` (runtime mínimo)
- No instalar herramientas de debug en stage `final`
- Usuario no-root en todos los contenedores
- Sin secrets en el build context ni en ARGs

---

## 10. CI/CD explicado

### `build-push.yml` — Build de imágenes

Se dispara cuando cambia `docker/**` en cualquier push. Hace:

1. Build multi-arch (`amd64` + `arm64`) con caché GHA
2. Push a GHCR con tag `<short-sha>` + tag de rama + `latest` (solo en `main`)
3. En ramas `develop`/`staging`/`main`: actualiza los tags en `values-ENV.yaml` con `yq` y hace auto-commit `[skip ci]`

### `argocd-sync.yml` — Sync por entorno

Se dispara cuando cambia `helm/**` o `ansible/**`:

| Rama      | Entorno | Gate                                                    |
| --------- | ------- | ------------------------------------------------------- |
| `develop` | dev     | Sin aprobación                                          |
| `staging` | staging | GH Environment `staging` — 1 revisor                    |
| `main`    | prod    | GH Environment `production` — 2 revisores + 5 min delay |

### Añadir un check al CI local

```bash
make ci    # ejecuta: helm-lint + yamllint

# Para extender, editar el target `ci` en Makefile:
ci: helm-lint mi-nuevo-check
```

### Credenciales necesarias en GitHub

| Secret/Variable | Scope              | Uso                           |
| --------------- | ------------------ | ----------------------------- |
| `GITHUB_TOKEN`  | Automático         | Push a GHCR, auto-commit tags |
| `ARGOCD_SERVER` | Environment secret | URL del servidor ArgoCD       |
| `ARGOCD_TOKEN`  | Environment secret | Auth argocd CLI               |

Configurar en: **GitHub → Settings → Environments → `dev`/`staging`/`production`**
