# DeepSeek Harness Docker 局域网部署

本方案运行 npm 发布版 `@deepseek-ai/dsh@0.1.2-rc.1`。Harness 在容器内仍只监听 `127.0.0.1:3080`；Caddy 与 Harness 共享网络命名空间，在服务器的 `10.61.16.33:8443` 上提供 HTTPS、密码认证和反向代理。

不要删除 Caddy 认证，也不要将 Docker socket、宿主机根目录或用户主目录挂载进容器。Harness 的 Web 界面可以执行代码，局域网访问者一旦登录，就拥有 `workspace/` 内的读写和命令执行能力。

## 1. 准备服务器

服务器需要 Linux、Docker Engine 和 Docker Compose v2：

```bash
ssh albin@10.61.16.33
docker version
docker compose version
sudo mkdir -p /opt/deepseek-harness
sudo chown albin:albin /opt/deepseek-harness
```

将本目录中的文件传到 `/opt/deepseek-harness/`，然后执行：

```bash
cd /opt/deepseek-harness
mkdir -p data workspace
sudo chown -R 1000:1000 data workspace
chmod 700 data workspace
```

如服务器地址不是 `10.61.16.33`，修改下面生成的 `.env` 中的 `LAN_IP`。

## 2. 设置访问密码

用 Caddy 生成 bcrypt 密码散列。密码不会以明文写入磁盘：

```bash
cd /opt/deepseek-harness
read -rsp 'Web access password: ' DSH_WEB_PASSWORD && echo
DSH_WEB_HASH="$(docker run --rm caddy:2.10.2-alpine caddy hash-password --plaintext "$DSH_WEB_PASSWORD")"
printf "LAN_IP=10.61.16.33\nBASIC_AUTH_HASH='%s'\n" "$DSH_WEB_HASH" > .env
unset DSH_WEB_PASSWORD DSH_WEB_HASH
chmod 600 .env
```

## 3. 启动并检查

```bash
docker compose config --quiet
docker compose up -d --build
docker compose ps
docker compose logs -f --tail=100
```

日志中看到 Harness 已监听 `http://127.0.0.1:3080`、两个服务均正常后，按 `Ctrl+C` 退出日志查看，不会停止容器。

## 4. 信任局域网 HTTPS 证书

Caddy 使用自己的内部 CA。导出根证书：

```bash
cd /opt/deepseek-harness
docker compose cp gateway:/data/caddy/pki/authorities/local/root.crt ./root.crt
```

将 `root.crt` 安全地传到每台需要访问的电脑。Windows 上以管理员身份运行：

```powershell
certutil -addstore -f Root .\root.crt
```

Ubuntu/Debian 客户端：

```bash
sudo cp root.crt /usr/local/share/ca-certificates/deepseek-harness.crt
sudo update-ca-certificates
```

然后访问：

```text
https://10.61.16.33:8443
```

用户名是 `albin`，密码是第 2 步输入的密码。首次进入后，在 Web 界面的模型设置中配置 DeepSeek API Key；它会保存在挂载的 `data/` 中，而不是写进镜像。

## 5. 局域网与防火墙

Compose 只把端口绑定到 `LAN_IP`，不会监听服务器的其他地址。仍应在服务器或上游防火墙中只允许实际局域网网段访问 TCP `8443`。先用以下命令确认网段和网卡，再按服务器现有的 `ufw`、`firewalld` 或边界防火墙规则配置：

```bash
ip -4 address show
ip -4 route show
```

注意：Docker 发布端口在部分系统上可能绕过普通 UFW INPUT 规则。不要仅凭“UFW 已开启”判断端口已限制；从局域网外的测试机实际验证 `8443` 不可达。不要开放 `3080`，它只应存在于容器共享网络中。

## 运维

查看状态和日志：

```bash
docker compose ps
docker compose logs -f --tail=200
```

重启：

```bash
docker compose restart
```

更新时先备份 `data/`，再修改 `compose.yaml` 中固定的 `DSH_VERSION`，重新构建：

```bash
tar -czf "deepseek-harness-data-$(date +%F).tgz" data
docker compose build harness
docker compose up -d
```

也可以使用仓库中的自动更新脚本。它会查询 npm 的 `latest` 版本，备份 `data/`、`workspace/` 和版本配置，更新 Harness，重新构建部署，并检查容器内实际版本：

```bash
./update-harness.sh
```

如需更新到指定版本：

```bash
./update-harness.sh 0.1.2-rc.1
```

备份默认保存在 `backups/`，脚本不会删除 `data/` 或 `workspace/`。当前运行版本也可以这样查看：

```bash
docker compose exec harness \
  node -p "require('/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json').version"
```


停止服务但保留数据：

```bash
docker compose down
```

项目文件放在服务器的 `/opt/deepseek-harness/workspace/`，Harness 中显示为 `/workspace`。需要额外的编译器或语言运行时，应在 `Dockerfile` 中安装后重建镜像，不要挂载宿主机 Docker socket。
