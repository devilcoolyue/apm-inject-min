#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

TARGET_OS=""
TARGET_ARCH=""
VERSION=""
OUT_DIR=""
SKIP_LAUNCHER=0
INCLUDE_INJECTCTL=1
SKIP_JAVA_AGENT=0
JAVA_AGENT_URL="https://dtdg.co/latest-java-tracer"

usage() {
  cat <<'USAGE'
Usage:
  scripts/package.sh --os <linux|darwin> --arch <amd64|arm64> [options]

Options:
  --os <os>               Target OS: linux | darwin
  --arch <arch>           Target arch: amd64 | arm64 (x86_64/aarch64 accepted)
  --version <ver>         Package version (default: git short sha or timestamp)
  --out <dir>             Output dir for tar.gz (default: dist/packages)
  --skip-launcher         Skip building launcher shared libraries
  --skip-java-agent       Do not download and include dd-java-agent.jar
  --java-agent-url <url>  Override Java agent URL (default: https://dtdg.co/latest-java-tracer)
  --no-injectctl          Do not include injectctl in package
  -h, --help              Show this help

Examples:
  scripts/package.sh --os linux --arch arm64 --version demo-1
  scripts/package.sh --os linux --arch amd64 --skip-java-agent
  scripts/package.sh --os darwin --arch arm64 --skip-launcher
USAGE
}

normalize_arch() {
  case "$1" in
    amd64|x86_64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *)
      echo "unsupported arch: $1" >&2
      exit 1
      ;;
  esac
}

normalize_os() {
  case "$1" in
    linux|darwin) echo "$1" ;;
    *)
      echo "unsupported os: $1" >&2
      exit 1
      ;;
  esac
}

host_os() {
  case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    linux*) echo "linux" ;;
    darwin*) echo "darwin" ;;
    *) echo "unknown" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os)
      TARGET_OS=$(normalize_os "$2")
      shift 2
      ;;
    --arch)
      TARGET_ARCH=$(normalize_arch "$2")
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    --skip-launcher)
      SKIP_LAUNCHER=1
      shift
      ;;
    --skip-java-agent)
      SKIP_JAVA_AGENT=1
      shift
      ;;
    --java-agent-url)
      JAVA_AGENT_URL="$2"
      shift 2
      ;;
    --no-injectctl)
      INCLUDE_INJECTCTL=0
      shift
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

if [[ -z "$TARGET_OS" || -z "$TARGET_ARCH" ]]; then
  echo "--os and --arch are required" >&2
  usage
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VERSION=$(git -C "$ROOT_DIR" rev-parse --short HEAD)
  else
    VERSION=$(date +%Y%m%d%H%M%S)
  fi
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$ROOT_DIR/dist/packages"
fi

PKG_NAME="datakit-apm-inject-${TARGET_OS}-${TARGET_ARCH}-${VERSION}"
BUILD_DIR_REL="dist/build/${PKG_NAME}"
BUILD_DIR="$ROOT_DIR/${BUILD_DIR_REL}"
STAGE_DIR="$BUILD_DIR/stage"
HOST_OS=$(host_os)

echo "[INFO] target=${TARGET_OS}/${TARGET_ARCH} version=${VERSION}"
echo "[INFO] build dir: $BUILD_DIR"

echo "[INFO] cleaning old build dir"
rm -rf "$BUILD_DIR"
mkdir -p "$STAGE_DIR/apm_inject/inject" "$STAGE_DIR/apm_inject/lib/java" "$STAGE_DIR/apm_inject/bin"
mkdir -p "$OUT_DIR"

echo "[INFO] building rewriter"
CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" \
  go build -o "$STAGE_DIR/apm_inject/inject/rewriter" "$ROOT_DIR/internal/apminject/rewriter/rewriter.go"

echo "[INFO] building dkrunc"
CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" \
  go build -o "$STAGE_DIR/apm_inject/inject/dkrunc" "$ROOT_DIR/internal/apminject/dkrunc/dkrunc.go"

if [[ "$INCLUDE_INJECTCTL" -eq 1 ]]; then
  echo "[INFO] building injectctl"
  CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" \
    go build -o "$STAGE_DIR/apm_inject/bin/injectctl" "$ROOT_DIR/cmd/injectctl"
fi

