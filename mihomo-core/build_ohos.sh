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
CC_WRAPPER="$SCRIPT_DIR/.ohos-arm64-clang.sh"
cat > "$CC_WRAPPER" <<EOF
#!/usr/bin/env bash
exec "$LLVM_BIN/clang" --target=aarch64-linux-ohos --sysroot="$SYSROOT" -D__MUSL__ "\$@"
EOF
chmod +x "$CC_WRAPPER"

cd "$SCRIPT_DIR"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
go mod tidy

echo "Building libmihomo.so for HarmonyOS arm64-v8a (aarch64-linux-ohos)..."
CGO_ENABLED=1 \
GOOS=linux \
GOARCH=arm64 \
CC="$CC_WRAPPER" \
CGO_CFLAGS="-O2 -fPIC" \
CGO_LDFLAGS="-Wl,-soname,libmihomo.so" \
go build -v \
  -buildmode=c-shared \
  -tags="with_gvisor,cmfa" \
  -ldflags="-w -s" \
  -o "$OUT_LIB_DIR/libmihomo.so" \
  .

mv "$OUT_LIB_DIR/libmihomo.h" "$OUT_INC_DIR/libmihomo.h"
rm -f "$CC_WRAPPER"

echo "Built successfully:"
ls -lh "$OUT_LIB_DIR/libmihomo.so" "$OUT_INC_DIR/libmihomo.h"
"$LLVM_BIN/llvm-readelf" -d "$OUT_LIB_DIR/libmihomo.so" | grep -E "NEEDED|SONAME"
