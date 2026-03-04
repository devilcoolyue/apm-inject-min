# APM Inject 全流程演示文档（本地打包 -> 服务器部署 -> 启动 -> 验证）

本文档基于 `apm-inject-min` 当前代码，给出演示环境可直接执行的全流程。

## 1. 你将演示什么

- 本地构建并打包 APM 注入组件（支持 `linux/darwin` + `amd64/arm64`）
- 打包时自动下载 Java Agent 探针
- 部署到 Linux 服务器
- 默认同时开启宿主机 + Docker 注入（`host,docker`）
- 启动 systemd 服务保证重启后仍生效
- 验证注入是否生效

> 当前版本已做自动化增强：
> - `injectctl` 默认模式改为 `host,docker`
> - 新增 `scripts/package.sh` / `scripts/server_install.sh` / `scripts/deploy_remote.sh` / `scripts/verify.sh`

---

## 2. 准备工作

## 2.1 本地环境

- Go 1.21+
- Bash
- `tar`, `curl`
- 可选：Docker（用于在 macOS 上构建 Linux launcher 动态库）

## 2.2 目标服务器环境

- Linux（建议 x86_64 或 arm64）
- root 权限（或 sudo）
- Docker（若要演示 Docker 注入）
- `curl`
- 可选：`python3 + pip`（若演示 Python 注入）
- 可选：`java/javac`（若演示 Host Java 进程注入）

---

## 3. 本地打包

在项目根目录执行：

```bash
cd /Users/tianlanxu/Documents/staryea/apm-inject-min
```

### 3.1 打 Linux 包（推荐演示）

```bash
scripts/package.sh --os linux --arch amd64 --version demo-v1
```

说明：

- 默认会构建：`dkrunc`、`rewriter`、`injectctl`
- 默认会下载 Java Agent：`dd-java-agent.jar`
- 默认会尝试构建 launcher（`apm_launcher.so` / `apm_launcher_musl.so`）

产物：

- `dist/packages/datakit-apm-inject-linux-amd64-demo-v1.tar.gz`

### 3.2 常用参数

```bash
# 跳过 launcher（调试时）
scripts/package.sh --os linux --arch arm64 --version demo --skip-launcher

# 跳过 Java agent 下载
scripts/package.sh --os linux --arch arm64 --version demo --skip-java-agent

# 自定义 Java agent URL
scripts/package.sh --os linux --arch arm64 --version demo \
  --java-agent-url https://dtdg.co/latest-java-tracer
```

---

## 4. 部署到服务器

## 4.1 推荐：一键远程部署

```bash
scripts/deploy_remote.sh \
  --host root@<SERVER_IP> \
  --bundle dist/packages/datakit-apm-inject-linux-amd64-demo-v1.tar.gz \
  --mode host,docker \
  --python-ddtrace on \
  --enable-service on
```

该命令会：

1. `scp` 上传 bundle、安装脚本和校验脚本
2. 远程执行 `server_install.sh`
3. 解压到 `/usr/local/datakit`
4. 默认执行 `injectctl -action install -mode host,docker`
5. 安装并启动 systemd 服务（`apm-inject.service`）

## 4.2 手动部署（可选）

```bash
# 本地上传
scp dist/packages/datakit-apm-inject-linux-amd64-demo-v1.tar.gz root@<SERVER_IP>:/tmp/
scp scripts/server_install.sh root@<SERVER_IP>:/tmp/
scp scripts/verify.sh root@<SERVER_IP>:/tmp/

# 远程安装
ssh root@<SERVER_IP> \
  "bash /tmp/server_install.sh --bundle /tmp/datakit-apm-inject-linux-amd64-demo-v1.tar.gz --mode host,docker --python-ddtrace on --enable-service on"
```

---

## 5. 启动服务（默认 host + docker）

如果你使用 `server_install.sh --enable-service on`，服务会自动启动。

检查：

```bash
systemctl status apm-inject.service
systemctl is-enabled apm-inject.service
```

手工执行（无需 service）：

```bash
/usr/local/datakit/apm_inject/bin/injectctl \
  -action install \
  -mode host,docker \
  -install-dir /usr/local/datakit
```

---

## 6. 验证注入

## 6.1 一键基础验证

```bash
/usr/local/datakit/apm_inject/bin/injectctl -action install -mode host,docker -install-dir /usr/local/datakit
bash /tmp/apm-inject-demo/verify.sh --install-dir /usr/local/datakit
```


## 6.2 手工关键检查

### 宿主机注入检查

```bash
grep apm_launcher /etc/ld.so.preload
```

期望：看到 `/usr/local/datakit/apm_inject/inject/apm_launcher...`

### Docker 注入检查

```bash
docker info --format '{{.DefaultRuntime}}'
```

期望：`dk-runc`

### Java Agent 文件检查

```bash
ls -l /usr/local/datakit/apm_inject/lib/java/dd-java-agent.jar
```

### Docker 环境变量注入检查（简单烟测）

```bash
docker run --rm ubuntu:22.04 bash -lc 'env | grep -E "^LD_PRELOAD=|^ENV_DATAKIT_SOCKET_ADDR="'
```

期望：至少看到 `LD_PRELOAD=/usr/local/datakit/apm_inject/inject/apm_launcher.so`

---

## 7. 演示建议流程（10~15 分钟）

1. 展示本地打包命令和产物
2. 执行一键远程部署
3. 展示 `systemctl status apm-inject.service`
4. 展示 `docker info` 的 runtime 已切换为 `dk-runc`
5. 展示 `/etc/ld.so.preload` 已写入 launcher
6. 运行 `verify.sh` 给出 PASS/WARN

---

## 8. 回滚/卸载

```bash
/usr/local/datakit/apm_inject/bin/injectctl -action uninstall -install-dir /usr/local/datakit

# 若启用了 service
systemctl disable --now apm-inject.service
rm -f /etc/systemd/system/apm-inject.service
systemctl daemon-reload
```

如果 Docker 已有历史容器需要切回 `runc`，可结合你现有运维流程处理容器 runtime 迁移。

---

## 9. 常见问题

1. macOS 打 Linux 包缺 launcher
- 原因：本机无法直接产 Linux `.so`
- 解决：安装 Docker，或先用 `--skip-launcher` 验证其他流程

2. Java/Python 注入不生效
- 检查 `dd-java-agent.jar` 是否存在
- 检查 `ddtrace-run` 是否可用（Python 场景）
- 检查 `/etc/ld.so.preload` 是否包含 launcher

3. Docker 注入不生效
- 检查 `docker info` 默认 runtime 是否是 `dk-runc`
- 检查 `/etc/docker/daemon.json` 中 `default-runtime` 与 `runtimes.dk-runc.path`
