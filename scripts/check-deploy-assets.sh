#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "deploy asset check failed: $*" >&2
  exit 1
}

require_file() {
  local file="$1"
  [ -f "$file" ] || fail "missing $file"
}

require_executable() {
  local file="$1"
  [ -x "$file" ] || fail "$file is not executable"
}

require_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

require_file Dockerfile
require_file .dockerignore
require_file .env.example
require_file docker-compose.yml
require_file docker-compose.ip-test.yml
require_file deploy/deploy.sh
require_file deploy/nginx.conf
require_file deploy/nginx.conf.example
require_file docs/deployment.md
require_file docs/ip-test-deployment.md
require_file scripts/install-docker-ubuntu-aliyun.sh

require_executable deploy/deploy.sh
require_executable scripts/install-docker-ubuntu-aliyun.sh

require_contains Dockerfile "npm ci"
require_contains Dockerfile "npm run build"
require_contains Dockerfile "alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3 AS site-build"
require_contains Dockerfile "npmmirror.com/mirrors/node"
require_contains Dockerfile "registry.npmmirror.com"
require_contains Dockerfile "yum install -y nginx"
require_contains Dockerfile "COPY --from=site-build /app/dist /usr/share/nginx/html"

require_contains docker-compose.yml "yiduo-site"
require_contains docker-compose.yml "80:80"
require_contains docker-compose.yml "deploy/nginx.conf"
require_contains docker-compose.ip-test.yml "8000:80"

require_contains deploy/deploy.sh "git pull --ff-only"
require_contains deploy/deploy.sh "FORCE_SYNC"
require_contains deploy/deploy.sh "docker compose"
require_contains deploy/deploy.sh "DEPLOY_MODE=production"
require_contains deploy/deploy.sh "DEPLOY_MODE=ip-test"
require_contains deploy/deploy.sh "curl -fsS"

require_contains deploy/nginx.conf 'try_files $uri $uri/ /index.html'
require_contains deploy/nginx.conf "Cache-Control"
require_contains deploy/nginx.conf.example "server_name yiduo.your-domain.com"

require_contains docs/deployment.md "ICP备案"
require_contains docs/deployment.md "mirrors.aliyun.com/docker-ce"
require_contains docs/deployment.md "403 Forbidden"
require_contains docs/deployment.md "DEPLOY_MODE=production ./deploy/deploy.sh"
require_contains docs/ip-test-deployment.md "http://云服务器公网IP:8000"
require_contains docs/ip-test-deployment.md "docker-compose.ip-test.yml"
require_contains docs/ip-test-deployment.md "mirrors.aliyun.com/docker-ce"
require_contains scripts/install-docker-ubuntu-aliyun.sh "mirrors.aliyun.com/docker-ce"
require_contains scripts/install-docker-ubuntu-aliyun.sh "docker-compose-plugin"
require_contains scripts/install-docker-ubuntu-aliyun.sh "looks like a placeholder"

echo "Deployment assets look good."
