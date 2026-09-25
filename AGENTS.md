# AGENTS.md

监测 token plan 订阅余额的 macOS 菜单栏应用（SwiftUI + Swift Package）+ iOS 版（SwiftUI，XcodeGen）。
V1 数据源：DeepSeek / Z.AI Coding Plan / OpenCode Go（双端）+ ChatGPT（仅 macOS，读 Codex CLI OAuth）。

## 项目约定

- 与用户交流、文档、代码注释一律用中文；代码标识符保持英文。
- macOS 侧是 Swift Package 的 executable target，不建 xcodeproj、不用 XcodeGen/Tuist（iOS 侧例外，见下）。
- 最低 macOS 15。App 形态：菜单栏常驻（NSStatusItem 自绘环形进度图标，NSPopover 下拉面板）+ 独立 NSWindow 设置窗口管理 API key。
- 构建 / 测试：`swift build` / `swift test`；**开发运行用 `Scripts/run-dev.sh`**（构建后用固定开发证书签名再跑；直接 `swift run` 的 ad-hoc 签名每次都变，Keychain 会每次弹访问授权）；**打包安装用 `Scripts/package.sh`**（走 XcodeGen 工程 + 自动签名出 development profile，装到 /Applications，需 Xcode 已登录开发者账号）。
- **iOS 工程**：源是 `project.yml`，`xcodeproj` 是 XcodeGen 生成物（已 gitignore，勿手改勿提交）。构建用 `Scripts/build-ios.sh`，模拟器运行用 `Scripts/run-ios-sim.sh`。iOS target 通过 `includes/excludes` 直接编译 `Sources/TokenUsage` 里的共享文件（AppKit 壳四个文件被 exclude），**没有独立 Core 模块、零 public 样板**——新增共享代码放进 Sources/TokenUsage 即双端可用，新增 macOS 专属文件记得同步加进 excludes。小组件 target 只编入 `SnapshotStore.swift` / `Models.swift` / `Views/UsageRingView.swift`。
- iOS 数据源为三家（无 ChatGPT）：凭据来自 `~/.codex/auth.json`，iOS 上不存在，`AppModel.availableProviders` 已按平台过滤；iOS 的 ChatGPT 接入方案（完整 OAuth）留待后续版本。
- **小组件数据流**：app 每次刷新把快照 JSON 写入 App Group（`group.com.tokenusage.shared`，`SnapshotStore`），widget 只读快照，不碰网络与 key。
- **Mac → iOS 凭据导入（V1 主路径 = QR）**：Mac 设置页「导出到 iOS」生成二维码（`CredentialTransfer`，格式 `tokenusage-import:v1:<base64url>`），iOS「从 Mac 导入」扫码或粘贴。
- **Keychain 同步（方案 A 已打通，前提 = Xcode 自动签名）**：写 `kSecAttrSynchronizable=true` 条目要求进程带 `keychain-access-groups` entitlement **且**有匹配的 development profile——① CLI 签名（无 entitlement/profile）→ 同步写入 -34018、带 entitlement 无 profile 则启动即杀（exit 137），两者实测 2026-09；② profile 必须显式列出同名 keychain 组，`Mac Team Provisioning Profile: *` 通配组不满足（amfid -413 "No matching profile found"）。解法 = 在你的付费团队 portal 注册 Mac/iPhone 设备后，`package.sh` 走 Xcode 自动签名（entitlements 见 project.yml，团队通过 `DEVELOPMENT_TEAM` 环境变量注入）。另外 `kSecAttrSynchronizableAny` 的**删除**查询不匹配非同步条目，删除需按 true/false 各删一遍（KeychainStore 已处理）；CLI 工具查不到同步条目（无 entitlement），验证以 app 自身日志为准。
- 菜单栏用 `NSStatusItem` + `NSPopover`（AppKit），不要改回 `MenuBarExtra`：其 label 不支持「图标 + 文字」并排，组合时 SwiftUI 只取 Text、丢掉 Image。设置窗口也用 AppKit `NSWindow` 承载。
- SF Symbols 的 `gauge.with.needle.*percent` 在 macOS 上**不存在**（iOS only），`NSImage(systemSymbolName:)` 会静默返回 nil——菜单栏图标用 `ImageRenderer` 自绘圆环（`UsageRingView`），别再试这些 symbol 名。
- **图标**：`swift Scripts/make-icon.swift` 用 CoreGraphics 矢量重绘生成——macOS `Configs/Resources/AppIcon.icns`（squircle 渐变底 + 用量环 + 闪电）、iOS `Sources/TokenUsageiOS/Assets.xcassets`（1024 方图）。改设计就改脚本再重跑，别直接改 png/icns。
- API key 只存 Keychain：不得写入仓库、UserDefaults 明文或日志输出。

