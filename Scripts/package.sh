#!/bin/bash
# Mac 正式版打包：走 Xcode 工程（XcodeGen）自动签名，带 keychain-access-groups
# entitlement + development provisioning profile → keychain 条目可随 iCloud 钥匙串
# 同步到 iPhone（方案 A）。装到 /Applications。
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project TokenUsage.xcodeproj -scheme TokenUsageMac \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/xcode -allowProvisioningUpdates build | tail -3

APP=".build/xcode/Build/Products/Release/TokenUsage.app"
test -d "$APP"

rm -rf /Applications/TokenUsage.app
if cp -R "$APP" /Applications/ 2>/dev/null; then
    echo "已安装：/Applications/TokenUsage.app（profile 签名，Keychain 可 iCloud 同步）"
    echo "启动：open /Applications/TokenUsage.app"
else
    echo "写入 /Applications 失败，请用 sudo 重新运行本脚本" >&2
    exit 1
fi
