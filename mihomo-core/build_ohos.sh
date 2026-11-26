#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OHOS_NDK="${OHOS_NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
LLVM_BIN="$OHOS_NDK/llvm/bin"
SYSROOT="$OHOS_NDK/sysroot"

OUT_LIB_DIR="$ROOT_DIR/entry/libs/arm64-v8a"
OUT_INC_DIR="$ROOT_DIR/entry/src/main/cpp/include"
mkdir -p "$OUT_LIB_DIR" "$OUT_INC_DIR"

# Wrapper clang script for HarmonyOS aarch64-linux-ohos
# Filter out Android-only -llog / -landroid since HarmonyOS uses musl libc
# and our ohos_compat.c provides __android_log_* stubs.
CC_WRAPPER="$SCRIPT_DIR/.ohos-arm64-clang.sh"
cat > "$CC_WRAPPER" <<EOF
#!/usr/bin/env bash
args=()
for arg in "\$@"; do
  if [[ "\$arg" == "-llog" || "\$arg" == "-landroid" ]]; then
    continue
  fi
  args+=("\$arg")
done
exec "$LLVM_BIN/clang" --target=aarch64-linux-ohos --sysroot="$SYSROOT" -I"$SCRIPT_DIR/ohos_inc" -D__MUSL__ "\${args[@]}"
EOF
chmod +x "$CC_WRAPPER"

cd "$SCRIPT_DIR"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
go mod tidy

# Use GOOS=android with HarmonyOS NDK clang:
# 1. Go's GOOS=android uses POSIX pthread_key TLS (zero ELF PT_TLS / R_AARCH64_TLS_TPREL64),
#    which HarmonyOS musl dlopen() requires ("initial-exec TLS resolves to dynamic definition").
# 2. Mihomo/sing-tun uses mobile TUN fd mode (cmfa) without Linux root/netlink calls.
echo "Building libmihomo.so for HarmonyOS arm64-v8a (aarch64-linux-ohos, no initial-exec TLS)..."
CGO_ENABLED=1 \
GOOS=android \
GOARCH=arm64 \
CC="$CC_WRAPPER" \
CGO_CFLAGS="-O2 -fPIC" \
CGO_LDFLAGS="-Wl,-soname,libmihomo.so" \
go build -v \
  -buildmode=c-shared \
  -tags="with_gvisor,cmfa,netgo" \
  -ldflags="-w -s" \
  -o "$OUT_LIB_DIR/libmihomo.so" \
  .

mv "$OUT_LIB_DIR/libmihomo.h" "$OUT_INC_DIR/libmihomo.h"
rm -f "$CC_WRAPPER"

echo "=== Built successfully ==="
ls -lh "$OUT_LIB_DIR/libmihomo.so" "$OUT_INC_DIR/libmihomo.h"
echo "=== Dynamic deps (must only be libc.so) ==="
"$LLVM_BIN/llvm-readelf" -d "$OUT_LIB_DIR/libmihomo.so" | grep -E "NEEDED|SONAME"
echo "=== TLS relocations (must be EMPTY) ==="
"$LLVM_BIN/llvm-readelf" -l -r "$OUT_LIB_DIR/libmihomo.so" | grep -i tls || echo "OK: ZERO TLS segments/relocations!"
