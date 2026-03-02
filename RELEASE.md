# Release Flow

Este documento describe el flujo completo de release para `kubernetes-job-over-VPN`: desde un commit en una rama de feature hasta el despliegue en producción, incluyendo la validación GitOps con ArgoCD y el sistema de notificaciones.

---

## Índice

1. [Estrategia de ramas](#1-estrategia-de-ramas)
2. [Flujo de commits entre ramas](#2-flujo-de-commits-entre-ramas)
3. [Pipeline CI/CD por rama](#3-pipeline-cicd-por-rama)
4. [Validación GitOps con ArgoCD](#4-validación-gitops-con-argocd)
5. [Comportamiento de sync por entorno](#5-comportamiento-de-sync-por-entorno)
6. [Flujo de notificaciones](#6-flujo-de-notificaciones)
7. [Proceso de release de Ansible](#7-proceso-de-release-de-ansible)
8. [Rollback](#8-rollback)
9. [Referencia rápida de comandos](#9-referencia-rápida-de-comandos)

---

## 1. Estrategia de ramas

| Rama         | Entorno | Sync ArgoCD | Namespace              | Retención de pods |
| ------------ | ------- | ----------- | ---------------------- | ----------------- |
| `feature/**` | —       | —           | —                      | —                 |
| `develop`    | Dev     | Automático  | `ansible-jobs-dev`     | 30 min            |
| `staging`    | Staging | Semi-manual | `ansible-jobs-staging` | Sin TTL           |
| `main`       | Prod    | Manual      | `ansible-jobs-prod`    | 24 h              |

- **`feature/**`\*\*: trabajo de desarrollo. CI de compliance y seguridad.
- **`develop`**: integración continua. Despliegue automático en dev.
- **`staging`**: pre-producción. Requiere aprobación de GitHub environment antes del sync.
- **`main`**: producción. Requiere reviewers explícitos y sync manual con `argocd app sync`.

---

## 2. Flujo de commits entre ramas

```mermaid
gitGraph
   commit id: "init"

   branch develop
   checkout develop
   commit id: "feat: nueva tarea ansible"
   commit id: "fix: corregir playbook"

   branch feature/my-feature
   checkout feature/my-feature
   commit id: "wip: cambio experimental"
   commit id: "refactor: limpiar roles"

   checkout develop
   merge feature/my-feature id: "Merge PR → develop" tag: "CI: compliance + build"

   commit id: "ci: update image tags [skip ci]"

   checkout staging
   merge develop id: "Merge develop → staging" tag: "Gate: GH environment"

   commit id: "ci: update image tags staging [skip ci]"

   checkout main
   merge staging id: "Merge staging → main" tag: "Gate: required reviewers"

   commit id: "ci: update image tags prod [skip ci]"
   commit id: "ci: update prod artifact URL vX.Y.Z [skip ci]" tag: "Release vX.Y.Z"
```

### Reglas de promoción

```mermaid
flowchart LR
    subgraph dev ["🧑‍💻 Desarrollo"]
        F["feature/**"] -->|Pull Request| D["develop"]
    end

    subgraph stg ["🧪 Pre-producción"]
        D -->|Pull Request<br/>+ GitHub environment approval| S["staging"]
    end

    subgraph prd ["🚀 Producción"]
        S -->|Pull Request<br/>+ Required reviewers| M["main"]
        M -->|GitHub Release<br/>tag vX.Y.Z| R["Release Asset<br/>ansible-playbooks-vX.Y.Z.tar.gz"]
    end

    style dev fill:#e3f2fd,stroke:#1565c0
    style stg fill:#fff8e1,stroke:#f57f17
    style prd fill:#e8f5e9,stroke:#2e7d32
```

---

## 3. Pipeline CI/CD por rama

### 3.1 Flujo completo de CI/CD

```mermaid
flowchart TD
    subgraph triggers ["Eventos de trigger"]
        E1["push: feature/**<br>push: develop"]
        E2["PR → staging<br>PR → main"]
        E3["push: main<br>docker/** changes"]
        E4["GitHub Release<br>published"]
    end

    subgraph compliance ["ci-ai-compliance.yaml"]
        C1["ScanCode<br>(Licencias)"]
        C2["ORT<br>(Compliance)"]
        C3["TruffleHog<br>(Secrets)"]
        C1 --> C2 --> C3
    end

    subgraph build ["build-push.yml"]
        B1["Build VPN Sidecar<br>ghcr.io/.../k8s-vpn-sidecar:SHA"]
        B2["Build Ansible Executor<br>ghcr.io/.../k8s-ansible-executor:SHA"]
        B3["Update helm values<br>values-ENV.yaml ← SHA<br>commit [skip ci]"]
        B1 & B2 --> B3
    end

    subgraph release ["release-ansible.yml"]
        R1["Package ansible/<br>ansible-playbooks-vX.Y.Z.tar.gz"]
        R2["Upload to<br>GitHub Release"]
        R3["Update values-prod.yaml<br>artifact URL<br>commit [skip ci]"]
        R1 --> R2 --> R3
    end

    E1 --> compliance
    E2 --> compliance
    E3 --> build
    E4 --> release

    build -->|ArgoCD polling 3 min| ARGO["ArgoCD detecta drift<br>→ Sync"]
    release -->|ArgoCD sync manual| ARGO
```

### 3.2 Qué workflow se ejecuta en cada rama

| Evento                             | `ci-ai-compliance` | `build-push` | `release-ansible` |
| ---------------------------------- | :----------------: | :----------: | :---------------: |
| Push a `feature/**`                |         ✅         |      —       |         —         |
| Push a `develop`                   |         ✅         |      —       |         —         |
| PR hacia `staging` o `main`        |         ✅         |      —       |         —         |
| Push a `main` (cambios en docker/) |         —          |      ✅      |         —         |
| GitHub Release publicado           |         —          |      —       |        ✅         |

> El workflow `build-push.yml` actualmente se dispara solo en `main`. Los tags de imagen en `values-dev.yaml` y `values-staging.yaml` se actualizan manualmente o extendiendo el trigger a `develop` y `staging`.

---

## 4. Validación GitOps con ArgoCD

### 4.1 Arquitectura App-of-Apps

```mermaid
flowchart TD
    subgraph github ["GitHub (branch: main)"]
        AOA["argocd/app-of-apps.yaml<br>Application: ansible-gitops"]
        APPS["argocd/apps/<br>├── dev.yaml<br>├── staging.yaml<br>└── prod.yaml"]
        AOA -->|targetRevision: main<br>path: argocd/apps| APPS
    end

    subgraph argocd ["ArgoCD (namespace: argocd)"]
        ROOT["ansible-gitops<br>(App-of-Apps)<br>auto prune + selfHeal"]
        DEV["ansible-job-dev<br>branch: develop<br>AUTO sync"]
        STG["ansible-job-staging<br>branch: staging<br>SEMI-AUTO sync"]
        PRD["ansible-job-prod<br>branch: main<br>MANUAL sync"]
        ROOT --> DEV & STG & PRD
    end

    subgraph k8s ["Kubernetes"]
        NS_DEV["ansible-jobs-dev"]
        NS_STG["ansible-jobs-staging"]
        NS_PRD["ansible-jobs-prod"]
        DEV -->|Helm: values.yaml<br>values-dev.yaml| NS_DEV
        STG -->|Helm: values.yaml<br>values-staging.yaml| NS_STG
        PRD -->|Helm: values.yaml<br>values-prod.yaml| NS_PRD
    end

    style ROOT fill:#fff4e6,stroke:#e65100
    style DEV fill:#e3f2fd,stroke:#1565c0
    style STG fill:#fff8e1,stroke:#f57f17
    style PRD fill:#e8f5e9,stroke:#2e7d32
```

### 4.2 Ciclo de vida de un Job en Kubernetes

Cada Application despliega un `Kubernetes Job` con patrón sidecar:

```mermaid
sequenceDiagram
    participant AC as ArgoCD
    participant K8s as Kubernetes
    participant GS as git-sync (init)
    participant VPN as vpn (native sidecar)
    participant ANS as ansible (main)
    participant HOST as Remote Host (SSH)

    AC->>K8s: Sync Wave 0: ConfigMaps, Secrets, SA, RBAC
    AC->>K8s: PostSync Hook (BeforeHookCreation): borra Job anterior
    AC->>K8s: Sync Wave 1: crea nuevo Job

    K8s->>GS: inicia git-sync
    GS-->>ANS: clona repo → /workspace
    GS->>K8s: exit 0 (init completo)

    K8s->>VPN: inicia vpn sidecar (restartPolicy: Always)
    VPN-->>ANS: levanta wg0 (WireGuard tunnel)

    K8s->>ANS: inicia ansible-executor
    ANS->>ANS: espera wg0 activo
    ANS->>HOST: ejecuta playbook vía SSH/WireGuard (10.10.20.0/24)
    HOST-->>ANS: respuesta SSH
    ANS->>K8s: exit 0/1 (éxito o fallo)
    K8s->>AC: Job Succeeded / Failed
```

---

## 5. Comportamiento de sync por entorno

### 5.1 Dev — Sync Automático

```mermaid
flowchart TD
    A["Push a develop"] -->|git push| B["GitHub Actions<br>CI Compliance"]
    B -->|pass| C["ArgoCD polling<br>cada 3 min"]
    C -->|drift detectado| D["Auto-Sync<br>prune=true · selfHeal=true"]
    D --> E["Wave 0: recursos base"]
    E --> F["PostSync: borra Job anterior<br>BeforeHookCreation"]
    F --> G["Wave 1: nuevo Job"]
    G --> H["Ansible ejecuta<br>playbooks/test-connectivity.yml"]
    H -->|éxito| I["✅ Healthy<br>TTL: 30 min"]
    H -->|fallo| J["❌ backoffLimit: 3<br>retry automático"]

    style A fill:#e3f2fd
    style D fill:#bbdefb
    style I fill:#c8e6c9
    style J fill:#ffcdd2
```

**Características clave:**

- `prune: true` — elimina recursos obsoletos de Git
- `selfHeal: true` — re-sincroniza si el clúster deriva del estado de Git
- `Replace: true` — fuerza recreación de Jobs (campos inmutables)
- `retry.limit: 5` con backoff exponencial

### 5.2 Staging — Sync Semi-manual

```mermaid
flowchart TD
    A["PR develop → staging<br>aprobado y mergeado"] --> B["GitHub<br>environment: staging<br>Protection rules"]
    B -->|aprobación humana| C["Merge a staging"]
    C --> D["ArgoCD detecta drift<br>(no auto-sync)"]
    D --> E{"¿Acción requerida?"}
    E -->|CI trigger / manual| F["argocd app sync<br>ansible-job-staging"]
    E -->|sin acción| G["Estado: OutOfSync<br>(sin despliegue)"]
    F --> H["Sync con retry.limit: 3"]
    H -->|éxito| I["✅ Synced + Healthy<br>Slack: devops-staging"]
    H -->|fallo| J["❌ Sync Failed<br>Slack: devops-alerts"]

    style A fill:#fff8e1
    style B fill:#ffe0b2
    style I fill:#c8e6c9
    style J fill:#ffcdd2
```

**Características clave:**

- `prune: false` — no elimina recursos automáticamente (requiere acción explícita)
- `selfHeal: false` — detecta drift pero no lo corrige
- La sincronización efectiva requiere trigger manual o de CI
- `retry.limit: 3` — menos reintentos que dev

### 5.3 Prod — Sync Manual

```mermaid
flowchart TD
    A["PR staging → main<br>Required reviewers aprobados"] --> B["Merge a main"]
    B --> C["ArgoCD detecta drift<br>modo MANUAL únicamente"]
    C --> D{"Gate de producción"}
    D -->|aprobación + make prod-approve| E["argocd app sync ansible-job-prod<br>--grpc-web"]
    D -->|sin acción| F["OutOfSync indefinido<br>(sin despliegue)"]
    E --> G["Sync con retry.limit: 1<br>fail-fast"]
    G -->|éxito| H["✅ Deployed<br>TTL pods: 24h<br>Slack: devops-prod"]
    G -->|fallo| I["❌ Fallo<br>Slack: devops-critical<br>Revisar logs 24h"]

    style A fill:#e8f5e9
    style D fill:#ffccbc
    style H fill:#c8e6c9
    style I fill:#ffcdd2
```

**Características clave:**

- Sin bloque `automated` — sync 100% manual
- `retry.limit: 1` — falla rápido, no reintenta a ciegas
- Pods retenidos 24h (`ttlSecondsAfterFinished: 86400`) para inspección de logs
- Historial de syncs visible en ArgoCD UI y `argocd app history`

---

## 6. Flujo de notificaciones

### 6.1 Canales configurados por entorno

| Entorno | Evento               | GitHub Status | Slack channel     |
| ------- | -------------------- | :-----------: | ----------------- |
| Dev     | `on-sync-running`    |  ⏳ pending   | —                 |
| Dev     | `on-deployed`        |  ✅ success   | —                 |
| Dev     | `on-sync-failed`     |  ❌ failure   | `devops-alerts`   |
| Dev     | `on-health-degraded` |  ❌ failure   | `devops-alerts`   |
| Staging | `on-sync-running`    |  ⏳ pending   | `devops-staging`  |
| Staging | `on-sync-succeeded`  |  ✅ success   | `devops-staging`  |
| Staging | `on-deployed`        |  ✅ success   | —                 |
| Staging | `on-sync-failed`     |  ❌ failure   | `devops-alerts`   |
| Staging | `on-health-degraded` |  ❌ failure   | `devops-alerts`   |
| Prod    | `on-sync-running`    |  ⏳ pending   | `devops-prod`     |
| Prod    | `on-sync-succeeded`  |  ✅ success   | `devops-prod`     |
| Prod    | `on-deployed`        |  ✅ success   | —                 |
| Prod    | `on-sync-failed`     |  ❌ failure   | `devops-critical` |
| Prod    | `on-health-degraded` |  ❌ failure   | `devops-critical` |

### 6.2 Secuencia de notificación completa

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant AC as ArgoCD Controller
    participant NC as Notifications Controller
    participant Auth as GitHub Auth<br/>(PAT o GitHub App)
    participant API as GitHub Commit Status API
    participant SL as Slack

    Dev->>GH: git push origin staging

    GH->>AC: Polling detecta nuevo commit
    AC->>AC: Calcula drift (OutOfSync)

    note over AC,NC: Trigger: on-sync-running
    AC->>NC: Evento sync iniciado
    NC->>Auth: Solicita credenciales
    Auth-->>NC: Token (temporal/persistente)
    NC->>API: POST /repos/.../statuses/{SHA}<br/>state: "pending"
    API->>GH: ⏳ Commit status: pending

    alt Sync Exitoso
        AC->>NC: Evento: on-sync-succeeded / on-deployed
        NC->>API: POST /statuses/{SHA}<br/>state: "success"
        API->>GH: ✅ Commit status: success
        NC->>SL: Mensaje a #devops-staging
        GH->>Dev: Check verde en PR/commit
    else Sync Fallido
        AC->>NC: Evento: on-sync-failed
        NC->>API: POST /statuses/{SHA}<br/>state: "failure"
        API->>GH: ❌ Commit status: failure
        NC->>SL: Alerta a #devops-alerts
        GH->>Dev: Check rojo en PR/commit
    else Health Degraded
        AC->>NC: Evento: on-health-degraded
        NC->>API: POST /statuses/{SHA}<br/>state: "failure"
        API->>GH: ❌ Commit status: failure (health)
        NC->>SL: Alerta a #devops-alerts / #devops-critical
    end
```

### 6.3 Métodos de autenticación para GitHub Notifications

```mermaid
flowchart LR
    subgraph pat ["Método 1: Personal Access Token"]
        P1["Crear PAT en GitHub<br>scope: repo:status"]
        P2["kubectl create secret<br>argocd-notifications-secret<br>github-token=PAT"]
        P3["ConfigMap:<br>service.webhook.github-status"]
        P1 --> P2 --> P3
    end

    subgraph app ["Método 2: GitHub App (Recomendado prod)"]
        A1["Crear GitHub App<br>en github.com/settings/apps"]
        A2["kubectl create secret<br>github-app-id<br>github-app-installation-id<br>github-app-private-key"]
        A3["ConfigMap:<br>service.github (App JWT)"]
        A1 --> A2 --> A3
    end

    P3 -->|dev/testing| USE["ArgoCD Notifications<br>Controller"]
    A3 -->|staging/prod| USE

    style pat fill:#e3f2fd,stroke:#1565c0
    style app fill:#e8f5e9,stroke:#2e7d32
```

| Característica | PAT                    | GitHub App             |
| -------------- | ---------------------- | ---------------------- |
| Setup          | ⚡ 5 minutos           | ⏱️ 15-20 minutos       |
| Expiración     | ⚠️ Máx. 1 año          | ✅ No expira           |
| Permisos       | 🔓 Amplios (todo repo) | 🔒 Granulares (status) |
| Auditabilidad  | Usuario personal       | `App[bot]`             |
| Ideal para     | Dev / Testing          | Staging / Producción   |

---

## 7. Proceso de release de Ansible

Un **GitHub Release** (tag `vX.Y.Z`) desencadena el empaquetado de los playbooks para producción:

```mermaid
flowchart TD
    A["Crear GitHub Release<br>tag: vX.Y.Z desde main"] --> B["Workflow: release-ansible.yml<br>Trigger: release published"]

    B --> C["Checkout del tag vX.Y.Z"]
    C --> D["Build tarball<br>ansible-playbooks-vX.Y.Z.tar.gz<br>(excluye inventories/dev<br>y vault/secrets.yml)"]
    D --> E["Upload asset<br>al GitHub Release"]
    E --> F["Actualizar values-prod.yaml<br>releaseArtifact.url ← nueva URL<br>commit [skip ci] a main"]

    F --> G["ArgoCD detecta cambio<br>en values-prod.yaml"]
    G --> H{"Gate prod"}
    H -->|aprobación manual| I["argocd app sync<br>ansible-job-prod"]
    I --> J["Init container descarga<br>ansible-playbooks-vX.Y.Z.tar.gz<br>desde GitHub Release"]
    J --> K["Job ejecuta playbook<br>desde artifact (sin git-sync)"]

    style A fill:#e8f5e9
    style D fill:#f3e5f5
    style E fill:#e8eaf6
    style J fill:#e0f2f1
    style K fill:#c8e6c9
```

**¿Por qué usar release artifacts en producción?**

- Los playbooks están versionados e inmutables (sin git-sync dinámico)
- Prod descarga exactamente `vX.Y.Z`, no la punta de la rama
- Permite rollback descargando un tag anterior sin tocar Git
- `gitSync.enabled: false` en `values-prod.yaml`

---

## 8. Rollback

### Por entorno

```mermaid
flowchart LR
    subgraph dev_rb ["Dev — Rollback"]
        D1["argocd app rollback<br>ansible-job-dev ID"]
        D2["⚠️ selfHeal=true<br>ArgoCD re-sync al HEAD"]
        D1 --> D2
        D3["Alternativa permanente:<br>git revert en develop"]
    end

    subgraph stg_rb ["Staging — Rollback"]
        S1["argocd app rollback<br>ansible-job-staging ID"]
        S2["✅ selfHeal=false<br>Rollback persiste"]
        S1 --> S2
    end

    subgraph prd_rb ["Prod — Rollback"]
        P1["Opción A:<br>argocd app rollback<br>ansible-job-prod ID"]
        P2["Opción B:<br>git revert en main<br>+ sync manual"]
        P3["Opción C:<br>Descarga tarball<br>de release anterior"]
        P1 & P2 & P3
    end

    style dev_rb fill:#e3f2fd
    style stg_rb fill:#fff8e1
    style prd_rb fill:#e8f5e9
```

### Comandos de rollback

```bash
# Ver historial de syncs
argocd app history ansible-job-prod --grpc-web

# Rollback a revisión ID anterior
argocd app rollback ansible-job-prod <ID> --grpc-web

# Esperar health
argocd app wait ansible-job-prod --health --timeout 300 --grpc-web
```

> En dev, con `selfHeal=true`, el rollback vía ArgoCD es temporal: en el siguiente polling, ArgoCD restaura el estado de `develop`. Para un rollback permanente en dev, usa `git revert` o fija el tag de imagen en `values-dev.yaml`.

---

## 9. Referencia rápida de comandos

### Bootstrap (una sola vez)

```bash
# Instalar ArgoCD App-of-Apps
kubectl apply -f argocd/app-of-apps.yaml

# Instalar ArgoCD Notifications Controller
make argocd-notifications-install

# Configurar notificaciones (elige uno)
make argocd-notifications-setup      # PAT (dev/testing)
make argocd-notifications-setup-app  # GitHub App (staging/prod)
```

### Operación diaria

```bash
# Estado de todas las Applications
make argocd-status

# Ver diff pendiente por entorno
make argocd-diff-dev
argocd app diff ansible-job-staging --grpc-web
argocd app diff ansible-job-prod    --grpc-web

# Forzar sync
make dev-sync                                          # dev (automático igual)
argocd app sync ansible-job-staging --grpc-web         # staging
argocd app sync ansible-job-prod    --grpc-web         # prod (requiere aprobación previa)

# Ver logs del Job
make k8s-logs-dev
kubectl logs -n ansible-jobs-staging -l batch.kubernetes.io/job-name -c ansible
kubectl logs -n ansible-jobs-prod    -l batch.kubernetes.io/job-name -c ansible

# Ver logs de notificaciones
make argocd-notifications-logs
```

### Gestión de releases

```bash
# Crear un release (desde main, tag vX.Y.Z)
gh release create vX.Y.Z --title "Release vX.Y.Z" --notes "..."

# Verificar que el artifact fue generado
gh release view vX.Y.Z --json assets

# Ver URL del artifact en values-prod.yaml
grep -A3 'releaseArtifact:' helm/ansible-job/values-prod.yaml
```

---

## Referencias

| Recurso                 | Ruta                                                                               |
| ----------------------- | ---------------------------------------------------------------------------------- |
| App-of-Apps ArgoCD      | [argocd/app-of-apps.yaml](argocd/app-of-apps.yaml)                                 |
| Application dev         | [argocd/apps/dev.yaml](argocd/apps/dev.yaml)                                       |
| Application staging     | [argocd/apps/staging.yaml](argocd/apps/staging.yaml)                               |
| Application prod        | [argocd/apps/prod.yaml](argocd/apps/prod.yaml)                                     |
| ConfigMap Notifications | [k8s/argocd-notifications/configmap.yaml](k8s/argocd-notifications/configmap.yaml) |
| Guía Notifications      | [docs/argocd/github-notifications.md](docs/argocd/github-notifications.md)         |
| Guía ArgoCD dev         | [docs/argocd/README.md](docs/argocd/README.md)                                     |
| Workflow Build & Push   | [.github/workflows/build-push.yml](.github/workflows/build-push.yml)               |
| Workflow Release        | [.github/workflows/release-ansible.yml](.github/workflows/release-ansible.yml)     |
| Helm values base        | [helm/ansible-job/values.yaml](helm/ansible-job/values.yaml)                       |