## V1 数据源（三个端点 2026-09 均已实测返回 200）

### DeepSeek（余额）

- `GET https://api.deepseek.com/user/balance`，头 `Authorization: Bearer <key>`
- 返回 `is_available` + `balance_infos[]`（`currency` / `total_balance` / `granted_balance` / `topped_up_balance`）
- 官方文档：api-docs.deepseek.com →「查询余额」

### Z.AI Coding Plan（额度百分比）

- `GET https://api.z.ai/api/monitor/usage/quota/limit`，头 Bearer + `User-Agent: opencode/1.18.31`（带此 UA 实测可用）
- 返回 `data.limits[]` 和 `data.level`（套餐档位，如 `pro`）；每条 limit 含 `type`（`TOKENS_LIMIT` / `TIME_LIMIT`）、`percentage`（已用百分比）、`nextResetTime`（毫秒时间戳）
- 多条 `TOKENS_LIMIT` 用 `unit` 区分窗口：**1=天、3=小时、5=月、6=周**（OpenClaw 源码 `provider-usage.fetch.zai.ts` 映射 1/3/5，Z.AI 官网确认计划为「5 小时 + 每周」双窗口，故 6=周）。实测 Pro 返回 5 小时窗（`unit=3,number=5`）与每周窗（`unit=6,number=1`）；OpenClaw 自己没映射 unit=6，界面上显示为 "Tokens (Limit)"
- `TIME_LIMIT` 是附加工具额度（search / web-reader / zread），月度重置，V1 可忽略（OpenClaw 把它标成 "Monthly"，别被误导）
- 判断多把 key 是否同账号：`GET https://api.z.ai/api/biz/subscription/list`，比对 `customerId`
- 死路：`/api/coding/paas/v4/quota` 返回 404，不要再试

### OpenCode Go（额度百分比）

- `GET https://opencode.ai/zen/go/v1/usage`，头 `Authorization: Bearer <key>`；**不需要** `x-opencode-session`（那是 chat 端点的要求）
- 返回三个窗口，`percent` 为已用百分比、`resetsAt` 为 ISO8601 重置时间：
  ```json
  {"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"2026-09-23T22:14:31.419Z"},
            "weekly":{"status":"ok","percent":15,"resetsAt":"2026-09-28T00:00:00.000Z"},
            "monthly":{"status":"ok","percent":18,"resetsAt":"2026-10-09T02:18:25.000Z"}}}
  ```
- 401 / 403 = key 过期或无权限；单个窗口 `percent` 越界（>100 或非有限数）应丢弃该窗口，不要 clamp 成 100%
- key 从 https://opencode.ai/auth 获取；本机开发凭据在 `~/.local/share/opencode/auth.json`（`opencode-go` / `zai-coding-plan` 条目，形如 `{type:"api", key}`），调试时可用，但不得打印或提交 key
- 参考实现：TokenBar（github.com/Nanako0129/TokenBar）的 `crates/tb_core_ffi/src/agent_opencode_go.rs`（移植自 mana.bar），含解码边界处理与响应测试样例

### ChatGPT（Plus / Pro 订阅，Codex CLI OAuth）

- 凭据：**不进 Keychain**，直接读 `~/.codex/auth.json` → `tokens.access_token` + `tokens.account_id`（Codex CLI 登录时写入，`auth_mode` 应为 `chatgpt`）
- `GET https://chatgpt.com/backend-api/wham/usage`，头 `Authorization: Bearer <token>`、`ChatGPT-Account-Id: <account_id>`、`originator: codex_cli_rs`、`Accept: application/json`（2026-09 实测 200）
- 返回 `rate_limit.primary_window`（5 小时，`limit_window_seconds=18000`）与 `secondary_window`（周，604800），各含 `used_percent`（已用百分比）+ `reset_at`（**Unix 秒**，注意与 Z.AI 的毫秒不同）；`plan_type`（如 `plus`）可当档位展示
- 已知限制：access token 过期返回 401，V1 不自动刷新（refresh token 轮换有写坏 auth.json 的风险），错误提示用户终端跑一次 `codex` 即可
- 参考实现：OpenClaw `src/infra/provider-usage.fetch.codex.ts`（github.com/openclaw/openclaw）
