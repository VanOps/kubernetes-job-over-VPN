# GitHub Notifications con GitHub App

## Objetivo

Configurar ArgoCD Notifications con GitHub App para actualizar automáticamente el estado de los commits en GitHub cuando un despliegue se completa.

**💡 Ideal para**: Entornos de staging y producción

**⚡ Ventajas**:

- Sin expiración
- Permisos granulares
- Independiente de usuarios
- Mejor auditabilidad

**⚠️ Complejidad**: Configuración más compleja (15-20 minutos)

**📚 Para testing rápido**: Considera usar [Personal Access Token](github-notifications-pat.md)

---

## Arquitectura

```mermaid
sequenceDiagram
    participant Git as GitHub
    participant ArgoCD as ArgoCD Controller
    participant Notif as Notifications Controller
    participant App as GitHub App
    participant API as GitHub API

    Git->>ArgoCD: Push to staging/main
    ArgoCD->>ArgoCD: Detecta cambio
    ArgoCD->>ArgoCD: Inicia Sync
    ArgoCD->>Notif: Evento: on-sync-running
    Notif->>App: Autentica con Private Key
    App->>API: Genera Installation Token
    API->>App: Token temporal
    Notif->>API: POST /repos/.../statuses/{sha}<br/>(con Installation Token)
    API->>Git: State: pending ⏳

    alt Sync Exitoso
        ArgoCD->>Notif: Evento: on-deployed
        Notif->>API: POST /repos/.../statuses/{sha}
        API->>Git: State: success ✅
    else Sync Fallido
        ArgoCD->>Notif: Evento: on-sync-failed
        Notif->>API: POST /repos/.../statuses/{sha}
        API->>Git: State: failure ❌
    end
```

**Diferencia clave**: GitHub App genera tokens de instalación temporales usando la private key, en lugar de usar un token fijo.

---

## Instalación Paso a Paso

### Paso 1: Instalar ArgoCD Notifications Controller

Si no está instalado:

```bashManual (Recomendado - más simple)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/release-1.0/manifests/install.yaml

# Opción B: Con Helm (solo si ArgoCD se instaló con Helm)
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set notifications.enabled=true
```

**⚠️ Importante**: Si instalaste ArgoCD Notifications manualmente y luego intentas usar Helm, obtendrás un error de ownership. Elige un método y mantente con él.

**Si ya tienes el error de Helm**:

```bash
# Error: "invalid ownership metadata; label validation error: missing key app.kubernetes.io/managed-by"

# Solución 1: Eliminar la instalación manual y reinstalar con Helm
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/release-1.0/manifests/install.yaml
helm upgrade --install argocd argo/argo-cd --namespace argocd --set notifications.enabled=true

# Solución 2: Continuar con kubectl (recomendado)
# No hacer nada, ya está instalado correctamente
```

Verificar:

```bash
kubectl get pods -n argocd | grep notifications
# Debe aparecer: argocd-notifications-controller-xxx
```

**Usando el Makefile** (usa kubectl apply)

**Usando el Makefile**:

```bash
make argocd-notifications-install
```

---

### Paso 2: Crear GitHub App

#### 2.1 Registrar la App

1. Ve a: **https://github.com/settings/apps/new**
   - Para organizaciones: `https://github.com/organizations/TU_ORG/settings/apps/new`

2. Completa el formulario:

| Campo               | Valor                                              |
| ------------------- | -------------------------------------------------- |
| **GitHub App name** | `ArgoCD Notifications` (o el nombre que prefieras) |
| **Homepage URL**    | `https://argoproj.github.io/argo-cd/`              |
| **Webhook**         | ❌ **Desactivar** "Active"                         |
| **Webhook URL**     | Dejar vacío                                        |

#### 2.2 Configurar Permisos

En la sección **Repository permissions**, configura solo lo necesario:

| Permiso             | Nivel de Acceso  | Obligatorio |
| ------------------- | ---------------- | ----------- |
| **Commit statuses** | `Read and write` | ✅ Sí       |
| **Contents**        | `Read-only`      | ☑️ Opcional |

En **Organization permissions** (si aplica):
| Permiso | Nivel de Acceso |
|---------|----------------|
| **Metadata** | `Read-only` (se activa automáticamente) |

#### 2.3 Guardar y Obtener App ID

1. Haz clic en **Create GitHub App**
2. Serás redirigido a la página de configuración de tu app
3. En la parte superior verás:

```
App ID: 123456  ← Anota este número
```

**🔑 Valor 1 de 3: `APP_ID = 123456`**

