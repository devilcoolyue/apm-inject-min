#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/usr/local/datakit"
SMOKE_HOST_JAVA="off"
SMOKE_HOST_PYTHON="off"
SMOKE_DOCKER_ENV="on"

usage() {
  cat <<'USAGE'
Usage:
  verify.sh [options]

Options:
  --install-dir <dir>          Install root (default: /usr/local/datakit)
  --smoke-host-java <on|off>   Run host Java smoke test (default: off)
  --smoke-host-python <on|off> Run host Python smoke test (default: off)
  --smoke-docker-env <on|off>  Run docker env smoke test (default: on)
  -h, --help                   Show help
USAGE
}

pass() { echo "[PASS] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --smoke-host-java)
      SMOKE_HOST_JAVA="$2"
      shift 2
      ;;
    --smoke-host-python)
      SMOKE_HOST_PYTHON="$2"
      shift 2
      ;;
    --smoke-docker-env)
      SMOKE_DOCKER_ENV="$2"
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

INJ_DIR="$INSTALL_DIR/apm_inject"

[[ -d "$INJ_DIR" ]] || fail "missing $INJ_DIR"
[[ -f "$INJ_DIR/inject/dkrunc" ]] || fail "missing dkrunc"
[[ -f "$INJ_DIR/inject/rewriter" ]] || fail "missing rewriter"
if [[ -f "$INJ_DIR/inject/apm_launcher.so" || -f "$INJ_DIR/inject/apm_launcher_musl.so" ]]; then
  pass "launcher files found"
else
  warn "launcher files missing"
fi

if grep -q "$INJ_DIR/inject/apm_launcher" /etc/ld.so.preload 2>/dev/null; then
  pass "host preload configured in /etc/ld.so.preload"
else
  warn "host preload not found in /etc/ld.so.preload"
fi

if command -v docker >/dev/null 2>&1; then
  runtime=$(docker info --format '{{.DefaultRuntime}}' 2>/dev/null || true)
  if [[ "$runtime" == "dk-runc" ]]; then
    pass "docker default runtime is dk-runc"
  else
    warn "docker default runtime is '$runtime' (expect dk-runc)"
  fi
else
  warn "docker not found"
fi

if [[ "$SMOKE_DOCKER_ENV" == "on" ]] && command -v docker >/dev/null 2>&1; then
  set +e
  out=$(docker run --rm ubuntu:22.04 bash -lc 'env | grep -E "^LD_PRELOAD=|^ENV_DATAKIT_SOCKET_ADDR="' 2>/dev/null)
  rc=$?
  set -e
  if [[ $rc -eq 0 ]] && echo "$out" | grep -q '^LD_PRELOAD='; then
    pass "docker env smoke passed (LD_PRELOAD injected)"
  else
    warn "docker env smoke not passed (maybe image pull/network/runtime issue)"
  fi
fi

if [[ "$SMOKE_HOST_JAVA" == "on" ]]; then
  if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
    tmpd=$(mktemp -d)
    cat > "$tmpd/Loop.java" <<'JAVA'
public class Loop {
  public static void main(String[] args) throws Exception {
    while (true) Thread.sleep(1000);
  }
}
JAVA
    javac "$tmpd/Loop.java"
    java -cp "$tmpd" Loop >/tmp/apm_loop_java.log 2>&1 &
    jpid=$!
    sleep 2
    cmdline=$(ps -o command= -p "$jpid" 2>/dev/null || true)
    if echo "$cmdline" | grep -q -- '-javaagent:.*/dd-java-agent.jar'; then
      pass "host java smoke passed (-javaagent observed)"
    else
      warn "host java smoke did not observe -javaagent in cmdline"
    fi
    kill "$jpid" >/dev/null 2>&1 || true
    rm -rf "$tmpd"
  else
    warn "javac/java not found, skip host java smoke"
  fi
fi

if [[ "$SMOKE_HOST_PYTHON" == "on" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; time.sleep(300)' >/tmp/apm_loop_py.log 2>&1 &
    ppid=$!
    sleep 2
    if [[ -f "/proc/$ppid/environ" ]]; then
      if tr '\0' '\n' < "/proc/$ppid/environ" | grep -Eq '^(DD_TRACE_AGENT_URL|DD_AGENT_HOST)='; then
        pass "host python smoke passed (DD_* env observed)"
      else
        warn "host python smoke did not observe DD_* env"
      fi
    else
      warn "/proc/$ppid/environ not readable, skip env check"
    fi
    kill "$ppid" >/dev/null 2>&1 || true
  else
    warn "python3 not found, skip host python smoke"
  fi
fi

echo "[DONE] verification complete"
