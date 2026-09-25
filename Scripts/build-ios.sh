#!/bin/bash
# iOS 构建脚本：XcodeGen 生成工程 + xcodebuild 编译（模拟器目标）。
# xcodeproj 是生成物（已 gitignore），源是 project.yml。
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project TokenUsage.xcodeproj -scheme TokenUsageiOS \
  -destination 'generic/platform=iOS Simulator' build | tail -5