---

### Paso 3: Generar Private Key

En la página de configuración de tu GitHub App:

1. Baja hasta la sección **Private keys**
2. Haz clic en **Generate a private key**
3. Se descargará un archivo `.pem`:
   ```
   argocd-notifications.2026-03-01.private-key.pem
   ```
4. **Guarda este archivo de forma segura** (no lo subas a git)

```bash
# Mover a ubicación segura
mkdir -p ~/.github-apps
mv ~/Downloads/argocd-notifications.*.private-key.pem ~/.github-apps/
chmod 600 ~/.github-apps/argocd-notifications.*.private-key.pem
```

**🔑 Valor 2 de 3: `PRIVATE_KEY` (archivo .pem)**

---

### Paso 4: Instalar la App en tu Repositorio

#### 4.1 Instalar

En la página de tu GitHub App:

1. Haz clic en **Install App** (menú lateral izquierdo)
2. Selecciona tu **organización** o **cuenta personal**
3. Elige los repositorios:
   - **All repositories** (todas) o
   - **Only select repositories** → Selecciona `kubernetes-job-over-VPN`
4. Haz clic en **Install**

#### 4.2 Obtener Installation ID

Después de instalar, serás redirigido a una URL como:

**Para cuentas personales:**

```
https://github.com/settings/installations/12345678
                                          ^^^^^^^^
                                      Installation ID
```

**Para organizaciones:**

```
https://github.com/organizations/VanOps/settings/installations/12345678
                                                                ^^^^^^^^
                                                            Installation ID
```

**🔑 Valor 3 de 3: `INSTALLATION_ID = 12345678`**

#### 4.3 Forma Alternativa (usando API)

Si no puedes ver el ID en la URL:

```bash
# Necesitas un Personal Access Token para esta consulta
curl -H "Authorization: token TU_GITHUB_TOKEN" \
  https://api.github.com/repos/VanOps/kubernetes-job-over-VPN/installation

# Respuesta:
{
  "id": 12345678,         ← Este es tu Installation ID
  "app_id": 123456,       ← Confirma tu App ID
  "target_type": "User",
  "account": { ... }
}
```

---

### Paso 5: Crear Secret en Kubernetes

Ahora ya tienes los 3 valores necesarios:

- ✅ `APP_ID`
- ✅ `INSTALLATION_ID`
- ✅ `PRIVATE_KEY` (archivo .pem)

#### Opción A: Comando Rápido (Recomendado)

```bash
make argocd-notifications-setup-app
```

El comando te pedirá interactivamente:

1. GitHub App ID
2. Installation ID
3. Ruta al archivo .pem

#### Opción B: Comando Manual

```bash
# 1. Leer el contenido del archivo .pem
PRIVATE_KEY=$(cat ~/.github-apps/argocd-notifications.2026-03-01.private-key.pem)

# 2. Crear el secret
kubectl create secret generic argocd-notifications-secret \
  --from-literal=github-app-id=123456 \
  --from-literal=github-app-installation-id=12345678 \
  --from-literal=github-app-private-key="$PRIVATE_KEY" \
  -n argocd

# 3. Verificar
kubectl get secret argocd-notifications-secret -n argocd
```

#### Opción C: Usando Archivo YAML

Edita `k8s/argocd-notifications/github-app-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
type: Opaque
stringData:
  github-app-id: "123456"
  github-app-installation-id: "12345678"
  github-app-private-key: |
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEAxxxx...
    (pegar el contenido completo del archivo .pem)
    ...xxxxxxxxxxxxxx
    -----END RSA PRIVATE KEY-----
```

Aplicar:

```bash
kubectl apply -f k8s/argocd-notifications/github-app-secret.yaml
```

---

### Paso 6: Actualizar ConfigMap

Edita `k8s/argocd-notifications/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  # ────────────────────────────────────────────────────────────────────
  # OPCIÓN 1: GitHub App (Recomendado para Producción)
  # ────────────────────────────────────────────────────────────────────
  service.github: |
    appID: $github-app-id
    installationID: $github-app-installation-id
    privateKey: $github-app-private-key

  # ────────────────────────────────────────────────────────────────────
  # OPCIÓN 2: Personal Access Token (comentar si usas GitHub App)
  # ────────────────────────────────────────────────────────────────────
  # service.webhook.github-status: |
  #   url: https://api.github.com
  #   headers:
  #   - name: Authorization
  #     value: token $github-token

  # ... resto de templates y triggers ...
```

**Cambios necesarios**:

