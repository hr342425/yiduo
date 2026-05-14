#!/usr/bin/env bash
set -euo pipefail

DOCKER_CE_MIRROR="${DOCKER_CE_MIRROR:-https://mirrors.aliyun.com/docker-ce}"
DOCKER_REGISTRY_MIRROR="${DOCKER_REGISTRY_MIRROR:-}"
REMOVE_OLD_DOCKER_PACKAGES="${REMOVE_OLD_DOCKER_PACKAGES:-0}"

log() {
  printf '[docker-install] %s\n' "$*"
}

if [ "$(id -u)" -eq 0 ]; then
  echo "Please run this script as a normal sudo-capable user, not as root." >&2
  exit 1
fi

if [ "$REMOVE_OLD_DOCKER_PACKAGES" = "1" ]; then
  log "removing old Ubuntu docker packages if present"
  sudo apt-get remove -y \
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
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release git ufw

log "adding Docker CE apt key from $DOCKER_CE_MIRROR"
sudo install -m 0755 -d /etc/apt/keyrings
sudo rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL "$DOCKER_CE_MIRROR/linux/ubuntu/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

log "adding Docker CE apt repository"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $DOCKER_CE_MIRROR/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

log "installing Docker Engine and Compose plugin"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if [ -n "$DOCKER_REGISTRY_MIRROR" ]; then
  log "configuring Docker registry mirror: $DOCKER_REGISTRY_MIRROR"
  sudo mkdir -p /etc/docker
  if [ -f /etc/docker/daemon.json ]; then
    sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%Y%m%d%H%M%S)"
  fi
  sudo tee /etc/docker/daemon.json >/dev/null <<JSON
{
  "registry-mirrors": ["$DOCKER_REGISTRY_MIRROR"]
}
JSON
fi

log "enabling Docker service"
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

log "Docker installed"
docker --version || sudo docker --version
docker compose version || sudo docker compose version

cat <<'EOF'

If you were just added to the docker group, log out and log back in over SSH,
then verify with:

  docker info
  docker compose version

EOF
