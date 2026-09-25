#!/bin/bash
# iOS 模拟器运行脚本：构建 → 安装 → 启动（默认 iPhone 16 Pro）。
# 截图：xcrun simctl io "iPhone 16 Pro" screenshot ~/Desktop/ios.png
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-iPhone 16 Pro}"

xcodegen generate
APP_DIR=$(xcodebuild -project TokenUsage.xcodeproj -scheme TokenUsageiOS \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null \
  | grep -m1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //')

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP_DIR/TokenUsageiOS.app"
xcrun simctl launch "$SIM" com.tokenusage.ios
echo "已在 $SIM 启动 TokenUsageiOS"
