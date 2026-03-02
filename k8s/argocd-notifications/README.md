# ArgoCD Notifications - GitHub Commit Status

Esta carpeta contiene la configuración para ArgoCD Notifications que actualiza automáticamente el estado de los commits en GitHub.

## Archivos

| Archivo                    | Descripción                                      |
| -------------------------- | ------------------------------------------------ |
| `configmap.yaml`           | Configuración de templates, triggers y servicios |
| `github-token-secret.yaml` | Secret para Personal Access Token (Método 1)     |
| `github-app-secret.yaml`   | Secret para GitHub App (Método 2, recomendado)   |

## Configuración Rápida

**⚠️ Importante**: Si ya ejecutaste `make argocd-notifications-install`, ya tienes el controller instalado. Puedes saltar directamente a la configuración.

### Opción 1: Personal Access Token (Simple)

```bash
# 1. Verificar que el controller existe (si no, instalarlo)
kubectl get pods -n argocd | grep notifications || make argocd-notifications-install

# 2. Configurar con token
make argocd-notifications-setup

# 3. Verificar
make argocd-notifications-test
```

### Opción 2: GitHub App (Recomendado para Producción)

```bash
# 1. Verificar que el controller existe (si no, instalarlo)
kubectl get pods -n argocd | grep notifications || make argocd-notifications-install

# 2. Crear GitHub App en: https://github.com/settings/apps/new

# 3. Configurar con App credentials
make argocd-notifications-setup-app

# 4. Verificar logs
make argocd-notifications-logs
```

## Troubleshooting Común

### Error de Helm: "invalid ownership metadata"

```
Error: UPGRADE FAILED: Unable to continue with update: ServiceAccount "argocd-notifications-controller" 
in namespace "argocd" exists and cannot be imported into the current release
```

**Causa**: Ya instalaste ArgoCD Notifications con `kubectl apply` y ahora Helm no puede gestionarlo.

**Solución**: Ya tienes el controller instalado correctamente. Simplemente continúa con la configuración:

```bash
# Verificar que está funcionando
kubectl get pods -n argocd | grep notifications

# Continuar con la configuración
make argocd-notifications-setup  # Para PAT
# o
make argocd-notifications-setup-app  # Para GitHub App
```

## Documentación Completa

Ver: [docs/argocd/github-notifications.md](../../docs/argocd/github-notifications.md)

## Resultado

Cuando hagas push a las ramas `develop`, `staging` o `main`, GitHub mostrará:

- ⏳ **pending** - Mientras ArgoCD está sincronizando
- ✅ **success** - Cuando el despliegue es exitoso
- ❌ **failure** - Si el despliegue falla

Los estados aparecen directamente en el commit y en los pull requests.
