# Vault Quick Reference — Comandos Esenciales

Referencia rápida de comandos para gestionar secretos de staging en HashiCorp Vault.

---

## 🚀 Setup Inicial (Una sola vez)

```bash
# 1. Habilitar KV v2
vault secrets enable -path=ansible-vpn -version=2 kv

# 2. Crear política
cat > eso-staging-policy.hcl <<'EOF'
path "ansible-vpn/data/staging/*" {
  capabilities = ["read"]
}
path "ansible-vpn/metadata/staging/*" {
  capabilities = ["read", "list"]
}
EOF

vault policy write eso-staging-policy eso-staging-policy.hcl

# 3. Generar token
VAULT_TOKEN=$(vault token create \
  -policy=eso-staging-policy \
  -period=720h \
  -field=token)

echo "Token: $VAULT_TOKEN"
```

---

## 📝 Crear/Actualizar Secretos

```bash
# WireGuard config
vault kv put ansible-vpn/staging/wireguard-config \
  wg0.conf=@test/vpn/wg0.conf

# Vault password
vault kv put ansible-vpn/staging/vault-password \
  vault-password="$(cat test/secrets/vault-password)"

# SSH key
vault kv put ansible-vpn/staging/ssh-key \
  ssh-private-key=@test/secrets/ssh-private-key
```

---

## 🔍 Consultar Secretos

```bash
# Listar paths
vault kv list ansible-vpn/staging

# Ver metadatos (sin revelar contenido)
vault kv metadata get ansible-vpn/staging/wireguard-config

# Ver contenido completo
vault kv get ansible-vpn/staging/wireguard-config

# Ver solo un campo específico
vault kv get -field=wg0.conf ansible-vpn/staging/wireguard-config

# Ver una versión específica
vault kv get -version=2 ansible-vpn/staging/wireguard-config
```

---

## 🔄 Actualización y Versionado

```bash
# Actualizar (crea nueva versión automáticamente)
vault kv put ansible-vpn/staging/wireguard-config \
  wg0.conf=@wg0-new.conf

# Ver historial de versiones
vault kv metadata get ansible-vpn/staging/wireguard-config

# Rollback (promover versión antigua como nueva versión)
vault kv get -version=1 -field=wg0.conf \
  ansible-vpn/staging/wireguard-config | \
vault kv put ansible-vpn/staging/wireguard-config wg0.conf=-
```

---

## 🔐 Gestión de Tokens

```bash
# Ver info del token actual
vault token lookup

# Renovar token
vault token renew

# Crear nuevo token
vault token create \
  -policy=eso-staging-policy \
  -period=720h \
  -display-name="eso-staging-$(date +%Y%m%d)"

# Revocar token
vault token revoke <TOKEN>
```

---

## ☸️ Kubernetes Integration

```bash
# Crear Secret con token de Vault
kubectl create secret generic vault-token \
  --from-literal=token=$VAULT_TOKEN \
  -n external-secrets

# Aplicar ClusterSecretStore
kubectl apply -f k8s/external-secrets/secret-store-vault.yaml

# Aplicar ExternalSecrets de staging
kubectl apply -f k8s/external-secrets/staging-external-secret.yaml

# Verificar estado
kubectl get clustersecretstore hashicorp-vault
kubectl get externalsecrets -n ansible-jobs-staging
kubectl get secrets -n ansible-jobs-staging
```

---

## 🧹 Limpieza

```bash
# Soft delete (recuperable)
vault kv delete ansible-vpn/staging/wireguard-config

# Recuperar después de soft delete
vault kv undelete -versions=3 ansible-vpn/staging/wireguard-config

# Delete permanente (destruye todas las versiones)
vault kv metadata delete ansible-vpn/staging/wireguard-config
```

---

## 🐛 Debug

```bash
# Test conectividad
vault status

# Ver políticas del token actual
vault token lookup -format=json | jq .data.policies

# Verificar permisos
vault policy read eso-staging-policy

# Test lectura de secreto
vault kv get ansible-vpn/staging/wireguard-config

# Ver logs de ESO en K8s
kubectl logs -n external-secrets \
  -l app.kubernetes.io/name=external-secrets --tail=50 -f

# Describir ExternalSecret con problemas
kubectl describe externalsecret <NAME> -n ansible-jobs-staging
```

---

## 📊 Variables de Entorno

```bash
# Conectar a Vault
export VAULT_ADDR=https://vault.example.com:8200
export VAULT_TOKEN=hvs.CAES...xxxxx

# O usar archivo de config
export VAULT_ADDR=https://vault.example.com:8200
vault login -method=token
```

---

## 🔗 Links Rápidos

- [Setup completo](01-vault-setup-staging.md)
- [Vault Docs](https://developer.hashicorp.com/vault)
- [External Secrets Operator](https://external-secrets.io)
