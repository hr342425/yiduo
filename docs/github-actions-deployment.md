# GitHub Actions 自动部署

本文档说明如何通过 GitHub Actions 自动部署到云服务器。它适用于两种部署模式：

```text
production  正式模式，site 容器开放 80
ip-test     备案完成前的临时测试模式，site 容器开放公网 8000
```

默认建议：

```text
备案未完成：手动触发 workflow，选择 ip-test
备案完成后：push main 自动 production 部署
```

## 1. 工作方式

GitHub Actions 不保存服务器数据，也不直接把构建产物推到服务器。流程是：

```text
push main 或手动触发 workflow
  -> GitHub Actions 安装依赖
  -> npm run check
  -> npm run build
  -> 校验部署资产
  -> SSH 到云服务器
  -> cd /opt/yiduo/app
  -> 执行 ./deploy/deploy.sh
  -> 服务器自己 git pull、docker compose build、docker compose up
```

## 2. 服务器前置条件

服务器需要先完成一次手动准备：

```bash
sudo mkdir -p /opt/yiduo
sudo chown -R "$USER":"$USER" /opt/yiduo
```

按 `docs/deployment.md` 的“安装基础软件”章节安装 Docker、Git。该章节使用阿里云 Docker CE apt 源，并可配置阿里云专属镜像加速地址。安装后确认当前 SSH 用户可以执行 Docker：

```bash
docker --version
docker compose version
docker info
```

首次拉取代码：

```bash
git clone <repo-url> /opt/yiduo/app
cd /opt/yiduo/app
cp .env.example .env
```

如果仓库是私有仓库，服务器也需要能执行 `git pull`。推荐给服务器配置 GitHub Deploy Key：

```bash
ssh-keygen -t ed25519 -C "yiduo-server-deploy" -f ~/.ssh/yiduo_repo_key
cat ~/.ssh/yiduo_repo_key.pub
```

把公钥添加到 GitHub 仓库：

```text
Settings -> Deploy keys -> Add deploy key
```

然后在服务器的 `~/.ssh/config` 中配置该 key，确保：

```bash
cd /opt/yiduo/app
git pull --ff-only
```

可以成功执行。

## 3. GitHub Secrets

在 GitHub 仓库配置：

```text
Settings -> Secrets and variables -> Actions -> Repository secrets
```

新增：

```text
DEPLOY_HOST      云服务器公网 IP
DEPLOY_USER      SSH 用户名，例如 ubuntu 或 root
DEPLOY_SSH_KEY   GitHub Actions 连接服务器用的私钥
DEPLOY_PORT      SSH 端口，可选；不填默认 22
```

建议为 GitHub Actions 单独创建服务器登录 key：

```bash
ssh-keygen -t ed25519 -C "github-actions-yiduo-deploy" -f ./github-actions-yiduo-deploy
```

把公钥内容追加到服务器对应用户的：

```text
~/.ssh/authorized_keys
```

把私钥内容填入 GitHub Secret：

```text
DEPLOY_SSH_KEY
```

## 4. GitHub Variables

可选配置：

```text
Settings -> Secrets and variables -> Actions -> Variables
```

新增：

```text
DEPLOY_MODE=production
```

可选值：

```text
production
ip-test
```

如果不配置，默认使用 `production`。

## 5. 自动部署

`.github/workflows/deploy.yml` 会在 `main` 分支 push 后自动执行：

```text
1. 安装 Node 依赖
2. 运行 Astro 类型检查
3. 构建静态站点
4. 校验部署资产
5. SSH 到服务器执行 deploy/deploy.sh
```

正式部署默认执行：

```bash
DEPLOY_MODE=production BRANCH=main ./deploy/deploy.sh
```

这会使用：

```bash
docker compose -f docker-compose.yml up -d --build
```

应用绑定：

```text
0.0.0.0:80 -> Nginx -> Astro dist
```

## 6. 备案前 IP 测试自动部署

备案未完成时，可以在 GitHub Actions 页面手动触发：

```text
Actions -> Deploy -> Run workflow -> deploy_mode: ip-test
```

这会在服务器执行：

```bash
DEPLOY_MODE=ip-test ./deploy/deploy.sh
```

实际使用：

```bash
docker compose -f docker-compose.ip-test.yml up -d --build
```

应用会临时开放：

```text
http://云服务器公网IP:8000
```

仍然需要你在云厂商安全组和服务器防火墙中临时开放 `8000`。具体见：

```text
docs/ip-test-deployment.md
```

测试完成后删除 `8000` 入站规则。

## 7. 常见问题

### SSH 连接失败

检查：

```text
DEPLOY_HOST 是否是公网 IP
DEPLOY_USER 是否正确
DEPLOY_PORT 是否正确
DEPLOY_SSH_KEY 是否是私钥
服务器 ~/.ssh/authorized_keys 是否包含对应公钥
云厂商安全组是否允许 GitHub Actions 来源访问 SSH
```

如果服务器 SSH 只允许固定 IP，而 GitHub Actions 出口 IP 不固定，建议改用自托管 runner，或者临时使用手动 SSH 部署。

### git pull 失败

说明服务器没有仓库读取权限。检查服务器上：

```bash
cd /opt/yiduo/app
git pull --ff-only
```

如果失败，给服务器配置 GitHub Deploy Key。

如果失败原因是服务器工作区有本地代码改动，而这些改动不需要保留，可以手动执行：

```bash
cd /opt/yiduo/app
DEPLOY_MODE=production FORCE_SYNC=1 ./deploy/deploy.sh
```
