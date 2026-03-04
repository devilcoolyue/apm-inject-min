#!/bin/sh

set -e

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

target_arch=$1
if [ -z "$target_arch" ]; then
    target_arch=$(uname -m | sed -e s/x86_64/amd64/ -e s/aarch64.\*/arm64/)
fi

dist_rela_dir=dist/datakit-apm-inject-linux-$target_arch
if [ -n "$2" ]; then
    dist_rela_dir=$2
fi

make -f "$repo_dir/internal/apminject/Makefile" \
    dkrunc rewriter launcher launcher_musl \
    DIST_DIR="$repo_dir/$dist_rela_dir" \
    ARCH="$target_arch" REPO_PATH="$repo_dir"
