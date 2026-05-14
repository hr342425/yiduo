#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/yiduo/app}"
DEPLOY_MODE="${DEPLOY_MODE:-production}"
BRANCH="${BRANCH:-main}"
FORCE_SYNC="${FORCE_SYNC:-0}"
HEALTH_URL="${HEALTH_URL:-}"

log() {
  printf '[deploy] %s\n' "$*"
}

case "$DEPLOY_MODE" in
  production)
    COMPOSE_ARGS=(-f docker-compose.yml)
    DEFAULT_HEALTH_URL="http://127.0.0.1/healthz"
    ;;
  ip-test)
    COMPOSE_ARGS=(-f docker-compose.ip-test.yml)
    DEFAULT_HEALTH_URL="http://127.0.0.1:8000/healthz"
    ;;
  *)
    echo "Unsupported DEPLOY_MODE: $DEPLOY_MODE" >&2
    echo "Use DEPLOY_MODE=production or DEPLOY_MODE=ip-test." >&2
    exit 1
    ;;
esac

HEALTH_URL="${HEALTH_URL:-$DEFAULT_HEALTH_URL}"

if [ "$FORCE_SYNC" != "0" ] && [ "$FORCE_SYNC" != "1" ]; then
  echo "Unsupported FORCE_SYNC: $FORCE_SYNC" >&2
  echo "Use FORCE_SYNC=0 or FORCE_SYNC=1." >&2
  exit 1
fi

cd "$APP_DIR"

log "syncing code from origin/$BRANCH"
git fetch origin "$BRANCH"
if [ "$FORCE_SYNC" = "1" ]; then
  git checkout -B "$BRANCH" "origin/$BRANCH"
  git reset --hard "origin/$BRANCH"
else
  if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    git checkout "$BRANCH"
  else
    git checkout -b "$BRANCH" "origin/$BRANCH"
  fi
  git pull --ff-only origin "$BRANCH"
fi

log "building site image"
docker compose "${COMPOSE_ARGS[@]}" build site

log "starting containers"
docker compose "${COMPOSE_ARGS[@]}" up -d --remove-orphans

log "checking health: $HEALTH_URL"
for attempt in $(seq 1 20); do
  if curl -fsS "$HEALTH_URL" >/dev/null; then
    log "deploy complete. mode=$DEPLOY_MODE branch=$BRANCH force_sync=$FORCE_SYNC"
    exit 0
  fi
  sleep 1
  log "health check retry $attempt/20"
done

echo "Health check failed: $HEALTH_URL" >&2
docker compose "${COMPOSE_ARGS[@]}" ps >&2 || true
docker compose "${COMPOSE_ARGS[@]}" logs --tail=80 site >&2 || true
exit 1

