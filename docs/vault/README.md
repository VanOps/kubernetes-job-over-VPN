# HashiCorp Vault — Gestión de Secretos

Documentación sobre la configuración y uso de HashiCorp Vault como backend de secretos para los entornos de staging.

---

## 📚 Documentos Disponibles

| Documento | Descripción |
|-----------|-------------|
| [01-vault-setup-staging.md](01-vault-setup-staging.md) | **Configuración completa** de Vault para staging: KV v2 mount, políticas, tokens, y External Secrets Operator |

---

## 🎯 Quick Start

### Para configurar Vault por primera vez (staging):

```bash
# 1. Habilitar KV v2 engine
vault secrets enable -path=ansible-vpn -version=2 kv

# 2. Crear los 3 secretos necesarios
vault kv put ansible-vpn/staging/wireguard-config wg0.conf=@test/vpn/wg0.conf
vault kv put ansible-vpn/staging/vault-password vault-password="$(cat test/secrets/vault-password)"
vault kv put ansible-vpn/staging/ssh-key ssh-private-key=@test/secrets/ssh-private-key

# 3. Crear política de lectura
vault policy write eso-staging-policy - <<EOF
path "ansible-vpn/data/staging/*" {
  capabilities = ["read"]
}
path "ansible-vpn/metadata/staging/*" {
  capabilities = ["read", "list"]
}
EOF

# 4. Generar token
vault token create -policy=eso-staging-policy -period=720h

# 5. Configurar en Kubernetes
kubectl create secret generic vault-token \
  --from-literal=token=<VAULT_TOKEN> \
  -n external-secrets

# 6. Aplicar recursos ESO
make k8s-apply-external-secrets-staging
```

---

## 🗂️ Estructura de Secretos en Vault

```
ansible-vpn/          (KV v2 mount point)
└── staging/
    ├── wireguard-config   → { "wg0.conf": "<contenido completo>" }
    ├── vault-password     → { "vault-password": "<contraseña>" }
    └── ssh-key            → { "ssh-private-key": "<clave PEM>" }
```

---

## 🔐 Secretos Requeridos por Entorno

### Dev
- **Backend:** Kubernetes Secrets (manuales)
- **Método:** `kubectl create secret`
- **Comando:** `make k8s-secrets-dev`

### Staging
- **Backend:** HashiCorp Vault KV v2
- **Método:** Vault CLI + External Secrets Operator
- **Documentación:** [01-vault-setup-staging.md](01-vault-setup-staging.md)

### Prod
- **Backend:** AWS Secrets Manager
- **Método:** AWS Console/CLI + External Secrets Operator
- **Documentación:** Ver [k8s/external-secrets/secret-store-aws.yaml](../../k8s/external-secrets/secret-store-aws.yaml)

---

## ⚙️ Comandos Make

```bash
# Crear vault-token Secret en K8s
make k8s-secrets-vault-token VAULT_TOKEN=hvs.XXXX

# Aplicar ClusterSecretStore + ExternalSecrets staging
make k8s-apply-external-secrets-staging

# Aplicar todos los recursos ESO (staging + prod)
make k8s-apply-external-secrets
```

---

## 🔍 Verificación Rápida

```bash
# 1. Verificar secretos en Vault
vault kv list ansible-vpn/staging

# 2. Verificar ClusterSecretStore
kubectl get clustersecretstore hashicorp-vault

# 3. Verificar ExternalSecrets
kubectl get externalsecrets -n ansible-jobs-staging

# 4. Verificar Secrets sincronizados
kubectl get secrets -n ansible-jobs-staging
```

---

## 🚨 Troubleshooting Común

### ExternalSecret no sincroniza

```bash
# Ver estado detallado
kubectl describe externalsecret <NAME> -n ansible-jobs-staging

# Ver logs de ESO
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Token de Vault expirado

```bash
# Verificar TTL
vault token lookup $VAULT_TOKEN

# Crear nuevo token
vault token create -policy=eso-staging-policy -period=720h

# Actualizar Secret
kubectl create secret generic vault-token \
  --from-literal=token=<NEW_TOKEN> \
  -n external-secrets --dry-run=client -o yaml | kubectl apply -f -
```

---

## 📖 Referencias

- [External Secrets Operator](https://external-secrets.io)
- [HashiCorp Vault Docs](https://developer.hashicorp.com/vault)
- [Secret Store Config](../../k8s/external-secrets/secret-store-vault.yaml)
- [Staging ExternalSecrets](../../k8s/external-secrets/staging-external-secret.yaml)
