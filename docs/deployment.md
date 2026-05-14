# 云服务器部署方案

本文档覆盖长春市奕多经贸有限公司官网的单机部署：服务器安装 Docker，仓库由 Docker 多阶段构建生成 Astro 静态产物，最终由 Nginx 容器托管。

## 1. 部署架构

```text
已备案域名
  -> DNS A 记录
云服务器公网 IP
  -> 80
Docker Compose site 容器
  -> Nginx
  -> /usr/share/nginx/html 静态文件
```

生产模式只开放公网 `80`：

```text
0.0.0.0:80 -> Docker Nginx -> Astro dist
```

后续如果要接入 HTTPS，可以在云厂商负载均衡/CDN 上终止 TLS，或把本仓库的 Nginx 配置扩展为挂载证书并开放 `443`。

## 2. 域名 DNS 与备案

建议使用正式官网域名或业务子域名，例如：

```text
yiduo.your-domain.com
www.yiduo.your-domain.com
```

DNS 配置：

```text
记录类型：A
主机记录：yiduo / www
记录值：云服务器公网 IP
TTL：默认
```

如果云服务器在中国大陆，请确认：

```text
1. 域名 ICP备案 状态正常。
2. 如果备案不在当前云厂商，需要按云厂商要求完成备案接入或接入变更。
3. 云厂商控制台安全组已开放 80。
```

## 3. 服务器目录

```text
/opt/yiduo/app/    # Git 仓库代码
```

初始化目录：

```bash
sudo mkdir -p /opt/yiduo
sudo chown -R "$USER":"$USER" /opt/yiduo
```

## 4. 安装基础软件

Ubuntu 服务器建议使用阿里云 Docker CE apt 源安装，不使用 `get.docker.com`。全新服务器可直接执行：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release git ufw

# 可选：全新服务器清理 Ubuntu 自带或旧版 Docker 包，避免包冲突。
sudo apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true

# 添加阿里云 Docker CE GPG key。
sudo install -m 0755 -d /etc/apt/keyrings
sudo rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 添加阿里云 Docker CE apt 源。
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装 Docker Engine、Buildx 和 Compose 插件。
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

如果你有阿里云容器镜像服务控制台里的专属镜像加速地址，可以再配置 Docker Hub 拉取加速。将下面的 `https://你的专属ID.mirror.aliyuncs.com` 替换成控制台给出的真实地址：

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'JSON'
{
  "registry-mirrors": ["https://你的专属ID.mirror.aliyuncs.com"]
}
JSON

sudo systemctl daemon-reload
sudo systemctl restart docker
```

仓库里也提供了脚本版安装命令：

```bash
bash scripts/install-docker-ubuntu-aliyun.sh
```

如果是全新服务器，并且需要先清理 Ubuntu 自带或旧版 Docker 包：

```bash
REMOVE_OLD_DOCKER_PACKAGES=1 bash scripts/install-docker-ubuntu-aliyun.sh
```

如果要一并写入专属镜像加速地址：

```bash
DOCKER_REGISTRY_MIRROR="https://你的专属ID.mirror.aliyuncs.com" bash scripts/install-docker-ubuntu-aliyun.sh
```

重新登录 SSH 后验证：

```bash
docker --version
docker compose version
docker info
```

开启防火墙：

```bash
sudo ufw allow 22
sudo ufw allow 80
sudo ufw enable
```

云厂商安全组也只开放 `22`、`80`。正式上线不需要开放 `4321`、`5173`、`8000` 等开发端口。

如果服务器上已经有宿主机 Nginx/Caddy 占用 `80`，需要先停掉，或改成本仓库容器只监听另一个端口再由宿主机代理：

```bash
sudo systemctl stop nginx || true
sudo systemctl disable nginx || true
sudo systemctl stop caddy || true
sudo systemctl disable caddy || true
```

## 5. 首次部署

拉取代码：

```bash
git clone <repo-url> /opt/yiduo/app
cd /opt/yiduo/app
```

可选：复制 Compose 环境变量示例。默认值已经能直接运行，只有需要改镜像名或容器名时才需要编辑。

```bash
cp .env.example .env
```

如果要把 Nginx 的 `server_name` 限定为真实域名：

```bash
cp deploy/nginx.conf.example deploy/nginx.conf
nano deploy/nginx.conf
```

把 `yiduo.your-domain.com` 和 `www.yiduo.your-domain.com` 替换为真实域名。

一键部署：

```bash
DEPLOY_MODE=production ./deploy/deploy.sh
```

脚本会执行：

```text
git fetch origin main
git checkout main
git pull --ff-only origin main
docker compose -f docker-compose.yml build site
docker compose -f docker-compose.yml up -d --remove-orphans
curl http://127.0.0.1/healthz
```

访问：

```text
http://你的域名/
```

## 6. 日常更新代码

服务器上执行：

```bash
cd /opt/yiduo/app
DEPLOY_MODE=production ./deploy/deploy.sh
```

指定分支：

```bash
BRANCH=main DEPLOY_MODE=production ./deploy/deploy.sh
```

如果服务器工作区有临时改动并阻塞同步，而这些改动确认不需要保留，可以强制对齐远端：

```bash
FORCE_SYNC=1 DEPLOY_MODE=production ./deploy/deploy.sh
```

`FORCE_SYNC=1` 会执行 `git reset --hard origin/$BRANCH`，只建议在确认服务器上的代码改动可以丢弃时使用。

## 7. 常用运维命令

查看状态：

```bash
cd /opt/yiduo/app
docker compose ps
```

查看日志：

```bash
docker compose logs -f site
```

重启：

```bash
docker compose restart site
```

停止：

```bash
docker compose down
```

检查 Nginx 配置：

```bash
docker compose exec site nginx -t
```

健康检查：

```bash
curl -fsS http://127.0.0.1/healthz
```

## 8. 上线检查清单

```text
域名 A 记录已指向云服务器公网 IP
ICP备案 状态正常
云厂商安全组只开放 22、80
服务器防火墙只开放 22、80
服务器 Docker 与 Docker Compose 可用
/opt/yiduo/app 是最新代码
DEPLOY_MODE=production ./deploy/deploy.sh 成功
http://127.0.0.1/healthz 返回 ok
正式域名可以访问官网首页
刷新页面后图片、样式、favicon 正常加载
```
