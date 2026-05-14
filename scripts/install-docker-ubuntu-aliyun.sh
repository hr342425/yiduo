#!/usr/bin/env bash
set -euo pipefail

DOCKER_CE_MIRROR="${DOCKER_CE_MIRROR:-https://mirrors.aliyun.com/docker-ce}"
DOCKER_REGISTRY_MIRROR="${DOCKER_REGISTRY_MIRROR:-}"
REMOVE_OLD_DOCKER_PACKAGES="${REMOVE_OLD_DOCKER_PACKAGES:-0}"

log() {
  printf '[docker-install] %s\n' "$*"
}

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
  INSTALL_USER="${SUDO_USER:-}"
else
  SUDO=(sudo)
  INSTALL_USER="$USER"
fi

case "$DOCKER_REGISTRY_MIRROR" in
  *xxxxxx*|*你的专属ID*|*你的*)
    echo "DOCKER_REGISTRY_MIRROR looks like a placeholder: $DOCKER_REGISTRY_MIRROR" >&2
    echo "Use the exact accelerator URL from your ACR console, or leave DOCKER_REGISTRY_MIRROR empty." >&2
    exit 1
    ;;
esac

if [ "$REMOVE_OLD_DOCKER_PACKAGES" = "1" ]; then
  log "removing old Ubuntu docker packages if present"
  "${SUDO[@]}" apt-get remove -y \
    docker.io \
    docker-doc \
    docker-compose \
    docker-compose-v2 \
    podman-docker \
    containerd \
    runc || true
else
  log "skipping old package removal; set REMOVE_OLD_DOCKER_PACKAGES=1 on a fresh server if needed"
fi

log "installing apt prerequisites"
"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y ca-certificates curl gnupg lsb-release git ufw

log "adding Docker CE apt key from $DOCKER_CE_MIRROR"
"${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
"${SUDO[@]}" rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL "$DOCKER_CE_MIRROR/linux/ubuntu/gpg" | "${SUDO[@]}" gpg --dearmor -o /etc/apt/keyrings/docker.gpg
"${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.gpg

log "adding Docker CE apt repository"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $DOCKER_CE_MIRROR/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null

log "installing Docker Engine and Compose plugin"
"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if [ -n "$DOCKER_REGISTRY_MIRROR" ]; then
  log "configuring Docker registry mirror: $DOCKER_REGISTRY_MIRROR"
  "${SUDO[@]}" mkdir -p /etc/docker
  if [ -f /etc/docker/daemon.json ]; then
    "${SUDO[@]}" cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%Y%m%d%H%M%S)"
  fi
  "${SUDO[@]}" tee /etc/docker/daemon.json >/dev/null <<JSON
{
  "registry-mirrors": ["$DOCKER_REGISTRY_MIRROR"]
}
JSON
fi

log "enabling Docker service"
"${SUDO[@]}" systemctl enable --now docker

if [ -n "$INSTALL_USER" ] && [ "$INSTALL_USER" != "root" ]; then
  log "adding $INSTALL_USER to docker group"
  "${SUDO[@]}" usermod -aG docker "$INSTALL_USER"
else
  log "running as root; skipping docker group update"
fi

log "Docker installed"
docker --version
docker compose version

cat <<'EOF'

Verify with:

  docker info
  docker compose version

If a non-root user was added to the docker group, log out and log back in over
SSH before running docker as that user.

EOF
