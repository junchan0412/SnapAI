import SnapAILogic
import SwiftUI

struct PrivacySettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: AISettingsUI
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void
    @State private var pendingRestoreRedactionDefault = false

    private var enabledRulesCount: Int {
        settings.redactionRules.filter(\.isEnabled).count
    }

    var body: some View {
        SnapAISectionGroup("隐私与内容防护") {
            EmptyView()
        } content: {
            toggleRow(
                title: "发送前预览确认",
                description: "提交给云端或本地模型前，先弹窗核对完整提示词、脱敏结果与图片附件。",
                icon: "eye",
                tint: .blue,
                isOn: Binding(
                    get: { settings.privacyPreviewEnabled },
                    set: { settings.privacyPreviewEnabled = $0; commit() }
                )
            )

            SnapAIFormDivider()

            toggleRow(
                title: "自动识别图片文字 (本机 OCR)",
                description: "粘贴或截取图片后在本机识别文字，支持选择仅发送文字、原图或图文同发。",
                icon: "text.viewfinder",
                tint: .teal,
                isOn: Binding(
                    get: { settings.imageOCREnabled },
                    set: { settings.imageOCREnabled = $0; commit() }
                )
            )

            SnapAIFormDivider()

            toggleRow(
                title: "本地敏感词脱敏",
                description: "在请求发出前按本机正则规则自动隐去密钥、邮箱或自定义敏感字段。",
                icon: "hand.raised.fill",
                tint: .orange,
                isOn: Binding(
                    get: { settings.redactionEnabled },
                    set: { settings.redactionEnabled = $0; commit() }
                )
            )

            SnapAIFormDivider()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    ui.showRedactionRules.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Text("脱敏规则与样本测试")
                            .font(SnapAIUI.Typography.bodyText.weight(.medium))
                        SnapAIStatusPill(title: "已启用 \(enabledRulesCount)/\(settings.redactionRules.count) 条",
                                         systemImage: "shield",
                                         tint: settings.redactionEnabled ? SnapAIUI.StatusColor.success : .secondary,
                                         filled: settings.redactionEnabled)
                        Spacer()
                        Image(systemName: ui.showRedactionRules ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if ui.showRedactionRules {
                    SnapAIFormDivider(inset: 14)
                    redactionRulesEditor
                        .padding(14)
                }
            }
        }
        .snapAIConfirmDestructive(
            isPresented: $pendingRestoreRedactionDefault,
            title: "恢复默认脱敏规则",
            message: "将使用内置规则覆盖当前全部自定义规则，此操作不可撤销。"
        ) {
            settings.redactionRules = PrivacyRedactionRule.defaults()
            commit()
        }
    }

    private func toggleRow(title: String,
                           description: String,
                           icon: String,
                           tint: Color,
                           isOn: Binding<Bool>) -> some View {
        SnapAISettingRow(title: title, subtitle: description, icon: icon, iconTint: tint) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
    }

    private var redactionRulesEditor: some View {
        let preview = redactionPreview
        let patternError = newRedactionPatternError
        return VStack(alignment: .leading, spacing: 10) {
            if !settings.redactionEnabled {
                Label("当前「本地敏感词脱敏」开关处于关闭状态，开启后以下规则才会生效。",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(SnapAIUI.StatusColor.warning)
            }

            VStack(spacing: 6) {
                ForEach(settings.redactionRules) { rule in
                    redactionRuleRow(rule, preview: preview)
                }
            }

            newRuleRow

            if let patternError {
                Label(patternError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(SnapAIUI.StatusColor.error)
            }

            SnapAIFormDivider(inset: 0)
            redactionPreviewPanel(preview)
        }
    }

    private func redactionRuleRow(_ rule: PrivacyRedactionRule,
                                  preview: PrivacyRedactionPreview) -> some View {
        let report = preview.reports.first { $0.ruleID == rule.id }
        return HStack(spacing: 8) {
            Toggle("", isOn: bindingForRedactionRule(rule.id, \.isEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("启用规则 \(rule.name)")

            TextField("名称", text: bindingForRedactionRule(rule.id, \.name, policy: .deferredSave), onCommit: commit)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 96)
                .accessibilityLabel("规则名称")

            TextField("正则表达式", text: bindingForRedactionRule(rule.id, \.pattern, policy: .deferredSave), onCommit: commit)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .accessibilityLabel("正则表达式")

            TextField("替换为", text: bindingForRedactionRule(rule.id, \.replacement, policy: .deferredSave), onCommit: commit)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 90)
                .accessibilityLabel("替换为")

            if report?.isValid == false {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SnapAIUI.StatusColor.error)
                    .help(report?.statusText ?? "正则无效")
            }

            Button {
                settings.redactionRules.removeAll { $0.id == rule.id }
                commit()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("删除规则")
        }
    }

    private var newRuleRow: some View {
        HStack(spacing: 8) {
            TextField("新规则名", text: $ui.newRedactionName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 96)
                .accessibilityLabel("新规则名称")
            TextField("新增正则表达式…", text: $ui.newRedactionPattern)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .accessibilityLabel("新规则正则表达式")
            TextField("替换为", text: $ui.newRedactionReplacement)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 90)
                .accessibilityLabel("新规则替换为")
            Button {
                addRedactionRule()
            } label: {
                Label("添加", systemImage: "plus")
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
            .disabled(!canAddRedactionRule)

            Button("重置内置规则") {
                pendingRestoreRedactionDefault = true
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private func redactionPreviewPanel(_ preview: PrivacyRedactionPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("脱敏效果实时测试")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("命中 \(preview.totalMatches) 处")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 10) {
                TextEditor(text: $ui.redactionSample)
                    .accessibilityLabel("规则测试样本")
                    .font(.system(size: 11.5))
                    .frame(height: 68)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .snapAIGlassField(radius: 6)

                ScrollView {
                    Text(preview.output)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 68)
                .snapAIGlassField(radius: 6)
            }
        }
    }

    private var redactionPreview: PrivacyRedactionPreview {
        PrivacyFilter.preview(text: ui.redactionSample, rules: settings.redactionRules)
    }

    private var newRedactionPatternError: String? {
        let pattern = ui.newRedactionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        return PrivacyFilter.validatePattern(pattern)
    }

    private var canAddRedactionRule: Bool {
        let pattern = ui.newRedactionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return !pattern.isEmpty && newRedactionPatternError == nil
    }

    private func bindingForRedactionRule<V>(_ id: String,
                                            _ keyPath: WritableKeyPath<PrivacyRedactionRule, V>,
                                            policy: SettingsCommitPolicy = .fullReload) -> Binding<V> {
        Binding(
            get: {
                (settings.redactionRules.first(where: { $0.id == id })
                 ?? PrivacyRedactionRule(name: "", pattern: "", replacement: ""))[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = settings.redactionRules.firstIndex(where: { $0.id == id }) else { return }
                settings.redactionRules[idx][keyPath: keyPath] = newValue
                applyCommit(policy)
            }
        )
    }

    private func addRedactionRule() {
        let pattern = ui.newRedactionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty, PrivacyFilter.validatePattern(pattern) == nil else { return }
        let name = ui.newRedactionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = ui.newRedactionReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.redactionRules.append(PrivacyRedactionRule(
            name: name.isEmpty ? "自定义规则" : name,
            pattern: pattern,
            replacement: replacement.isEmpty ? "[已隐藏]" : replacement
        ))
        ui.newRedactionName = ""
        ui.newRedactionPattern = ""
        ui.newRedactionReplacement = "[已隐藏]"
        commit()
    }
}

struct ContextProfileSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: AISettingsUI
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    var body: some View {
        SnapAISectionGroup("背景上下文包") {
            EmptyView()
        } content: {
            SnapAISettingRow(
                title: "当前启用上下文包",
                subtitle: "将常用项目背景、术语表或个人写作偏好自动注入全局提示词。",
                icon: "doc.text.below.ecg",
                iconTint: .indigo
            ) {
                Picker("", selection: $settings.activeContextProfileID) {
                    Text("不使用上下文").tag("")
                    ForEach(settings.contextProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 168)
                .accessibilityLabel("当前使用的上下文包")
                .onChange(of: settings.activeContextProfileID) { commit() }
            }

            SnapAIFormDivider()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    ui.showContextProfiles.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text("管理上下文包列表")
                            .font(SnapAIUI.Typography.bodyText.weight(.medium))
                        SnapAIStatusPill(title: "共 \(settings.contextProfiles.count) 个",
                                         systemImage: "folder",
                                         tint: .secondary)
                        Spacer()
                        Image(systemName: ui.showContextProfiles ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if ui.showContextProfiles {
                    SnapAIFormDivider(inset: 14)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(settings.contextProfiles) { profile in
                            profileRow(profile)
                        }
                        addProfileRow
                    }
                    .padding(14)
                }
            }
        }
    }

    private func profileRow(_ profile: ContextProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: bindingForContextProfile(profile.id, \.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel("启用上下文包 \(profile.name)")

                TextField("名称", text: bindingForContextProfile(profile.id, \.name, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .accessibilityLabel("上下文包名称")

                if settings.activeContextProfileID == profile.id {
                    Text("当前生效")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }

                Button {
                    if settings.activeContextProfileID == profile.id {
                        settings.activeContextProfileID = ""
                    }
                    settings.contextProfiles.removeAll { $0.id == profile.id }
                    commit()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除上下文包")
            }

            TextEditor(text: bindingForContextProfile(profile.id, \.content, policy: .deferredSave))
                .accessibilityLabel("上下文包 \(profile.name) 的内容")
                .font(.system(size: 12))
                .frame(height: 62)
                .scrollContentBackground(.hidden)
                .padding(6)
                .snapAIGlassField(radius: 6)
        }
        .padding(8)
        .background(SnapAIUI.Surface.quiet,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var addProfileRow: some View {
        HStack(spacing: 8) {
            TextField("输入新上下文包名称…", text: $ui.newContextName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .accessibilityLabel("新上下文包名称")
                .onSubmit { addContextProfile() }
            Button {
                addContextProfile()
            } label: {
                Label("新建", systemImage: "plus")
            }
            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
            .disabled(ui.newContextName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func bindingForContextProfile<V>(_ id: String,
                                             _ keyPath: WritableKeyPath<ContextProfile, V>,
                                             policy: SettingsCommitPolicy = .fullReload) -> Binding<V> {
        Binding(
            get: {
                (settings.contextProfiles.first(where: { $0.id == id })
                 ?? ContextProfile(name: "", content: ""))[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = settings.contextProfiles.firstIndex(where: { $0.id == id }) else { return }
                settings.contextProfiles[idx][keyPath: keyPath] = newValue
                applyCommit(policy)
            }
        )
    }

    private func addContextProfile() {
        let name = ui.newContextName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let profile = ContextProfile(name: name, content: "")
        settings.contextProfiles.append(profile)
        settings.activeContextProfileID = profile.id
        ui.newContextName = ""
        commit()
    }
}
