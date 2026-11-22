#!/bin/bash
# 一键构建 → 签名 → 安装 → 启动（模拟器）
# 用法: bash native/scripts/deploy.sh [--start]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEVECO="C:/Program Files/Huawei/DevEco Studio"
SDK="$DEVECO/sdk"
SDKLIB="$SDK/default/openharmony/toolchains/lib"
HDC="$SDK/default/openharmony/toolchains/hdc.exe"
# 锁定模拟器目标，避免误装到 USB 真机（如需真机部署，临时改这里）
HDC_TARGET="127.0.0.1:5557"
HDC="$HDC -t $HDC_TARGET"
SIGN_DIR="$ROOT/.tmp/sign"
UNSIGNED="$ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap"
SIGNED="$SIGN_DIR/goout-signed.hap"
SIGNED_WIN="C:\\Users\\fengq\\DevProjects\\GoOut\\.tmp\\sign\\goout-signed.hap"

export DEVECO_SDK_HOME="C:\\Program Files\\Huawei\\DevEco Studio\\sdk"
# 注意：PATH 必须用 /c/ MSYS 形式，否则 node 继承的 Windows PATH 会被转换错误
export PATH="/c/Program Files/Huawei/DevEco Studio/tools/node:/c/Program Files/Huawei/DevEco Studio/jbr/bin:$PATH"

echo "==> hvigor assembleHap"
node "$DEVECO/tools/hvigor/bin/hvigorw.js" --mode module -p product=default assembleHap --analyze=false --no-daemon > "$ROOT/.tmp/hvigor-build.log" 2>&1 || {
  tail -40 "$ROOT/.tmp/hvigor-build.log"; exit 1;
}
tail -3 "$ROOT/.tmp/hvigor-build.log"

echo "==> sign hap"
java -jar "$SDKLIB/hap-sign-tool.jar" sign-app \
  -mode "localSign" \
  -keyAlias "openharmony application release" -keyPwd "123456" \
  -appCertFile "$SIGN_DIR/app-chain.cer" \
  -profileFile "$SIGN_DIR/goout-profile.p7b" \
  -inFile "$UNSIGNED" -outFile "$SIGNED" \
  -signAlg "SHA256withECDSA" \
  -keystoreFile "$SIGN_DIR/OpenHarmony.p12" -keystorePwd "123456" \
  -compatibleVersion "12" 2>&1 | grep -E "success|ERROR"

echo "==> hdc install"
"$HDC" install "$SIGNED_WIN" 2>&1 | grep -iE "success|fail|error"

if [ "${1:-}" = "--start" ]; then
  echo "==> start app"
  "$HDC" shell "aa start -a EntryAbility -b com.fql.goout" 2>&1
fi
echo "DEPLOY OK"
