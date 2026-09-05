# Harness 自动更新脚本设计

## 目标

新增 `update-harness.sh`，用于在部署目录中自动把 DeepSeek Harness 更新到 npm 的最新 `latest` 版本，并重新构建、部署和验证服务。

脚本只负责 Harness 版本，不修改 Caddy、TLS、Basic Auth、模型提供商、`data/` 或 `workspace/` 的内容。

## 使用方式

```bash
./update-harness.sh
./update-harness.sh 0.1.2-rc.1
```

不传参数时查询 `@deepseek-ai/dsh` 的 npm `latest` 标签；传入参数时使用指定版本，并先通过 npm 校验该版本存在。

## 执行流程

1. 定位脚本所在的部署目录并检查 `docker`、Docker Compose 和 npm 查询能力。
2. 读取当前 `DSH_VERSION`，拒绝空版本或无法识别的配置。
3. 查询目标版本并在目标版本与当前版本相同时直接退出，不重建服务。
4. 在本地备份目录创建带时间戳的压缩包，包含 `data/` 和 `workspace/`；同时保存 `Dockerfile` 与 `compose.yaml` 的版本配置副本。
5. 更新 `compose.yaml` 的 `DSH_VERSION` 和 `Dockerfile` 的 `ARG DSH_VERSION`。
6. 运行 `docker compose config --quiet` 做配置校验。
7. 执行 `docker compose build harness`，然后执行 `docker compose up -d`，不主动拉取 Node 基础镜像。
8. 等待 Harness 的 Compose healthcheck 通过，读取容器内实际安装的 npm 包版本，并确认与目标版本一致。
9. 输出目标版本、备份位置和服务状态。

## 错误处理与恢复

- 使用 `set -Eeuo pipefail`，任意关键步骤失败时立即停止。
- 构建或配置校验失败时恢复 `Dockerfile` 和 `compose.yaml` 的原始版本配置。
- 不删除旧镜像、数据目录或工作区，失败时保留现场供排查。
- 备份目录默认位于部署目录的 `backups/`，权限设置为仅所有者可访问；该目录加入 `.gitignore`，避免运行数据进入版本库。
- 脚本不会自动回滚已经成功启动的新容器，因为新版本可能已经执行数据格式迁移；恢复时以备份为准，回滚操作由管理员明确执行。

## 实现边界

- npm 查询优先使用宿主机 `npm`；宿主机没有 npm 时，使用现有 Harness 容器中的 npm 查询 registry，避免要求额外安装 Node.js。
- 版本替换只针对当前仓库已有的两个固定字段，不改动其他文本。
- 构建不使用 `--pull` 或 `--no-cache`；版本参数变化会使 Harness 安装层失效并重新安装目标版本，同时复用已完成的系统依赖层。

## 验证

- `bash -n update-harness.sh`
- 在版本相同、版本不同、npm 查询失败和 Compose 校验失败时检查脚本的退出行为。
- 真实部署后通过容器内 `package.json` 版本和 Compose 健康状态确认结果。
