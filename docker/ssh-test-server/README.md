# SSH Test Server

Servidor SSH basado en Debian Bookworm para testing de conexiones Ansible.

## Características de Seguridad

- ✅ Usuario no-root (`ansible`)
- ✅ Autenticación solo por clave pública
- ✅ Password authentication deshabilitado
- ✅ Root login deshabilitado
- ✅ Python3 preinstalado para módulos Ansible
- ✅ Sudo sin password para usuario `ansible`

## Uso Rápido

### 1. Build de la imagen

```bash
docker build -t ssh-test-server -f docker/ssh-test-server/Dockerfile .
```

### 2. Ejecutar con clave pública montada

```bash
# Crear red de prueba
docker network create ssh-net

# Ejecutar servidor (monta clave pública existente)
docker run -d \
  --name ssh-server \
  --network ssh-net \
  -v "$(pwd)/test/secrets/ssh-private-key.pub:/tmp/authorized_keys:ro" \
  ssh-test-server

# Ver logs
docker logs ssh-server
```

### 3. Probar conexión desde cliente

```bash
# Opción A: Cliente interactivo
docker run -it --rm \
  --network ssh-net \
  -v "$(pwd)/test/secrets/ssh-private-key:/root/.ssh/id_rsa:ro" \
  debian:bookworm-slim bash -c \
  "apt-get update && apt-get install -y openssh-client && \
   chmod 600 /root/.ssh/id_rsa && \
   ssh-keyscan ssh-server >> /root/.ssh/known_hosts && \
   ssh -o StrictHostKeyChecking=accept-new ansible@ssh-server whoami"

# Opción B: Usar imagen ansible existente del proyecto
docker run -it --rm \
  --network ssh-net \
  -v "$(pwd)/test/secrets/ssh-private-key:/root/.ssh/id_rsa:ro" \
  -v "$(pwd)/ansible:/ansible:ro" \
  $(docker build -q ./docker/ansible) \
  ansible all -i ssh-server, -u ansible --private-key=/root/.ssh/id_rsa -m ping
```

## Variables de Entorno

| Variable         | Descripción                              | Ejemplo             |
| ---------------- | ---------------------------------------- | ------------------- |
| `SSH_PUBLIC_KEY` | Clave pública SSH (alternativa al mount) | `ssh-rsa AAAAB3...` |

## Alternativa: Usar con variable de entorno

```bash
docker run -d \
  --name ssh-server \
  --network ssh-net \
  -e "SSH_PUBLIC_KEY=$(cat ./test/secrets/ssh-private-key.pub)" \
  ssh-test-server
```

## Cleanup

```bash
docker rm -f ssh-server
docker network rm ssh-net
```

## Integración con Docker Compose

Ver `docker-compose.ssh-lab.yml` en la raíz del proyecto.
