#!/usr/bin/env bash
set -euo pipefail

BUNDLE=""
INSTALL_DIR="/usr/local/datakit"
MODE="host,docker"
PYTHON_DDTRACE="off"
ENABLE_SERVICE="on"
SERVICE_NAME="apm-inject"
JAVA_AGENT_URL="https://dtdg.co/latest-java-tracer"

usage() {
  cat <<'USAGE'
Usage:
  server_install.sh --bundle <tar.gz> [options]

Options:
  --bundle <file>            Bundle produced by scripts/package.sh (required)
  --install-dir <dir>        Install root (default: /usr/local/datakit)
  --mode <mode>              host | docker | host,docker | disable (default: host,docker)
  --python-ddtrace <on|off>  Install ddtrace via pip on host (default: off)
  --enable-service <on|off>  Install + enable systemd oneshot service (default: on)
  --service-name <name>      systemd service name without suffix (default: apm-inject)
  --java-agent-url <url>     Fallback URL when jar missing in bundle
  -h, --help                 Show help
USAGE
}

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERROR] run as root (or use sudo)" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      BUNDLE="$2"
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
    --java-agent-url)
      JAVA_AGENT_URL="$2"
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

if [[ -z "$BUNDLE" ]]; then
  echo "[ERROR] --bundle is required" >&2
  usage
  exit 1
fi

if [[ ! -f "$BUNDLE" ]]; then
  echo "[ERROR] bundle not found: $BUNDLE" >&2
  exit 1
fi

need_root

echo "[INFO] extracting bundle to ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"
tar -xzf "$BUNDLE" -C "$INSTALL_DIR"

INJ_DIR="$INSTALL_DIR/apm_inject"
INJ_BIN="$INJ_DIR/bin/injectctl"

if [[ ! -d "$INJ_DIR/inject" ]]; then
  echo "[ERROR] invalid bundle layout: $INJ_DIR/inject not found" >&2
  exit 1
fi

chmod +x "$INJ_DIR/inject/dkrunc" "$INJ_DIR/inject/rewriter" || true
if [[ -f "$INJ_BIN" ]]; then
  chmod +x "$INJ_BIN"
else
  echo "[ERROR] injectctl not found in bundle: $INJ_BIN" >&2
  exit 1
fi

if [[ ! -f "$INJ_DIR/lib/java/dd-java-agent.jar" ]]; then
  echo "[WARN] dd-java-agent.jar missing in bundle, downloading from ${JAVA_AGENT_URL}"
  mkdir -p "$INJ_DIR/lib/java"
  curl -fL --retry 3 --connect-timeout 10 \
    -o "$INJ_DIR/lib/java/dd-java-agent.jar" \
    "$JAVA_AGENT_URL"
fi

if [[ "$PYTHON_DDTRACE" == "on" ]]; then
  echo "[INFO] installing python ddtrace on host"
  PY_BIN=""
  if command -v python3 >/dev/null 2>&1; then
    PY_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PY_BIN="python"
  fi

  if [[ -n "$PY_BIN" ]]; then
    "$PY_BIN" -m pip install --upgrade pip || true
    "$PY_BIN" -m pip install ddtrace
  else
    echo "[WARN] python not found, skip ddtrace install"
  fi
fi

echo "[INFO] applying injection mode: ${MODE}"
"$INJ_BIN" -action install -mode "$MODE" -install-dir "$INSTALL_DIR"

if [[ "$ENABLE_SERVICE" == "on" ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    cat > "$UNIT_FILE" <<UNIT
[Unit]
Description=APM Auto Inject Bootstrap
After=network.target docker.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${INJ_BIN} -action install -mode ${MODE} -install-dir ${INSTALL_DIR}
ExecStop=${INJ_BIN} -action uninstall -install-dir ${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}.service"
    echo "[INFO] systemd service enabled: ${SERVICE_NAME}.service"
  else
    echo "[WARN] systemctl not found, skip service setup"
  fi
fi

echo "[OK] install finished"
echo "[NEXT] run: ${INSTALL_DIR}/apm_inject/bin/injectctl -action install -mode host,docker -install-dir ${INSTALL_DIR}"
