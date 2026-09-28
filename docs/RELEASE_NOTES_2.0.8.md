# SnapAI 2.0.8

SnapAI 2.0.8 是**更新通道与自动化入口**版本:应用内更新从自研下载/替换迁到 Sparkle(appcast + EdDSA 签名 + 标准更新窗口),同时补上 App Intents 元数据 —— 此前 Shortcuts 里根本看不到 SnapAI,原因在构建而非本机设置。功能、配置、快捷键与历史记录完全兼容 2.0.x。

## 更新通道:Sparkle

- **通道**:`SUFeedURL` 指向 `releases/latest/download/appcast.xml`,`scripts/generate-appcast.sh` 在每次打包后生成 —— 官方 `sign_update` 签名、**立刻回验**、再比对 `Info.plist` 公钥与私钥派生公钥,三道都过才写入 `dist/appcast.xml`;preflight 再做结构校验(signature / length / url / version 与 zip 和 Info.plist 一致)。
- **完整性**:应用内更新由 Sparkle 校验 EdDSA 签名 + 新旧应用代码签名连续性。**自签名证书指纹固定,满足该要求 —— 不需要 Apple 公证**。`manifest` 与 `SBOM` 照常发布,供人工与供应链核对,不再参与安装流程。
- **UI**:改用 Sparkle 标准更新窗口(发布说明、下载进度、安装并重启),删除自研 `UpdateWindow`、下载器与替换脚本(约 880 行)。
- **行为不变**:自动检查保持关闭(`SUEnableAutomaticChecks=false`),仍由「检查更新…」手动触发。
- **升级路径**:2.0.7 及更早版本没有 Sparkle,仍走旧的 GitHub Releases 检查路径升到 2.0.8;此后才切换到 appcast 通道。

## App Intents:Shortcuts 能列出来并执行

- 根因:SwiftPM 构建**不执行** Xcode 的 App Intents 元数据提取阶段,包里没有 `Metadata.appintents`,Shortcuts 自然无从发现。
- 修复:`build.sh` 显式调用 `appintentsmetadataprocessor`,把元数据写进
  `Contents/Resources/Metadata.appintents/`(与第三方应用同位置),缺失即构建失败。
- 使用手册见 `docs/APP_INTENTS.md`(装到 /Applications、首次启动、如何搜索动作、列不出来怎么排)。

## 依赖政策:第一个第三方依赖

- `Sparkle` 经 SPM 引入,`Package.resolved` 按 `2.9.6` + revision 固定。
- 供应链扫描因此从「零依赖直接通过」变为**真实扫描**:`osv-scanner` 在本机与 CI 都安装,
  `Package.resolved` 纳入扫描范围。
- README 更新了依赖政策:新增依赖需先说明理由并接入扫描;其余功能仍全部一手框架。

## 工程

- **CI**:`actions/checkout` v4 → v7.0.1(node24 运行时),Node 20 弃用警告清零。
- **发版预检偶发栈溢出根因修复**:`App runtime smoke` 的 AX 遍历无界递归,在 AX 树出现环时
  吃到栈保护页并 SIGSEGV(同一线程连续 12 帧本进程代码可证)。改为显式栈迭代 + 深度/节点上限。
- **门禁**:无 ripgrep 环境退回 `grep -E`(195 条 pattern 逐条比对一致);新增 Sparkle 通道、
  App Intents 元数据、AX 有界遍历等条目。

## 兼容性

- 最低系统版本保持 **macOS 14**;Sparkle 2 支持 10.13+,无影响。
- 更新不改变签名身份:仍为自签名,首次安装需右键 → 打开;**不做 Apple notarization**(本机无私钥证书,决策见 `docs/RELEASE_PIPELINE.md`)。
- 提供 ZIP、签名 manifest、签名文件、SBOM 与 **appcast.xml** 五件资产。

## 已知事项

- Sparkle 标准窗口的样式由上游提供,未做定制;如需主题化需实现 `SPUUserDriver`(18 个方法),暂不铺开。
- 每个 Release 必须携带 `appcast.xml`,否则「检查更新」找不到通道(preflight 已加校验)。
- Shortcuts 列出与 VoiceOver/纯键盘 4 条人工走查需要在真机完成,见 `docs/APP_INTENTS.md` 与 `docs/ACCESSIBILITY_WALKTHROUGH.md`。
- 本轮无新增界面截图:更新窗口由 Sparkle 提供,需真实 feed 才能截取。
