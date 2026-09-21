import AppKit
import SwiftUI
import SnapAILogic

struct QuickInputView: View {
    @ObservedObject var model: QuickInputModel
    @ObservedObject private var settings: AppSettings
    var onClose: () -> Void
    var onCapture: () -> Void

    init(model: QuickInputModel, onClose: @escaping () -> Void, onCapture: @escaping () -> Void) {
        self.model = model
        self.settings = model.settings
        self.onClose = onClose
        self.onCapture = onCapture
    }

    private var currentAction: AIAction? {
        settings.enabledActions.first(where: { $0.id == model.actionID })
            ?? settings.enabledActions.first
    }

    private var canSubmit: Bool {
        currentAction != nil && !model.isCapturing && !model.didJustSend
            && (!model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.imageData != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 12) {
                QuickPromptEditor(
                    text: $model.text,
                    placeholder: model.imagePreview == nil
                        ? "写下问题，或贴入一段文字…"
                        : "想了解这张图片的什么？",
                    onSubmit: { if canSubmit { model.submit() } }
                )
                .frame(minHeight: 144, idealHeight: 160, maxHeight: .infinity)
                .snapAIGlassField(radius: 12)

                if let preview = model.imagePreview {
                    QuickInputAttachmentRow(image: preview,
                                            detail: model.imageNotice?.message,
                                            onRemove: model.clearImage)
                }
                if let notice = model.imageNotice, notice.isWarning {
                    Label(notice.message, systemImage: notice.systemImage)
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(SnapAIUI.StatusColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if currentAction == nil {
                    Label("先在设置中启用一个动作，即可发送提问。", systemImage: "info.circle")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(SnapAIUI.edgePadding)
            footer
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 300)
        .background(SnapAIUI.Surface.canvas)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("快捷提问")
                    .font(SnapAIUI.Typography.panelTitle)
                Text(settings.model.isEmpty ? "SnapAI" : settings.model)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            actionMenu
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(SnapAIIconButtonStyle(circular: false))
            .help("关闭快捷提问 (Esc)")
            .accessibilityLabel("关闭快捷提问")
        }
        .padding(.horizontal, SnapAIUI.edgePadding)
        .padding(.vertical, 16)
        .snapAIChrome()
    }

    private var actionMenu: some View {
        Menu {
            ForEach(settings.enabledActions) { action in
                Button {
                    model.actionID = action.id
                } label: {
                    if action.id == currentAction?.id {
                        Label(action.name, systemImage: "checkmark")
                    } else {
                        Label(action.name, systemImage: action.icon.isEmpty ? "wand.and.stars" : action.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentAction?.name ?? "选择动作")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(SnapAIUI.Typography.toolbarLabel)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .snapAIGlassPill(tint: .secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: 160)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(settings.enabledActions.isEmpty)
        .help("选择本次提问使用的动作")
        .accessibilityLabel("当前动作：\(currentAction?.name ?? "未选择")")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onCapture) {
                HStack(spacing: 6) {
                    if model.isCapturing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "camera")
                    }
                    Text(model.isCapturing ? "截图中" : "截图")
                }
            }
            .disabled(model.isCapturing)
            .help("截取当前屏幕并附加到提问")
            Button(action: model.pasteImageFromClipboard) {
                Label("粘贴图片", systemImage: "photo.on.rectangle")
            }
            .disabled(model.isCapturing)
            .help("添加剪贴板中的图片")
            Spacer(minLength: 8)
            if let status = model.transientStatus {
                Text(status)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(SnapAIUI.StatusColor.success)
                    .lineLimit(1)
            } else {
                HStack(spacing: 4) {
                    SnapAIKeycap(text: "⇧↩")
                    Text("换行")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Button { model.submit() } label: {
                HStack(spacing: 7) {
                    Text(model.didJustSend ? "已发送" : "发送")
                    Image(systemName: model.didJustSend ? "checkmark" : "return")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(SnapAIPrimaryButtonStyle())
            .disabled(!canSubmit)
            .help("发送提问 (↩)")
            .accessibilityLabel(model.didJustSend ? "已发送" : "发送提问")
        }
        .buttonStyle(.borderless)
        .font(SnapAIUI.Typography.toolbarLabel)
        .padding(.horizontal, SnapAIUI.edgePadding)
        .padding(.vertical, 14)
        .snapAIChrome()
    }
}

private struct QuickInputAttachmentRow: View {
    let image: NSImage
    let detail: String?
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 48)
                .background(SnapAIUI.Surface.content)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel("已附加图片的预览")
            VStack(alignment: .leading, spacing: 4) {
                Text("已附加 1 张图片")
                    .font(.system(size: 13, weight: .medium))
                Text("将随问题一起发送")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onRemove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(SnapAIIconButtonStyle(circular: false))
            .help("移除图片附件")
            .accessibilityLabel("移除图片附件")
        }
        .padding(10)
        .snapAIGlassCard(radius: 10)
        .help(detail ?? "图片将随本次提问发送")
    }
}
