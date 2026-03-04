#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST=""
BUNDLE=""
REMOTE_TMP="/tmp/apm-inject-demo"
SSH_PORT="22"
INSTALL_DIR="/usr/local/datakit"
MODE="host,docker"
PYTHON_DDTRACE="off"
ENABLE_SERVICE="on"
SERVICE_NAME="apm-inject"

usage() {
  cat <<'USAGE'
Usage:
  deploy_remote.sh --host <user@ip> --bundle <tar.gz> [options]

Options:
  --host <user@ip>            Remote SSH host (required)
  --bundle <file>             Local bundle path (required)
  --ssh-port <port>           SSH port (default: 22)
  --remote-tmp <dir>          Remote temp dir (default: /tmp/apm-inject-demo)
  --install-dir <dir>         Install root on remote (default: /usr/local/datakit)
  --mode <mode>               host | docker | host,docker | disable (default: host,docker)
  --python-ddtrace <on|off>   Install host ddtrace on remote (default: off)
  --enable-service <on|off>   Enable systemd service on remote (default: on)
  --service-name <name>       systemd service name (default: apm-inject)
  -h, --help                  Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      REMOTE_HOST="$2"
      shift 2
      ;;
    --bundle)
      BUNDLE="$2"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="$2"
      shift 2
      ;;
    --remote-tmp)
      REMOTE_TMP="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --python-ddtrace)
      PYTHON_DDTRACE="$2"
      shift 2
      ;;
    --enable-service)
      ENABLE_SERVICE="$2"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REMOTE_HOST" || -z "$BUNDLE" ]]; then
  echo "[ERROR] --host and --bundle are required" >&2
  usage
  exit 1
fi

if [[ ! -f "$BUNDLE" ]]; then
  echo "[ERROR] bundle not found: $BUNDLE" >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

echo "[INFO] preparing remote dir: ${REMOTE_TMP}"
ssh -p "$SSH_PORT" "$REMOTE_HOST" "mkdir -p '$REMOTE_TMP'"

echo "[INFO] uploading bundle and scripts"
scp -P "$SSH_PORT" \
  "$BUNDLE" \
  "$SCRIPT_DIR/server_install.sh" \
  "$SCRIPT_DIR/verify.sh" \
  "$REMOTE_HOST:$REMOTE_TMP/"

REMOTE_BUNDLE="$REMOTE_TMP/$(basename "$BUNDLE")"
REMOTE_INSTALLER="$REMOTE_TMP/server_install.sh"

echo "[INFO] running remote install"
ssh -p "$SSH_PORT" "$REMOTE_HOST" \
  "sudo bash '$REMOTE_INSTALLER' --bundle '$REMOTE_BUNDLE' --install-dir '$INSTALL_DIR' --mode '$MODE' --python-ddtrace '$PYTHON_DDTRACE' --enable-service '$ENABLE_SERVICE' --service-name '$SERVICE_NAME'"

echo "[OK] remote deploy done"
echo "[NEXT] verify on remote: sudo bash ${REMOTE_TMP}/verify.sh --install-dir ${INSTALL_DIR}"
