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
- `swift build` + `./build.sh --debug` + 无签名 bundle 启动 smoke

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
