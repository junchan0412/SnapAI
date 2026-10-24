import AppKit
import SwiftUI
import SnapAILogic

struct QuickInputView: View {
    @ObservedObject var model: QuickInputModel
    @ObservedObject private var settings: AppSettings
    var onClose: () -> Void
    var onCapture: (ScreenCaptureMode) -> Void

    init(model: QuickInputModel, onClose: @escaping () -> Void, onCapture: @escaping (ScreenCaptureMode) -> Void) {
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
        currentAction != nil && !model.isCapturing && !model.isCropping && !model.didJustSend
            && model.canSubmitContent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    QuickPromptEditor(
                        text: $model.text,
                        placeholder: model.imagePreview == nil
                            ? SnapAIL10n.string("Ask a question, or paste text…")
                            : SnapAIL10n.string("What would you like to know about this image?"),
                        onSubmit: { if canSubmit { model.submit() } }
                    )
                    .frame(height: 160)
                    .snapAIGlassField(radius: 12)

                    if let preview = model.imagePreview {
                        QuickInputAttachmentRow(image: preview,
                                                detail: model.imageNotice?.message,
                                                submissionDetail: model.imageSubmissionDescription,
                                                onCrop: { model.isCropping = true },
                                                onRemove: model.clearImage)
                        imageSubmissionOptions
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
            }
            footer
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 300)
        .background(SnapAIUI.Surface.canvas)
        .sheet(isPresented: $model.isCropping) {
            if let preview = model.imagePreview {
                QuickInputCropView(image: preview,
                                   onCancel: { model.isCropping = false },
                                   onConfirm: model.cropImage)
            }
        }
    }

    private var imageSubmissionOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("本次图片发送方式", selection: Binding(
                get: { model.imageInput.mode },
                set: model.selectImageMode
            )) {
                ForEach(QuickInputImageMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("本次图片发送方式")

            switch model.imageInput.recognition {
            case .notStarted:
                Button("在本机识别文字", action: model.recognizeImageText)
                    .font(SnapAIUI.Typography.metaText)
            case .recognizing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(model.imageInput.mode == .image
                         ? "正在本机识别文字；可立即发送原图。"
                         : "正在本机识别文字，完成后可发送；也可改用原图。")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .ready(let text):
                Label("已在本机识别 \(text.count) 个字符", systemImage: "checkmark.circle")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                if model.imageInput.mode.requiresRecognition {
                    ScrollView {
                        Text(text)
                            .font(SnapAIUI.Typography.metaText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 88)
                    .background(SnapAIUI.Surface.content)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("本次将发送的 OCR 文字")
                }
            case .unavailable, .failed:
                Label(model.imageInput.recognition.failureMessage ?? "", systemImage: "exclamationmark.triangle")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(SnapAIUI.StatusColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("重新识别", action: model.recognizeImageText)
                    if model.imageInput.mode != .image {
                        Button("改用原图") { model.selectImageMode(.image) }
                    }
                }
                .font(SnapAIUI.Typography.metaText)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(SnapAIL10n.string("Quick Input"))
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
            .help(SnapAIL10n.string("Close Quick Input (Esc)"))
            .accessibilityLabel(SnapAIL10n.string("Close Quick Input (Esc)"))
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
            Menu {
                ForEach(ScreenCaptureMode.allCases) { mode in
                    Button(mode.title) { onCapture(mode) }
                }
            } label: {
                HStack(spacing: 6) {
                    if model.isCapturing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "camera")
                    }
                    Text(model.isCapturing ? SnapAIL10n.string("Capturing") : SnapAIL10n.string("Screenshot"))
                }
            }
            .disabled(model.isCapturing)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择区域、窗口或主屏幕；区域与窗口选择可按 Esc 取消。")
            .accessibilityLabel("截图范围")
            Button(action: model.pasteImageFromClipboard) {
                Label(SnapAIL10n.string("Paste Image"), systemImage: "photo.on.rectangle")
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
                    Text(model.didJustSend ? SnapAIL10n.string("Sent") : SnapAIL10n.string("Send"))
                    Image(systemName: model.didJustSend ? "checkmark" : "return")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(SnapAIPrimaryButtonStyle())
            .disabled(!canSubmit)
            .help(SnapAIL10n.string("Send Prompt (Return)"))
            .accessibilityLabel(model.didJustSend ? SnapAIL10n.string("Sent") : SnapAIL10n.string("Send Prompt (Return)"))
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
    let submissionDetail: String
    var onCrop: () -> Void
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
                Text("已保留 1 张图片")
                    .font(.system(size: 13, weight: .medium))
                Text(submissionDetail)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onCrop) {
                Image(systemName: "crop")
            }
            .buttonStyle(SnapAIIconButtonStyle(circular: false))
            .help("发送前裁剪图片")
            .accessibilityLabel("裁剪图片附件")
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
