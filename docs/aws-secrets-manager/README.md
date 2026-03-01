# AWS Secrets Manager — Guía Completa de Configuración

Documentación unificada para configurar y gestionar AWS Secrets Manager como backend de secretos para producción, con integración de External Secrets Operator (ESO) y autenticación IRSA en EKS.

---

## 📋 Tabla de Contenidos

- [Arquitectura](#-arquitectura)
- [Quick Start](#-quick-start)
- [Prerequisitos](#-prerequisitos)
- [Configuración de AWS](#-configuración-de-aws)
- [Configuración de IRSA](#-configuración-de-irsa)
- [Integración con Kubernetes](#-integración-con-kubernetes)
- [Comandos AWS CLI](#-comandos-aws-cli)
- [Actualización y Rotación](#-actualización-y-rotación)
- [Troubleshooting](#-troubleshooting)
- [Referencias](#-referencias)

---

## 🏗️ Arquitectura

```mermaid
flowchart LR
    A[AWS Secrets Manager<br/>ansible-vpn/prod/*] -->|IRSA/OIDC Auth| B[External Secrets Operator<br/>ClusterSecretStore]
    B -->|Sync cada 30min| C[ExternalSecret<br/>prod namespace]
    C -->|Crea/actualiza| D[Kubernetes Secrets<br/>ansible-jobs-prod]
    D -->|Montados en| E[Job Pod<br/>vpn + ansible containers]

    F[EKS Cluster OIDC] -->|AssumeRoleWithWebIdentity| G[IAM Role<br/>ExternalSecretsRole]
    G -->|secretsmanager:GetSecretValue| A

    style A fill:#ffd54f
    style B fill:#81c784
    style C fill:#64b5f6
    style D fill:#ba68c8
    style E fill:#ff8a65
    style F fill:#ffab91
    style G fill:#ce93d8
```

### Separación por Entorno

| Entorno     | Backend de Secrets      | Namespace K8s          | Método de gestión     |
| ----------- | ----------------------- | ---------------------- | --------------------- |
| **Dev**     | Kubernetes Secrets      | `ansible-jobs-dev`     | `kubectl create`      |
| **Staging** | HashiCorp Vault KV v2   | `ansible-jobs-staging` | Vault CLI + ESO       |
| **Prod**    | **AWS Secrets Manager** | `ansible-jobs-prod`    | AWS CLI/Console + ESO |

### Estructura de Secretos

```
aws secretsmanager (región: eu-west-1)
└── ansible-vpn/prod/
    ├── wireguard-config    → { "wg0.conf": "<WireGuard config completo>" }
    ├── vault-password      → { "vault-password": "<contraseña ansible-vault>" }
    └── ssh-key             → { "ssh-private-key": "<clave SSH privada PEM>" }
```

### ¿Por qué AWS Secrets Manager para Producción?

- ✅ **Integración nativa con EKS** vía IRSA (sin credenciales estáticas)
- ✅ **Rotación automática** de secretos
- ✅ **Auditoría completa** con CloudTrail
- ✅ **Cifrado en reposo** con AWS KMS
- ✅ **Alta disponibilidad** multi-AZ
- ✅ **Facturación por uso** (no requiere infraestructura)

---

## 🚀 Quick Start

```bash
# 1. Crear los 3 secretos en AWS
aws secretsmanager create-secret \
  --name ansible-vpn/prod/wireguard-config \
  --secret-string "$(jq -n --arg wg "$(cat test/vpn/wg0.conf)" '{wg0.conf: $wg}')" \
  --region eu-west-1

aws secretsmanager create-secret \
  --name ansible-vpn/prod/vault-password \
  --secret-string "$(jq -n --arg pwd "$(cat test/secrets/vault-password)" '{vault-password: $pwd}')" \
  --region eu-west-1

aws secretsmanager create-secret \
  --name ansible-vpn/prod/ssh-key \
  --secret-string "$(jq -n --arg key "$(cat test/secrets/ssh-private-key)" '{ssh-private-key: $key}')" \
  --region eu-west-1

# 2. Crear IAM Policy para lectura de secretos
aws iam create-policy \
  --policy-name ExternalSecretsPolicy \
  --policy-document file://iam-policy.json

# 3. Configurar IRSA (asociar IAM Role con ServiceAccount)
eksctl create iamserviceaccount \
  --name external-secrets \
  --namespace external-secrets \
  --cluster mi-cluster-eks \
  --role-name ExternalSecretsRole \
  --attach-policy-arn arn:aws:iam::ACCOUNT_ID:policy/ExternalSecretsPolicy \
  --approve

# 4. Aplicar recursos ESO en Kubernetes
kubectl apply -f k8s/external-secrets/secret-store-aws.yaml
kubectl apply -f k8s/external-secrets/prod-external-secret.yaml

# 5. Verificar sincronización
kubectl get externalsecrets -n ansible-jobs-prod
kubectl get secrets -n ansible-jobs-prod
```

---

## 📦 Prerequisitos

### 1. Cluster EKS con OIDC habilitado

```bash
# Verificar si OIDC está habilitado
aws eks describe-cluster \
  --name mi-cluster-eks \
  --query "cluster.identity.oidc.issuer" \
  --output text

# Habilitar OIDC si no existe
eksctl utils associate-iam-oidc-provider \
  --cluster mi-cluster-eks \
  --approve
```

### 2. External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true

kubectl get pods -n external-secrets
```

### 3. AWS CLI configurado

```bash
# Verificar configuración
aws sts get-caller-identity
aws secretsmanager list-secrets --region eu-west-1

# Configurar si es necesario
aws configure
```

---

## ⚙️ Configuración de AWS

### Paso 1: Crear IAM Policy

Crear archivo `iam-policy.json` (ver [iam-policy-example.json](iam-policy-example.json)):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:eu-west-1:ACCOUNT_ID:secret:ansible-vpn/prod/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:ListSecrets"],
      "Resource": "*"
    }
  ]
}
```

```bash
# Crear la política
aws iam create-policy \
  --policy-name ExternalSecretsPolicy \
  --policy-document file://iam-policy.json

# Output: arn:aws:iam::ACCOUNT_ID:policy/ExternalSecretsPolicy
```

### Paso 2: Crear Secretos en AWS

#### WireGuard Config

```bash
# Opción A: Desde archivo
aws secretsmanager create-secret \
  --name ansible-vpn/prod/wireguard-config \
  --description "WireGuard VPN configuration for Ansible Jobs" \
  --secret-string "$(jq -n --arg wg "$(cat test/vpn/wg0.conf)" '{
    "wg0.conf": $wg
  }')" \
  --region eu-west-1

# Opción B: Inline
aws secretsmanager create-secret \
  --name ansible-vpn/prod/wireguard-config \
  --secret-string '{
    "wg0.conf": "[Interface]\nPrivateKey = CLIENT_PRIVATE_KEY\nAddress = 10.10.99.2/24\nDNS = 10.10.99.1\n\n[Peer]\nPublicKey = SERVER_PUBLIC_KEY\nEndpoint = vpn.example.com:51820\nAllowedIPs = 10.10.99.0/24, 10.10.20.0/24\nPersistentKeepalive = 25"
  }' \
  --region eu-west-1
```

#### Ansible Vault Password

```bash
aws secretsmanager create-secret \
  --name ansible-vpn/prod/vault-password \
  --description "Ansible Vault password for encrypted vars" \
  --secret-string "$(jq -n --arg pwd "$(cat test/secrets/vault-password)" '{
    "vault-password": $pwd
  }')" \
  --region eu-west-1
```

#### SSH Private Key

```bash
aws secretsmanager create-secret \
  --name ansible-vpn/prod/ssh-key \
  --description "SSH private key for Ansible to connect to remote hosts" \
  --secret-string "$(jq -n --arg key "$(cat test/secrets/ssh-private-key)" '{
    "ssh-private-key": $key
  }')" \
  --region eu-west-1
```

### Paso 3: Verificar Secretos

```bash
# Listar todos los secretos
aws secretsmanager list-secrets \
  --filters Key=name,Values=ansible-vpn/prod \
  --region eu-west-1

# Ver valor de un secreto (cuidado: imprime el secreto)
aws secretsmanager get-secret-value \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1 \
  --query SecretString \
  --output text | jq .

# Ver solo metadatos (sin revelar el secreto)
aws secretsmanager describe-secret \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1
```

---

## 🔐 Configuración de IRSA

IRSA (IAM Roles for Service Accounts) permite que los pods de Kubernetes asuman roles de IAM sin credenciales estáticas.

### Opción A: Con eksctl (recomendado)

```bash
# Crear ServiceAccount con IAM Role automáticamente
eksctl create iamserviceaccount \
  --name external-secrets \
  --namespace external-secrets \
  --cluster mi-cluster-eks \
  --role-name ExternalSecretsRole \
  --attach-policy-arn arn:aws:iam::ACCOUNT_ID:policy/ExternalSecretsPolicy \
  --approve \
  --region eu-west-1

# Verificar
kubectl describe sa external-secrets -n external-secrets
# Debe tener anotación: eks.amazonaws.com/role-arn
```

### Opción B: Manual

#### 1. Crear Trust Policy

Crear `trust-policy.json` (ver [trust-policy-example.json](trust-policy-example.json)):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.eu-west-1.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }
  ]
}
```

#### 2. Crear IAM Role

```bash
# Crear role
aws iam create-role \
  --role-name ExternalSecretsRole \
  --assume-role-policy-document file://trust-policy.json

# Adjuntar política
aws iam attach-role-policy \
  --role-name ExternalSecretsRole \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/ExternalSecretsPolicy
```

#### 3. Anotar ServiceAccount

```bash
kubectl annotate serviceaccount external-secrets \
  -n external-secrets \
  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT_ID:role/ExternalSecretsRole
```

---

## ☸️ Integración con Kubernetes

### Paso 1: Aplicar ClusterSecretStore

Editar `k8s/external-secrets/secret-store-aws.yaml` si es necesario:

```yaml
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-west-1 # ← Tu región
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

```bash
kubectl apply -f k8s/external-secrets/secret-store-aws.yaml

# Verificar estado
kubectl get clustersecretstore aws-secrets-manager -o yaml
# Status.Conditions.Type: Ready = True
```

### Paso 2: Aplicar ExternalSecrets

```bash
# Crear namespace
kubectl create namespace ansible-jobs-prod

# Aplicar ExternalSecrets
kubectl apply -f k8s/external-secrets/prod-external-secret.yaml

# Verificar sincronización
kubectl get externalsecrets -n ansible-jobs-prod
# NAME                    STATUS          READY
# vpn-wireguard-config    SecretSynced    True
# ansible-vault-password  SecretSynced    True
# ansible-ssh-key         SecretSynced    True
```

### Paso 3: Verificar Secrets Creados

```bash
# Listar secrets
kubectl get secrets -n ansible-jobs-prod

# Ver contenido (decodificar base64)
kubectl get secret vpn-wireguard-config \
  -n ansible-jobs-prod \
  -o jsonpath='{.data.wg0\.conf}' | base64 -d

# Verificar metadatos del ExternalSecret
kubectl describe externalsecret vpn-wireguard-config \
  -n ansible-jobs-prod
```

---

## 🛠️ Comandos AWS CLI

### Operaciones Básicas

```bash
# Listar secretos con filtro
aws secretsmanager list-secrets \
  --filters Key=name,Values=ansible-vpn/prod \
  --region eu-west-1

# Ver valor completo
aws secretsmanager get-secret-value \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1 \
  --query SecretString \
  --output text | jq .

# Ver solo un campo
aws secretsmanager get-secret-value \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1 \
  --query SecretString \
  --output text | jq -r '.["wg0.conf"]'

# Ver metadatos sin revelar el secreto
aws secretsmanager describe-secret \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1
```

### Comandos Make

```bash
# Aplicar ClusterSecretStore + ExternalSecrets de prod
make k8s-apply-external-secrets-prod

# Aplicar todos los recursos ESO (staging + prod)
make k8s-apply-external-secrets
```

---

## 🔄 Actualización y Rotación

### Actualizar Secreto Manualmente

```bash
# Opción A: Actualizar valor completo
aws secretsmanager update-secret \
  --secret-id ansible-vpn/prod/wireguard-config \
  --secret-string "$(jq -n --arg wg "$(cat wg0-new.conf)" '{
    "wg0.conf": $wg
  }')" \
  --region eu-west-1

# Opción B: Actualizar desde string JSON
aws secretsmanager put-secret-value \
  --secret-id ansible-vpn/prod/vault-password \
  --secret-string '{"vault-password": "nueva-contraseña"}' \
  --region eu-west-1

# ESO sincronizará automáticamente en el próximo refresh (30min)
# O forzar inmediatamente:
kubectl annotate externalsecret vpn-wireguard-config \
  -n ansible-jobs-prod \
  force-sync="$(date +%s)" --overwrite
```

### Rotación Automática con Lambda

AWS Secrets Manager soporta rotación automática. Ejemplo de configuración:

```bash
# Habilitar rotación (requiere Lambda)
aws secretsmanager rotate-secret \
  --secret-id ansible-vpn/prod/ssh-key \
  --rotation-lambda-arn arn:aws:lambda:eu-west-1:ACCOUNT_ID:function:SecretsManagerRotation \
  --rotation-rules AutomaticallyAfterDays=90 \
  --region eu-west-1
```

### Ver Versiones de Secreto

```bash
# Listar versiones
aws secretsmanager list-secret-version-ids \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1

# Obtener versión específica
aws secretsmanager get-secret-value \
  --secret-id ansible-vpn/prod/wireguard-config \
  --version-id <VERSION_ID> \
  --region eu-west-1
```

### Eliminar Secreto

```bash
# Soft delete (recuperable durante 30 días)
aws secretsmanager delete-secret \
  --secret-id ansible-vpn/prod/wireguard-config \
  --recovery-window-in-days 30 \
  --region eu-west-1

# Recuperar secreto eliminado
aws secretsmanager restore-secret \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1

# Delete permanente (sin recovery window)
aws secretsmanager delete-secret \
  --secret-id ansible-vpn/prod/wireguard-config \
  --force-delete-without-recovery \
  --region eu-west-1
```

---

## 🐛 Troubleshooting

### ExternalSecret en "SecretSyncedError"

```bash
kubectl describe externalsecret vpn-wireguard-config -n ansible-jobs-prod
```

| Error                       | Causa                   | Solución                                                                                |
| --------------------------- | ----------------------- | --------------------------------------------------------------------------------------- |
| `AccessDeniedException`     | Role sin permisos       | Verificar IAM Policy y IRSA: `aws iam get-role-policy --role-name ExternalSecretsRole`  |
| `ResourceNotFoundException` | Secreto no existe       | Verificar: `aws secretsmanager list-secrets --filters Key=name,Values=ansible-vpn/prod` |
| `InvalidRequestException`   | Property key incorrecta | Verificar que el campo en AWS coincida con `remoteRef.property`                         |
| `could not assume role`     | IRSA mal configurado    | Verificar anotación en ServiceAccount y trust policy                                    |

### ClusterSecretStore "Invalid"

```bash
kubectl describe clustersecretstore aws-secrets-manager

# Ver logs de ESO
kubectl logs -n external-secrets \
  -l app.kubernetes.io/name=external-secrets --tail=100
```

**Debug paso a paso:**

```bash
# 1. Verificar OIDC del cluster
aws eks describe-cluster \
  --name mi-cluster-eks \
  --query "cluster.identity.oidc.issuer"

# 2. Verificar ServiceAccount tiene anotación
kubectl get sa external-secrets -n external-secrets -o yaml | grep role-arn

# 3. Verificar IAM Role existe
aws iam get-role --role-name ExternalSecretsRole

# 4. Verificar políticas adjuntas
aws iam list-attached-role-policies --role-name ExternalSecretsRole

# 5. Test desde pod
kubectl run aws-test --rm -it --restart=Never \
  --namespace=external-secrets \
  --serviceaccount=external-secrets \
  --image=amazon/aws-cli -- \
  sts get-caller-identity

kubectl run aws-test --rm -it --restart=Never \
  --namespace=external-secrets \
  --serviceaccount=external-secrets \
  --image=amazon/aws-cli -- \
  secretsmanager list-secrets --region eu-west-1
```

### Secret sincronizado pero con datos incorrectos

```bash
# Comparar datos en AWS vs Kubernetes
aws secretsmanager get-secret-value \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1 \
  --query SecretString --output text | jq -r '.["wg0.conf"]' > /tmp/aws.txt

kubectl get secret vpn-wireguard-config \
  -n ansible-jobs-prod \
  -o jsonpath='{.data.wg0\.conf}' | base64 -d > /tmp/k8s.txt

diff /tmp/aws.txt /tmp/k8s.txt
```

### Validar Permisos IRSA

```bash
# Verificar que el pod puede asumir el role
kubectl run aws-sts-test --rm -it --restart=Never \
  --namespace=external-secrets \
  --serviceaccount=external-secrets \
  --image=amazon/aws-cli -- \
  sts get-caller-identity
# Debe mostrar: "Arn": "arn:aws:sts::ACCOUNT_ID:assumed-role/ExternalSecretsRole/..."

# Verificar acceso a Secrets Manager
kubectl run aws-sm-test --rm -it --restart=Never \
  --namespace=external-secrets \
  --serviceaccount=external-secrets \
  --image=amazon/aws-cli -- \
  secretsmanager get-secret-value \
  --secret-id ansible-vpn/prod/wireguard-config \
  --region eu-west-1
```

---

## 💰 Costos

AWS Secrets Manager tiene los siguientes costos (precios aprox. región eu-west-1):

- **Almacenamiento:** $0.40 por secreto/mes
- **API calls:** $0.05 por 10,000 llamadas
- **Rotación automática:** Sin costo adicional

**Ejemplo para 3 secretos con refresh de 30min:**

- Almacenamiento: 3 secretos × $0.40 = **$1.20/mes**
- API calls: ~4,300 calls/mes × $0.05/10,000 = **$0.02/mes**
- **Total: ~$1.22/mes**

---

## 📚 Referencias

### Archivos del Proyecto

- [ClusterSecretStore Config](../../k8s/external-secrets/secret-store-aws.yaml)
- [Prod ExternalSecrets](../../k8s/external-secrets/prod-external-secret.yaml)
- [IAM Policy Example](iam-policy-example.json)
- [Trust Policy Example](trust-policy-example.json)

### Documentación Externa

- [External Secrets Operator - AWS Provider](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [AWS Secrets Manager Docs](https://docs.aws.amazon.com/secretsmanager/)
- [EKS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [AWS CLI Secrets Manager Reference](https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/)
