# SnapAI 发布链路

发版分两段:云端只读预检 + 本机签名发布。任何涉及私钥、签名身份、
tag 写入、GitHub Release 上传的步骤都不进 CI。

## 云端:只读预检(手动触发)

Actions → CI → Run workflow。跑 `readonly-preflight` job,覆盖本机
`scripts/preflight-release.sh` 的可移植前缀:

- **空白检查**:`scripts/ci-whitespace-check.sh <base>`,对 `base..HEAD` 的
  推送/PR 范围跑 `git diff --check`。工作区永远干净,直接跑 `git diff --check`
  恒为空,所以这里必须显式传基线提交(checkout 用 `fetch-depth: 0`);
- **版本一致性**:`Resources/Info.plist` 的 `CFBundleShortVersionString` 与
  `CFBundleVersion` 相同且格式合法 —— 与本机 `validate_release_version` 同口径;
- LICENSE 引用检查、`run-audit-remediation-check.sh`、`check-logic-symlinks.sh`
- `run-supply-chain-scan.sh`(零第三方依赖时直接通过)
- `run-logic-tests.sh`、`run-streaming-runtime-tests.sh`、
  `run-app-runtime-tests.sh`、`run-macos-smoke-tests.sh --skip-logic`
- `swift build` + `./build.sh --debug`(含 Sparkle 框架嵌入与 App Intents 元数据提取)
  + 无签名 bundle 启动 smoke

CI runner 没有稳定签名身份,因此只做 debug 构建验证可启动性,不做
release 签名构建、不打包、不生成 SBOM、不写 tag、不创建 Release。
checkout action 已 pin 到不可变 commit SHA(审计门禁锁定)。

### 只留在本机的只读工具

这些不需要私钥,但 runner 没有对应权限或屏幕,不进 Actions:

- `scripts/ax-audit.sh` —— 无障碍名称走查,需要辅助功能权限
  (见 `docs/ACCESSIBILITY_WALKTHROUGH.md`);
- `scripts/screenshots-all.sh` —— release notes 截图,需要屏幕录制权限;
- `scripts/measure-startup.sh`、`scripts/profile-settings-sections.sh` ——
  性能基线,必须在同一台机器上前后对比才有意义
  (见 `docs/STARTUP_BASELINE.md`、`docs/RUNTIME_MEMORY_BASELINE.md`)。

## 更新通道:Sparkle

2.0.8 起应用内更新改走 Sparkle(appcast + EdDSA 签名),不再自研下载与替换流程。

- **feed**:`SUFeedURL` = `https://github.com/junchan0412/SnapAI/releases/latest/download/appcast.xml`
  (所以**每个 Release 都必须带 `appcast.xml`**,否则「检查更新」会找不到通道);
- **公钥**:`SUPublicEDKey` 在 `Resources/Info.plist`;私钥在
  `~/.snapai/sparkle/ed25519-private.key`(base64 的 Ed25519 种子),
  同名 `.pem` 是用来派生公钥做一致性校验的,权限 600,不进仓库;
- **签名工具**:`scripts/fetch-sparkle-tools.sh` 取官方 `sign_update`(按 SHA-256 固定),
  装到 `~/.snapai/sparkle-tools/bin/`;
- **生成与回验**:`scripts/generate-appcast.sh <version>` 在
  `package-release.sh` 打包后自动执行:签名 → 用官方工具回验 → 比对 Info.plist
  公钥与私钥派生公钥 → 写 `dist/appcast.xml`;preflight 再做结构校验
  (signature/length/url/version 与 zip、Info.plist 一致);
- **完整性模型**:应用内更新由 Sparkle 负责 EdDSA 校验 + 新旧应用代码签名连续性
  (自签名证书指纹固定,满足该要求);`manifest` + `SBOM` 照常发布,供人工与
  供应链核对,不再参与应用内安装流程。

发布顺序因此多一步:`gh release create` 的资产里要带上 `dist/appcast.xml`。

### 发版后必须手工点一次更新检查

feed、签名、下载、版本号都能自动化校验,但**窗口有没有弹出来**只有人眼能确认
(本机锁屏时无法截图,已实测踩过)。发 2.0.8 这类通道变更后的第一次发版:

1. 解压安装新版本,启动后点状态栏菜单「检查更新…」;
2. 预期:弹出 Sparkle 标准窗口 —— 本地已是最新时显示「已是最新版本」,
   有新版本时显示发布说明 + 下载进度 + 安装并重启;
3. 旁证(无需截图):`defaults read com.snapai.app SULastCheckTime` 会在点击后更新,
   说明 updater 确实执行了检查。

## 已知决策(明确记录,避免反复)

- **不做 Apple notarization,继续自签名分发**:本机只有自签名身份
  `SnapAI Local Signing`(证书指纹 `547f9e9c…`),没有付费开发者账号。
  影响:首次安装需右键 → 打开(README 已写)。Sparkle 的更新安装不要求公证,
  只要求**新旧应用签名一致**,自签名满足。
  若将来申请到 Developer ID,需要:新证书签名 → `Resources/Info.plist` 公钥不变
  (Sparkle EdDSA 与代码签名是两套)→ 首次公证后按 Apple 流程重新分发。
- **不补发 v2.0.4 的 Release**:tag 已存在但没有 Release 资产,更新检查走
  `releases/latest`,用户从 2.0.3 会直接跳到最新版 —— 按决定保持现状,不再回填。

## 本机:签名发布(唯一写入口)

```bash
# 1. 云端先绿:Actions 手动触发 CI,通过后再继续
# 2. 本机全量预检(含签名/打包/可安装性验证)
export SNAPAI_MANIFEST_PRIVATE_KEY="$HOME/.snapai/snapai-manifest-private.pem"
scripts/preflight-release.sh
# 3. 提交 + tag + 推送
git commit && git tag -a vX.Y.Z -m "SnapAI X.Y.Z:..." && git push origin main vX.Y.Z
# 4. GitHub Release(附 zip / manifest / 签名 / SBOM)
gh release create vX.Y.Z dist/SnapAI-vX.Y.Z.zip \
  dist/snapai-manifest-vX.Y.Z.json dist/snapai-manifest-vX.Y.Z.json.sig \
  dist/snapai-sbom-vX.Y.Z.json --title "SnapAI X.Y.Z" --notes-file docs/RELEASE_NOTES_X.Y.Z.md
```

私钥(`~/.snapai/snapai-manifest-private.pem`)与本地签名身份
("SnapAI Local Signing",见 `scripts/create-local-signing-identity.sh`)
只存在于发布者的本机 keychain,绝不进仓库、不进 CI secrets —— 这是
"换电脑就不会发版"风险的来源,也是有意为之的安全边界:丢私钥的影响
半径被限制在一台机器。换电脑发版的正确流程是重新生成身份与密钥对,
并用新公钥替换 `Resources/ManifestPublicKey.pem`(需走一次正常发版)。
