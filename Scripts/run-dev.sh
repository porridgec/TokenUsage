#!/bin/bash
# 开发运行脚本：构建 → 用固定的开发证书签名 → 运行。
#
# 为什么不直接 swift run：SPM 产物是 ad-hoc 签名，cdHash 每次构建都不同，
# Keychain 会把每个新二进制当成陌生 app，每次运行都弹访问授权；
# 用固定的 Apple Development 证书重签后，第一次弹窗点「始终允许」即可永久记住。
set -euo pipefail
cd "$(dirname "$0")/.."

# 签名身份经环境变量注入；缺省用 ad-hoc（本机可用，但每次构建后 Keychain 会重新弹授权）
IDENTITY="${TOKENUSAGE_SIGN_IDENTITY:--}"
BIN=".build/arm64-apple-macosx/debug/TokenUsage"

swift build
# 注意：不要在此加 keychain-access-groups entitlement——无 provisioning profile 时
# macOS 会在启动时被 AMFI 杀掉（exit 137，实测）。跨设备同步靠条目本身的
# kSecAttrSynchronizable（见 KeychainStore 注释），无需 Mac 侧 entitlement。
codesign --force --sign "$IDENTITY" --identifier com.tokenusage.dev "$BIN"
exec "$BIN"
