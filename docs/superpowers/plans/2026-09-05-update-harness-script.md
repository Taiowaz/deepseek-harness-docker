# Harness 自动更新脚本 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建一个可重复执行的脚本，自动查询并部署 npm 最新 Harness 版本，同时保留运行数据并在部署后验证实际版本。

**Architecture:** `update-harness.sh` 以脚本目录作为 Compose 工作目录，读取并替换 `compose.yaml` 与 `Dockerfile` 中的固定版本字段。更新前将运行数据和配置版本备份到权限为 `700` 的 `backups/`，部署后通过 Compose healthcheck 和容器内 package.json 双重验证；失败时恢复两个配置文件，但不自动删除新镜像或回滚可能发生的数据迁移。

**Tech Stack:** Bash 4+, Docker Compose v2, npm registry, GNU tar/sed, Node/npm（宿主机或现有 Harness 容器）。

---

### Task 1: 创建更新脚本

**Files:**
- Create: `update-harness.sh`

- [ ] **Step 1: Add argument parsing and repository checks**

实现 `--help`、零或一个版本参数；限制版本参数为 npm semver 字符集；定位脚本目录，检查 `docker compose` 和 `tar`，并从两个配置文件读取当前版本。

- [ ] **Step 2: Add npm version resolution**

无参数时查询 `npm view @deepseek-ai/dsh version --json`；有宿主机 npm 时优先使用宿主机，否则通过当前 Harness Compose 服务的 npm 查询 registry，最后使用 `node:24-bookworm-slim` 临时容器作为兜底。指定版本查询必须成功且返回值与请求版本一致。

- [ ] **Step 3: Add backup and configuration update**

在 `backups/deepseek-harness-YYYYmmdd-HHMMSS/` 创建权限为 `700` 的备份目录，压缩 `data/` 和 `workspace/`，保存两个配置文件副本；只替换两个明确的 `DSH_VERSION` 字段，并在替换后重新读取确认一致。

- [ ] **Step 4: Add deployment and verification**

按顺序执行 `docker compose config --quiet`、`docker compose build harness`、`docker compose up -d`；轮询 Harness 容器 health 状态，随后使用容器内 package.json 读取实际版本并与目标版本比较，最后打印服务状态。

- [ ] **Step 5: Add failure recovery**

用 `ERR` trap 在配置已修改且关键步骤失败时恢复两个配置文件，输出备份路径和失败原因；成功完成后关闭恢复 trap。脚本不执行 destructive 的镜像、数据或工作区删除。

### Task 2: 忽略运行备份并补充使用说明

**Files:**
- Modify: `.gitignore`
- Modify: `README.md`

- [ ] **Step 1: Ignore generated backups**

加入 `backups/`，避免包含会话和工作区内容的压缩包进入版本库。

- [ ] **Step 2: Document the update command**

在运维部分加入 `./update-harness.sh`、指定版本用法和部署后版本查询命令，明确脚本不会删除 `data/` 或 `workspace/`。

### Task 3: Static and isolated verification

**Files:**
- Create: `tests/update-harness-static.sh`

- [ ] **Step 1: Add static assertions**

测试脚本执行 `bash -n update-harness.sh`，确认脚本包含 npm latest 查询、备份、Compose 配置校验、healthcheck 等关键步骤，并确认脚本不会使用 `docker compose down --volumes`、`rm -rf data` 或 `rm -rf workspace`。

- [ ] **Step 2: Run verification**

运行 `bash tests/update-harness-static.sh`，再运行 `bash -n update-harness.sh tests/update-harness-static.sh`；不启动 Docker、不联网部署、不修改 `data/` 和 `workspace/`。
