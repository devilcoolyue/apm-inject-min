# apm-inject-min

`apm-inject-min` is a minimal, standalone extraction of DataKit APM auto-injection core logic.

## Kept core logic

- Host injection via `/etc/ld.so.preload` + `apm_launcher.so`
- Docker injection via `default-runtime=dk-runc`
- Runtime rewrite for Java/Python in `rewriter`
- OCI spec rewrite in `dkrunc`

## Project layout

- `cmd/injectctl`: minimal CLI for `install/uninstall` (default mode: `host,docker`)
- `internal/apminject/utils`: install/uninstall logic
- `internal/apminject/rewriter`: Java/Python rewrite logic
- `internal/apminject/dkrunc`: Docker runtime wrapper
- `internal/apminject/apm_launcher.c`: `execve` hook shared library
- `scripts/package.sh`: one-click package builder
- `scripts/server_install.sh`: server-side install/bootstrap script
- `scripts/deploy_remote.sh`: one-command remote deploy (scp + ssh)
- `scripts/verify.sh`: host/docker verification script
- `DEMO_E2E_GUIDE.md`: full demo runbook

## Build

```bash
go mod tidy
go build ./cmd/injectctl
```

## One-click package

```bash
# linux/amd64
scripts/package.sh --os linux --arch amd64 --version demo-v1

# darwin/arm64
scripts/package.sh --os darwin --arch arm64 --version demo-v1
```

Output:

- `dist/packages/datakit-apm-inject-<os>-<arch>-<version>.tar.gz`

## Remote deploy (demo)

```bash
scripts/deploy_remote.sh \
  --host root@<SERVER_IP> \
  --bundle dist/packages/datakit-apm-inject-linux-amd64-demo-v1.tar.gz \
  --mode host,docker \
  --python-ddtrace on \
  --enable-service on
```

## Full guide

See [DEMO_E2E_GUIDE.md](DEMO_E2E_GUIDE.md) for full end-to-end instructions.