1. **Descomentar** la sección `service.github` (OPCIÓN 1)
2. **Comentar** la sección `service.webhook.github-status` (OPCIÓN 2)

Aplicar:

```bash
kubectl apply -f k8s/argocd-notifications/configmap.yaml -n argocd
```

---

### Paso 7: Verificar la Configuración

#### 7.1 Ver Logs del Controller

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller -f
```

Busca líneas como:

```
time="..." level=info msg="GitHub App authenticated successfully" appID=123456 installationID=12345678
```

Si ves errores:

```
time="..." level=error msg="failed to authenticate GitHub App" error="..."
```

Revisa que los valores en el secret sean correctos.

#### 7.2 Test Manual con la GitHub App

Instala `jwt-cli` para generar tokens JWT:

```bash
# macOS
brew install mike-engel/jwt-cli/jwt-cli

# Linux
cargo install jwt-cli
```

Prueba la autenticación:

```bash
APP_ID=123456
INSTALLATION_ID=12345678
PRIVATE_KEY_PATH=~/.github-apps/argocd-notifications.2026-03-01.private-key.pem

# 1. Generar JWT (válido 10 minutos)
JWT=$(jwt encode \
  --secret @$PRIVATE_KEY_PATH \
  --alg RS256 \
  --iat now \
  --exp +10min \
  --iss $APP_ID)

echo "JWT: $JWT"

# 2. Obtener installation token (válido 1 hora)
INSTALL_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens \
  | jq -r .token)

echo "Installation Token: $INSTALL_TOKEN"

# 3. Probar actualizar commit status
COMMIT_SHA="abc123"  # Reemplaza con un commit real

curl -X POST \
  -H "Authorization: token $INSTALL_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/VanOps/kubernetes-job-over-VPN/statuses/$COMMIT_SHA \
  -d '{
    "state": "success",
    "description": "Test from GitHub App",
    "context": "argocd/test"
  }'
```

---

## Probar la Configuración

### 1. Hacer un Commit de Prueba

```bash
git commit --allow-empty -m "test: trigger argocd sync with github app"
git push origin staging
```

### 2. Verificar en GitHub

Ve a tu commit:

```
https://github.com/VanOps/kubernetes-job-over-VPN/commit/{SHA}
```

Deberías ver los estados con el nombre de tu GitHub App:

| Estado         | Descripción                       | Bot                         |
| -------------- | --------------------------------- | --------------------------- |
| ⏳ **pending** | ArgoCD sync running               | `ArgoCD Notifications[bot]` |
| ✅ **success** | Application deployed successfully | `ArgoCD Notifications[bot]` |
| ❌ **failure** | Deployment failed                 | `ArgoCD Notifications[bot]` |

---

## Troubleshooting

### Error: "could not generate installation token"

```bash
# Ver logs detallados
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller --tail=100
```

**Causas comunes**:

- **App ID incorrecto**: Verifica en https://github.com/settings/apps
- **Installation ID incorrecto**: Verifica la URL de instalación
- **Private key corrupta**: Asegúrate de incluir las líneas BEGIN/END completas

**Solución**:

```bash
# Verificar el secret
kubectl get secret argocd-notifications-secret -n argocd -o yaml

# Recrear el secret
kubectl delete secret argocd-notifications-secret -n argocd
make argocd-notifications-setup-app
```

---

### Error: "GitHub App not installed on repository"

La app no está instalada en el repositorio correcto.

**Verificar instalación**:

1. Ve a: https://github.com/settings/installations
2. Haz clic en tu app
3. Verifica que `kubernetes-job-over-VPN` esté en la lista

**Solución**: Instalar la app en el repositorio (Paso 4)

---

### Error: "Resource not accessible by integration"

La GitHub App no tiene los permisos necesarios.

**Verificar permisos**:

1. Ve a: https://github.com/settings/apps/tu-app
2. Sección **Repository permissions**
3. Verifica: `Commit statuses` = `Read and write`

**Solución**:

1. Actualizar permisos en la configuración de la app
2. Reinstalar la app en el repositorio

---

### Las notificaciones no aparecen

**Checklist**:

```bash
# 1. Verificar que el secret existe y tiene los 3 valores
kubectl get secret argocd-notifications-secret -n argocd -o jsonpath='{.data}' | jq

# 2. Verificar que el ConfigMap usa service.github (no webhook)
kubectl get cm argocd-notifications-cm -n argocd -o jsonpath='{.data.service\.github}'

# 3. Verificar logs del controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller --tail=50

# 4. Verificar annotations de la Application
kubectl get app ansible-job-staging -n argocd -o yaml | grep notifications