build_linux_launcher_local() {
  local cc_bin="${CC:-gcc}"
  echo "[INFO] building linux launcher locally via ${cc_bin}"
  "$cc_bin" \
    -DDATAKIT_INJ_REWRITE_PROC='"/usr/local/datakit/apm_inject/inject/rewriter"' \
    "$ROOT_DIR/internal/apminject/apm_launcher.c" \
    -fPIC -shared -o "$STAGE_DIR/apm_inject/inject/apm_launcher.so"

  if command -v musl-gcc >/dev/null 2>&1; then
    echo "[INFO] building musl launcher locally via musl-gcc"
    musl-gcc \
      -DDATAKIT_INJ_REWRITE_PROC='"/usr/local/datakit/apm_inject/inject/rewriter"' \
      "$ROOT_DIR/internal/apminject/apm_launcher.c" \
      -fPIC -shared -o "$STAGE_DIR/apm_inject/inject/apm_launcher_musl.so"
  else
    echo "[WARN] musl-gcc not found, apm_launcher_musl.so is skipped"
  fi
}

build_linux_launcher_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] docker not found; cannot build linux launcher on non-linux host" >&2
    return 1
  fi

  echo "[INFO] building linux glibc launcher via docker (gcc:13)"
  docker run --rm \
    --platform "linux/${TARGET_ARCH}" \
    -v "$ROOT_DIR:/work" \
    -w /work \
    gcc:13 \
    bash -lc "gcc -DDATAKIT_INJ_REWRITE_PROC='\"/usr/local/datakit/apm_inject/inject/rewriter\"' internal/apminject/apm_launcher.c -fPIC -shared -o '${BUILD_DIR_REL}/stage/apm_inject/inject/apm_launcher.so'"

  echo "[INFO] building linux musl launcher via docker (alpine)"
  docker run --rm \
    --platform "linux/${TARGET_ARCH}" \
    -v "$ROOT_DIR:/work" \
    -w /work \
    alpine:3.19 \
    sh -lc "apk add --no-cache build-base musl-dev >/dev/null && gcc -DDATAKIT_INJ_REWRITE_PROC='\"/usr/local/datakit/apm_inject/inject/rewriter\"' internal/apminject/apm_launcher.c -fPIC -shared -o '${BUILD_DIR_REL}/stage/apm_inject/inject/apm_launcher_musl.so'"
}

build_darwin_launcher_local() {
  local cc_bin="${CC:-cc}"
  echo "[INFO] building darwin launcher via ${cc_bin}"
  "$cc_bin" \
    -DDATAKIT_INJ_REWRITE_PROC='"/usr/local/datakit/apm_inject/inject/rewriter"' \
    "$ROOT_DIR/internal/apminject/apm_launcher.c" \
    -dynamiclib -o "$STAGE_DIR/apm_inject/inject/apm_launcher.dylib"
}

if [[ "$SKIP_LAUNCHER" -eq 0 ]]; then
  if [[ "$TARGET_OS" == "linux" ]]; then
    if [[ "$HOST_OS" == "linux" ]]; then
      build_linux_launcher_local
      if [[ ! -f "$STAGE_DIR/apm_inject/inject/apm_launcher.so" ]]; then
        echo "[ERROR] failed to build apm_launcher.so" >&2
        exit 1
      fi
    else
      build_linux_launcher_docker
    fi
  elif [[ "$TARGET_OS" == "darwin" ]]; then
    if [[ "$HOST_OS" == "darwin" ]]; then
      build_darwin_launcher_local
    else
      echo "[WARN] skip darwin launcher: non-darwin host (${HOST_OS})"
    fi
  fi
else
  echo "[INFO] launcher build skipped by flag"
fi

if [[ "$SKIP_JAVA_AGENT" -eq 0 ]]; then
  echo "[INFO] downloading java agent: ${JAVA_AGENT_URL}"
  curl -fL --retry 3 --connect-timeout 10 \
    -o "$STAGE_DIR/apm_inject/lib/java/dd-java-agent.jar" \
    "$JAVA_AGENT_URL"
else
  echo "[INFO] java agent download skipped by flag"
fi

cat > "$STAGE_DIR/manifest.txt" <<MANIFEST
name=${PKG_NAME}
os=${TARGET_OS}
arch=${TARGET_ARCH}
version=${VERSION}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
host_os=${HOST_OS}
launcher_included=$(if [[ "$SKIP_LAUNCHER" -eq 0 ]]; then echo yes; else echo no; fi)
java_agent_included=$(if [[ "$SKIP_JAVA_AGENT" -eq 0 ]]; then echo yes; else echo no; fi)
MANIFEST

TAR_PATH="$OUT_DIR/${PKG_NAME}.tar.gz"

echo "[INFO] creating tar.gz"
tar -C "$STAGE_DIR" -czf "$TAR_PATH" .

echo "[OK] package created: $TAR_PATH"
ls -la "$STAGE_DIR"
