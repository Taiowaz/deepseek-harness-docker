# 远程模型设置补丁设计

## 目标

让经 Caddy Basic Auth 保护的内网远程浏览器可以使用 Harness 的 Settings → Models 页面，同时保留当前 Docker 部署、Caddy 反代和 API 请求校验。

## 根因

Harness Web client 根据浏览器地址栏的 hostname 计算 loopback 状态。非 `localhost`、`127.0.0.0/8` 或 `[::1]` 的页面会把 Settings persistence 设为 `memory`，因此远程页面不会调用 settings RPC，最终显示 `settings are unavailable in this browser`。

## 设计

- 新增 `scripts/patch-remote-settings.sh`，定位 `@deepseek-ai/dsh-client-ui-settings/lib/client.js`。
- 将唯一目标表达式 `const persistence = ctx.remote.$host.isLoopback ? "host" : "memory";` 替换为 `const persistence = "host";`。
- 脚本接收可选 npm 全局根目录参数，默认使用 `/usr/local/lib/node_modules`，便于 Docker 构建和临时测试共用同一逻辑。
- 目标表达式匹配一次时应用；已经是补丁状态时幂等成功；匹配零次或多次且不是已补丁状态时失败，阻止镜像产生不确定行为。
- Dockerfile 在安装 Harness 后运行补丁，因此每次 Harness 版本更新都会重新应用；`update-harness.sh` 无需单独修改容器内容。

## 安全边界

补丁只改变设置页面的客户端 persistence 选择，不移除 Caddy Basic Auth、不修改 Host/Origin 请求校验，也不开放 Docker socket。内网部署仍必须保留 Caddy 认证，因为 Settings 页面可以写入凭据并触发主机能力。

## 验证

- 临时 fixture 验证首次替换成功。
- 重复执行验证幂等。
- 两处目标表达式验证构建失败。
- `bash -n`、静态检查和 `docker compose config --quiet` 验证仓库集成。