# 5. Forzar un sync
argocd app sync ansible-job-staging
```

---

## Gestión y Mantenimiento

### Rotar Private Key

Recomendado anualmente o si la key se compromete:

```bash
# 1. En GitHub: Generar nueva private key
#    https://github.com/settings/apps/tu-app
#    Sección "Private keys" → "Generate a private key"

# 2. Descargar el nuevo .pem

# 3. Actualizar el secret
PRIVATE_KEY=$(cat nueva-private-key.pem)

kubectl create secret generic argocd-notifications-secret \
  --from-literal=github-app-id=123456 \
  --from-literal=github-app-installation-id=12345678 \
  --from-literal=github-app-private-key="$PRIVATE_KEY" \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Reiniciar controller
kubectl rollout restart deployment argocd-notifications-controller -n argocd

# 5. Revocar la key antigua en GitHub
```

### Revocar Private Key Antigua

En la página de tu GitHub App:

1. Ve a la sección **Private keys**
2. Encuentra la key antigua
3. Haz clic en **Delete**

### Agregar Más Repositorios

1. Ve a: https://github.com/settings/installations
2. Haz clic en **Configure** junto a tu app
3. En **Repository access**:
   - Selecciona los nuevos repositorios
4. Clic en **Save**

No necesitas cambiar nada en Kubernetes (mismo Installation ID).

---

## Comparación: GitHub App vs Personal Access Token

| Característica    | GitHub App                            | Personal Access Token            |
| ----------------- | ------------------------------------- | -------------------------------- |
| **Seguridad**     | ⭐⭐⭐ Alta<br/>Permisos granulares   | ⭐⭐ Básica<br/>Permisos amplios |
| **Expiración**    | ✅ No expira                          | ⚠️ Sí (max 1 año)                |
| **Permisos**      | Solo `commit status`                  | Todo el scope `repo`             |
| **Auditoría**     | Aparece como "App[bot]"               | Aparece como usuario             |
| **Dependencia**   | Independiente de usuarios             | Vinculado a usuario              |
| **Revocación**    | Si el usuario sale, sigue funcionando | Si el usuario sale, se rompe     |
| **Rate limits**   | 5,000 req/hora por instalación        | 5,000 req/hora total             |
| **Setup**         | ⭐⭐⭐ Complejo (20 min)              | ⭐ Simple (5 min)                |
| **Mantenimiento** | ⭐ Bajo (anual)                       | ⭐⭐ Medio (renovar cada año)    |
| **Ideal para**    | ✅ Staging/Production                 | ✅ Dev/Testing                   |

---

## Beneficios de GitHub App

### ✅ Seguridad

```yaml
# GitHub App - Solo puede actualizar commit status
permissions:
  statuses: write

# vs

# Personal Access Token - Acceso completo al repo
scopes:
  - repo # Puede leer/escribir código, issues, PRs, etc.
```

### ✅ Sin Expiración

```
GitHub App Private Key:
• No expira
• Rotación opcional (anual recomendado)

vs

Personal Access Token:
• Expira en máximo 1 año
• Requiere renovación regular
```

### ✅ Independiente de Usuarios

```
Usuario sysadmin renuncia
  ↓
GitHub App sigue funcionando ✅

vs

Usuario sysadmin renuncia
  ↓
Personal Access Token deja de funcionar ❌
```

### ✅ Mejor Auditabilidad

En GitHub commits:

```
✅ argocd/deployment — Application deployed successfully
   via ArgoCD Notifications (app)  ← Clara identificación
```

vs

```
✅ argocd/deployment — Application deployed successfully
   via john@example.com  ← Parece una acción manual
```

---

## Resumen de Comandos

```bash
# Setup inicial
make argocd-notifications-install      # Instalar controller
make argocd-notifications-setup-app    # Configurar con GitHub App

# Verificación
make argocd-notifications-logs         # Ver logs

# Mantenimiento
kubectl get secret argocd-notifications-secret -n argocd -o yaml
kubectl rollout restart deployment argocd-notifications-controller -n argocd

# Debug
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller -f
```

---

## Referencias

- [Documentación general](github-notifications.md)
- [Personal Access Token (alternativa)](github-notifications-pat.md)
- [GitHub Apps Documentation](https://docs.github.com/en/developers/apps/getting-started-with-apps/about-apps)
- [ArgoCD Notifications Docs](https://argocd-notifications.readthedocs.io/)
- [GitHub Commit Status API](https://docs.github.com/en/rest/commits/statuses)
