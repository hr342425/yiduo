# 备案完成前的 IP 直连测试部署

本文档用于域名 DNS 或 ICP备案 完成前，临时通过公网 IP 验证 Docker 部署是否成功。

这不是正式上线方案。测试完成后应关闭 `8000` 公网入口，并切回 `docs/deployment.md` 中的域名 + Docker Nginx 方案。

## 1. 测试架构

```text
浏览器
  -> http://云服务器公网IP:8000
云服务器安全组 / 防火墙
  -> 临时开放 8000
Docker Compose ip-test
  -> site 容器 80
  -> Nginx 静态站点
```

与正式部署的区别：

```text
正式部署：公网只开放 80
临时测试：公网临时开放 8000，容器内部仍是 Nginx 80
```

## 2. 云服务器准备

以下命令以 Ubuntu 为例，使用阿里云 Docker CE apt 源。

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

如果服务器当前就是 `root` 登录，最后一行 `sudo usermod -aG docker "$USER"` 可以不执行；`root` 本身可以直接运行 Docker。

如果你有阿里云容器镜像服务控制台里的专属镜像加速地址，可以继续配置 Docker Hub 拉取加速：

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

也可以直接执行仓库脚本：

```bash
bash scripts/install-docker-ubuntu-aliyun.sh
```

这个脚本支持 `root` 登录和普通 sudo 用户登录。普通用户执行时会自动把当前用户加入 `docker` 组；`root` 执行时会跳过这一步。

如果是普通用户安装，重新登录 SSH 后验证；如果是 `root` 安装，可以直接验证：

```bash
docker --version
docker compose version
docker info
```

创建目录：

```bash
sudo mkdir -p /opt/yiduo
sudo chown -R "$USER":"$USER" /opt/yiduo
```

## 3. 临时开放 8000 端口

### 3.1 云厂商安全组

在云厂商控制台添加入站规则：

```text
协议：TCP
端口：8000
来源：你的当前公网 IP/32
```

如果暂时不知道你的公网 IP，可以在本机执行：

```bash
curl ifconfig.me
```

如果云厂商不支持精确限制来源，才临时使用：

```text
来源：0.0.0.0/0
```

测试完成后要马上删除这条规则。

### 3.2 服务器防火墙

优先只允许你的公网 IP：

```bash
sudo ufw allow 22
sudo ufw allow from 你的公网IP to any port 8000 proto tcp
sudo ufw enable
sudo ufw status
```

短时间测试也可以临时开放：

```bash
sudo ufw allow 8000/tcp
```

测试完成后关闭：

```bash
sudo ufw delete allow 8000/tcp
```

如果使用了按来源 IP 的规则，按 `sudo ufw status numbered` 查到编号后删除：

```bash
sudo ufw status numbered
sudo ufw delete 编号
```

## 4. 拉取代码

```bash
git clone <repo-url> /opt/yiduo/app
cd /opt/yiduo/app
```

## 5. 启动 IP 测试部署

使用临时 Compose 文件启动：

```bash
DEPLOY_MODE=ip-test ./deploy/deploy.sh
```

检查容器状态：

```bash
docker compose -f docker-compose.ip-test.yml ps
docker compose -f docker-compose.ip-test.yml logs -f site
```

服务器内健康检查：

```bash
curl -fsS http://127.0.0.1:8000/healthz
```

预期返回：

```text
ok
```

本机浏览器访问：

```text
http://云服务器公网IP:8000
```

## 6. 测试清单

建议按以下顺序测试：

```text
1. 浏览器打开 http://云服务器公网IP:8000。
2. 首页能正常加载，无空白页。
3. Logo、业务图片、favicon 正常显示。
4. 页面刷新后仍可访问。
5. 移动端浏览器打开页面，布局正常。
6. docker compose -f docker-compose.ip-test.yml restart site 后页面仍可访问。
```

测试完成后删除 `8000` 入站规则，并使用正式部署：

```bash
DEPLOY_MODE=production ./deploy/deploy.sh
```
