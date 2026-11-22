#!/bin/bash
# Build libgoout.so (Go cgo bridge) for HarmonyOS (OHOS) targets.
# Usage: ./build-go-so.sh [x86_64|aarch64|all]
#
# Toolchain trick: clang derives its default target from argv[0] name
# (<triple>-clang.exe), config files next to the exe provide sysroot.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT_WIN="$(cygpath -w "$ROOT" | sed 's/\\/\\\\/g')"
SDK="${OHOS_SDK:-C:/Program Files/Huawei/DevEco Studio/sdk}"
LLVM_BIN="$SDK/default/openharmony/native/llvm/bin"
SYSROOT="$SDK/default/openharmony/native/sysroot"
RES_DIR="$SDK/default/openharmony/native/llvm/lib/clang/15.0.4"
GO_ROOT="$ROOT/.tmp/go127/go"
TC_ROOT="$ROOT/.tmp/toolchain"
OUT_DIR="$ROOT/entry/src/main/cpp/third_party/goout/prebuilt"
LIBS_DIR="$ROOT/entry/libs"

export GOROOT="$GO_ROOT"
export PATH="$GO_ROOT/bin:$PATH"
export GOPATH="$ROOT/.tmp/gopath"
export GOCACHE="$ROOT/.tmp/gocache"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

setup_toolchain() {
  local arch="$1" triple goarch unwind_lib ohos_abi
  if [ "$arch" = "x86_64" ]; then
    triple=x86_64-unknown-linux-ohos; goarch=amd64; unwind_lib="$SDK/default/openharmony/native/llvm/lib/x86_64-linux-ohos"
  else
    triple=aarch64-unknown-linux-ohos; goarch=arm64; unwind_lib="$SDK/default/openharmony/native/llvm/lib/aarch64-linux-ohos"
  fi
  local tc="$TC_ROOT/$arch"
  if [ ! -f "$tc/$triple-clang.exe" ]; then
    mkdir -p "$tc"
    cp "$LLVM_BIN/clang.exe" "$tc/$triple-clang.exe"
    cp "$LLVM_BIN/clang++.exe" "$tc/$triple-clang++.exe"
    cp "$LLVM_BIN/ld.lld.exe" "$LLVM_BIN/lld.exe" "$tc/" 2>/dev/null || true
    cp "$LLVM_BIN"/liblzma.dll "$LLVM_BIN"/libxml2.dll "$LLVM_BIN"/libpython3.12.dll "$tc/" 2>/dev/null || true
    for f in "$tc/$triple-clang.cfg" "$tc/$triple-clang++.cfg"; do
      cat > "$f" <<EOF
--sysroot="$SYSROOT"
-resource-dir="$RES_DIR"
-L"$unwind_lib"
EOF
    done
  fi
  echo "$triple $goarch"
}

build_one() {
  local arch="$1" ohos_abi
  if [ "$arch" = "aarch64" ]; then ohos_abi=arm64-v8a; else ohos_abi="$arch"; fi
  read -r triple goarch <<< "$(setup_toolchain "$arch")"
  local tc="$TC_ROOT/$arch"
  local cc="$tc/$triple-clang.exe"
  local cxx="$tc/$triple-clang++.exe"
  local out="$OUT_DIR/$ohos_abi"
  mkdir -p "$out"
  echo "==> building libgoout.so for $ohos_abi (GOARCH=$goarch)"
  (cd "$ROOT/native/gooutbridge" && \
    CGO_ENABLED=1 GOOS=android GOARCH="$goarch" \
    CC="$cc" CXX="$cxx" \
    CGO_CFLAGS="-I$ROOT_WIN\\native\\gooutbridge\\fakeinclude" \
    CGO_LDFLAGS="-L$ROOT_WIN\\native\\gooutbridge\\fakelib\\$arch -llog -Wl,-soname,libgoout.so" \
    CGO_LDFLAGS_ALLOW="-Wl,-soname,.*" \
    go build -trimpath -ldflags "-s -w" -buildmode=c-shared -o "$out/libgoout.so" .)
  cp "$ROOT/native/gooutbridge/fakelib/$arch/liblog.so" "$out/" 2>/dev/null || true
  # strip（幂等，Go -s -w 后通常无额外符号）
  "$LLVM_BIN/llvm-strip.exe" --strip-unneeded "$out/libgoout.so" -o "$out/libgoout.so" 2>/dev/null || true
  # hvigor 只打包 entry/libs/<abi>/ 下的 .so
  mkdir -p "$LIBS_DIR/$ohos_abi"
  cp "$out/libgoout.so" "$out/liblog.so" "$LIBS_DIR/$ohos_abi/"
  ls -la "$out" "$LIBS_DIR/$ohos_abi"
}

# ensure android log stub exists per arch
build_stub() {
  local arch="$1"
  read -r triple goarch <<< "$(setup_toolchain "$arch")"
  local tc="$TC_ROOT/$arch"
  mkdir -p "$ROOT/native/gooutbridge/fakelib/$arch"
  "$tc/$triple-clang.exe" -fPIC -shared -Wl,-soname,liblog.so \
    -I"$ROOT/native/gooutbridge/fakeinclude" \
    "$ROOT/native/gooutbridge/log_stub.c" \
    -o "$ROOT/native/gooutbridge/fakelib/$arch/liblog.so"
}

ARCHES="${1:-x86_64}"
[ "$ARCHES" = "all" ] && ARCHES="x86_64 aarch64"
for a in $ARCHES; do
  build_stub "$a"
  build_one "$a"
done
echo "DONE"
