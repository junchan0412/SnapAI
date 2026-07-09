import SwiftUI

struct PrivacySettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: AISettingsUI
    let commit: () -> Void
    let applyCommit: (SettingsCommitPolicy) -> Void

    var body: some View {
        section("隐私") {
            toggleRow(
                title: "发送前预览",
                description: "发送前查看最终 Prompt、脱敏命中和附件摘要。",
                isOn: Binding(
                    get: { settings.privacyPreviewEnabled },
                    set: { settings.privacyPreviewEnabled = $0; commit() }
                )
            )
            compactDivider
            toggleRow(
                title: "本地脱敏",
                description: "在请求发出前替换匹配文本，规则只在本机执行。",
                isOn: Binding(
                    get: { settings.redactionEnabled },
                    set: { settings.redactionEnabled = $0; commit() }
                )
            )
            if settings.redactionEnabled {
                compactDivider
                redactionRulesEditor
            }
        }
    }

    private var redactionRulesEditor: some View {
        let preview = redactionPreview
        let patternError = newRedactionPatternError
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(settings.redactionRules) { rule in
                redactionRuleRow(rule, preview: preview)
            }
            newRuleRow
            if let patternError {
                Label(patternError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Divider().padding(.vertical, 2)
            redactionPreviewPanel(preview)
        }
        .font(.caption)
        .padding(8)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func redactionRuleRow(_ rule: PrivacyRedactionRule,
                                  preview: PrivacyRedactionPreview) -> some View {
        let report = preview.reports.first { $0.ruleID == rule.id }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Toggle("", isOn: bindingForRedactionRule(rule.id, \.isEnabled))
                    .labelsHidden()
                TextField("名称", text: bindingForRedactionRule(rule.id, \.name, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 82)
                TextField("正则表达式", text: bindingForRedactionRule(rule.id, \.pattern, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
                TextField("替换为", text: bindingForRedactionRule(rule.id, \.replacement, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 86)
                Button {
                    settings.redactionRules.removeAll { $0.id == rule.id }
                    commit()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("删除规则")
            }
            Label(report?.statusText ?? "未检测",
                  systemImage: report?.isValid == false ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(report?.isValid == false ? Color.red : Color.secondary)
        }
        .padding(6)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var newRuleRow: some View {
        HStack(spacing: 6) {
            TextField("名称", text: $ui.newRedactionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 82)
            TextField("正则表达式", text: $ui.newRedactionPattern)
                .textFieldStyle(.roundedBorder)
            TextField("替换为", text: $ui.newRedactionReplacement)
                .textFieldStyle(.roundedBorder)
                .frame(width: 86)
            Button {
                addRedactionRule()
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!canAddRedactionRule)
            Button("恢复默认") {
                settings.redactionRules = PrivacyRedactionRule.defaults()
                commit()
            }
            .font(.caption)
        }
    }

    private func redactionPreviewPanel(_ preview: PrivacyRedactionPreview) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("规则测试").font(.caption.weight(.semibold))
                Spacer()
                Text("命中 \(preview.totalMatches) 处 · 错误 \(preview.invalidReports.count) 条")
                    .font(.caption2)
                    .foregroundStyle(preview.invalidReports.isEmpty ? Color.secondary : Color.red)
            }
            TextEditor(text: $ui.redactionSample)
                .font(.system(size: 12))
                .frame(height: PrivacyFilter.defaultSampleEditorHeight)
                .scrollContentBackground(.hidden)
                .padding(5)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(preview.output)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity,
                       minHeight: max(58, PrivacyFilter.defaultSampleEditorHeight - 14),
                       alignment: .leading)
                .padding(7)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
        section("上下文包") {
            pickerRow
            ForEach(settings.contextProfiles) { profile in
                profileRow(profile)
            }
            addProfileRow
        }
    }

    private var pickerRow: some View {
        HStack {
            Text("将项目背景、术语表和偏好合并进 System Prompt。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $settings.activeContextProfileID) {
                Text("不使用上下文").tag("")
                ForEach(settings.contextProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .frame(width: 170)
            .controlSize(.small)
            .onChange(of: settings.activeContextProfileID) { commit() }
        }
    }

    private func profileRow(_ profile: ContextProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: bindingForContextProfile(profile.id, \.isEnabled))
                    .labelsHidden()
                    .controlSize(.small)
                TextField("名称", text: bindingForContextProfile(profile.id, \.name, policy: .deferredSave), onCommit: commit)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                if settings.activeContextProfileID == profile.id {
                    Text("使用中")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
                Button {
                    if settings.activeContextProfileID == profile.id {
                        settings.activeContextProfileID = ""
                    }
                    settings.contextProfiles.removeAll { $0.id == profile.id }
                    commit()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("删除上下文包")
            }
            TextEditor(text: bindingForContextProfile(profile.id, \.content, policy: .deferredSave))
                .font(.system(size: 12))
                .frame(height: 58)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
        }
        .padding(7)
        .background(Color.primary.opacity(0.028))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var addProfileRow: some View {
        HStack(spacing: 8) {
            TextField("新上下文包名称", text: $ui.newContextName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            Button {
                addContextProfile()
            } label: {
                Label("添加", systemImage: "plus")
            }
            .controlSize(.small)
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

private extension View {
    func section<Content: View>(_ title: String,
                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snapAISurface(padding: 9, fillOpacity: SnapAIUI.quietFillOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func toggleRow(title: String,
                   description: String,
                   isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var compactDivider: some View {
        Divider()
            .opacity(0.55)
    }
}
