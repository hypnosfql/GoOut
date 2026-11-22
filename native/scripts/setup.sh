#!/bin/bash
# GoOut 二次开发环境准备脚本
# 职责：下载 Go 工具链 → 应用 OHOS 移植补丁 → 下载 Go 依赖 → （可选）编译内核
# 用法:
#   bash native/scripts/setup.sh            # 准备环境（不编译）
#   bash native/scripts/setup.sh --build    # 准备环境并编译全部 ABI 内核
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GO_VERSION="1.27.4"
GO_DIR="$ROOT/.tmp/go127"
GO_ZIP="$ROOT/.tmp/go.zip"
BRIDGE_DIR="$ROOT/native/gooutbridge"

log() { echo "[setup] $*"; }

# ---------------------------------------------------------------
# 1. 下载 Go 工具链（Windows x86_64 主机，交叉编译目标为 OHOS arm64/x86_64）
# ---------------------------------------------------------------
if [ -f "$GO_DIR/go/bin/go.exe" ]; then
  log "Go toolchain exists: $("$GO_DIR/go/bin/go.exe" version)"
else
  log "downloading go$GO_VERSION (windows/amd64)..."
  mkdir -p "$ROOT/.tmp"
  curl -fSL -o "$GO_ZIP" "https://go.dev/dl/go${GO_VERSION}.windows-amd64.zip" --connect-timeout 20
  log "extracting..."
  rm -rf "$GO_DIR"
  mkdir -p "$GO_DIR"
  unzip -q "$GO_ZIP" -d "$GO_DIR"
  rm -f "$GO_ZIP"
  log "Go installed: $("$GO_DIR/go/bin/go.exe" version)"
fi

export GOROOT="$(cygpath -w "$GO_DIR/go")"
export PATH="$GO_DIR/go/bin:$PATH"
export GOPATH="$(cygpath -w "$ROOT/.tmp/gopath")"
export GOCACHE="$(cygpath -w "$ROOT/.tmp/gocache")"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

# ---------------------------------------------------------------
# 2. 应用 OHOS 移植补丁（幂等）
#    Go 官方不支持 openharmony 目标，需以 GOOS=android 交叉编译，
#    以下两处源码问题必须修补：
#    1) net/cgo_resold.go: musl 的 getnameinfo 第三参数要求 socklen_t（bionic 接受 size_t）
#    2) net/interface.go: 放行 zoneCache 的 linkname 引用（anet 库需要）
# ---------------------------------------------------------------
NET_SRC="$GO_DIR/go/src/net"

log "applying OHOS patches to Go stdlib..."

# patch 1: getnameinfo socklen_t
if grep -q "C.socklen_t(len(b))" "$NET_SRC/cgo_resold.go"; then
  log "  patch1 (cgo_resold.go socklen_t) already applied"
else
  sed -i 's/C\.size_t(len(b))/C.socklen_t(len(b))/' "$NET_SRC/cgo_resold.go"
  grep -q "C.socklen_t(len(b))" "$NET_SRC/cgo_resold.go" \
    && log "  patch1 applied" \
    || { log "  ERROR: patch1 failed"; exit 1; }
fi

# patch 2: zoneCache linkname 放行
if grep -q "^//go:linkname zoneCache" "$NET_SRC/interface.go"; then
  log "  patch2 (interface.go linkname) already applied"
else
  sed -i 's|^var zoneCache = ipv6ZoneCache{|//go:linkname zoneCache\nvar zoneCache = ipv6ZoneCache{|' "$NET_SRC/interface.go"
  grep -q "^//go:linkname zoneCache" "$NET_SRC/interface.go" \
    && log "  patch2 applied" \
    || { log "  ERROR: patch2 failed"; exit 1; }
fi

# ---------------------------------------------------------------
# 3. 下载 Go 依赖（libXray + xray-core）
# ---------------------------------------------------------------
log "resolving go modules (libXray/xray-core, first run may take minutes)..."
(cd "$BRIDGE_DIR" && go mod download 2>&1 | tail -3)

# ---------------------------------------------------------------
# 4. 可选：编译内核
# ---------------------------------------------------------------
if [ "${1:-}" = "--build" ]; then
  log "building kernel for all ABIs..."
  bash "$ROOT/native/scripts/build-go-so.sh" all
  log "kernel build done"
else
  log "env ready. build kernel with:"
  log "  bash native/scripts/build-go-so.sh x86_64   # 模拟器"
  log "  bash native/scripts/build-go-so.sh aarch64   # 真机"
  log "  bash native/scripts/build-go-so.sh all       # 全部 ABI"
fi
log "DONE"
