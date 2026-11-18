import AppKit
import SwiftUI
import SnapAILogic

struct QuickInputView: View {
    @ObservedObject var model: QuickInputModel
    @ObservedObject private var settings: AppSettings
    var onClose: () -> Void
    var onCapture: (ScreenCaptureMode) -> Void

    @State private var editorHeight: CGFloat = 56
    @State private var showOCRPreview = false

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
        VStack(alignment: .leading, spacing: 0) {
            inputCanvas

            if let preview = model.imagePreview {
                attachmentSection(preview)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            if let notice = model.imageNotice, notice.isWarning {
                Label(notice.message, systemImage: notice.systemImage)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(SnapAIUI.StatusColor.warning)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if currentAction == nil {
                Label("请先在设置中启用至少一个动作。", systemImage: "info.circle")
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            SnapAIFormDivider(inset: 0)
            bottomControlBar
        }
        .frame(minWidth: 500, idealWidth: 560)
        .snapAIFloatingPanelSurface()
        .sheet(isPresented: $model.isCropping) {
            if let preview = model.imagePreview {
                QuickInputCropView(image: preview,
                                   onCancel: { model.isCropping = false },
                                   onConfirm: model.cropImage)
            }
        }
    }

    // MARK: - 无边框灵动输入区

    private var inputCanvas: some View {
        let placeholderText = model.imagePreview == nil
            ? SnapAIL10n.string("Ask a question, or paste text…")
            : SnapAIL10n.string("What would you like to know about this image?")
        return HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .topLeading) {
                QuickPromptEditor(
                    text: $model.text,
                    measuredHeight: $editorHeight,
                    placeholder: "",
                    minHeight: 56,
                    maxHeight: 200,
                    onSubmit: { if canSubmit { model.submit() } }
                )
                .frame(height: editorHeight)

                if model.text.isEmpty {
                    Text(placeholderText)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.leading, 4)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(SnapAIIconButtonStyle(size: 24, circular: true))
            .help(SnapAIL10n.string("Close Quick Input (Esc)"))
            .accessibilityLabel(SnapAIL10n.string("Close Quick Input (Esc)"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - 紧凑图片与 OCR 条

    private func attachmentSection(_ preview: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(SnapAIUI.Surface.border, lineWidth: 0.6)
                    }
                    .accessibilityLabel("已附加图片的预览")

                VStack(alignment: .leading, spacing: 3) {
                    ocrStatusSummary
                    Text(model.imageSubmissionDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Picker("本次图片发送方式", selection: Binding(
                    get: { model.imageInput.mode },
                    set: model.selectImageMode
                )) {
                    ForEach(QuickInputImageMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 176)
                .accessibilityLabel("本次图片发送方式")

                Button(action: { model.isCropping = true }) {
                    Image(systemName: "crop")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .help("裁剪图片")
                .accessibilityLabel("裁剪图片附件")

                Button(action: model.clearImage) {
                    Image(systemName: "trash")
                }
                .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
                .help("移除图片")
                .accessibilityLabel("移除图片附件")
            }

            ocrDetailRow
        }
        .padding(10)
        .snapAIGlassCard(radius: 9)
    }

    @ViewBuilder
    private var ocrStatusSummary: some View {
        switch model.imageInput.recognition {
        case .notStarted:
            HStack(spacing: 6) {
                Text("已附加截图")
                    .font(.system(size: 12, weight: .medium))
                Button("识别图中文字", action: model.recognizeImageText)
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        case .recognizing:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("正在识别文字…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .ready(let text):
            HStack(spacing: 6) {
                Label("已识别 \(text.count) 字", systemImage: "text.viewfinder")
                    .font(.system(size: 11.5, weight: .medium))
                if model.imageInput.mode.requiresRecognition {
                    Button(showOCRPreview ? "收起文字" : "查看文字") {
                        showOCRPreview.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }
        case .unavailable, .failed:
            HStack(spacing: 6) {
                Label(model.imageInput.recognition.failureMessage ?? "未能识别文字",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SnapAIUI.StatusColor.warning)
                    .lineLimit(1)
                Button("重试", action: model.recognizeImageText)
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                if model.imageInput.mode != .image {
                    Button("改发原图") { model.selectImageMode(.image) }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
        }
    }

    @ViewBuilder
    private var ocrDetailRow: some View {
        if case .ready(let text) = model.imageInput.recognition,
           model.imageInput.mode.requiresRecognition,
           showOCRPreview {
            ScrollView {
                Text(text)
                    .font(SnapAIUI.Typography.metaText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 76)
            .snapAIGlassField(radius: 6)
            .accessibilityLabel("本次将发送的 OCR 文字")
        }
    }

    // MARK: - 底部一体化工具条（动作切换 + 模型切换 + 截图粘贴 + 发送）

    private var bottomControlBar: some View {
        HStack(spacing: 6) {
            actionMenu
            modelMenu

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            screenshotMenu
            pasteImageButton

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
                        .foregroundStyle(.tertiary)
                }
            }

            Button { model.submit() } label: {
                HStack(spacing: 5) {
                    Text(model.didJustSend ? SnapAIL10n.string("Sent") : SnapAIL10n.string("Send"))
                    Image(systemName: model.didJustSend ? "checkmark" : "arrow.up")
                        .font(.system(size: 10.5, weight: .bold))
                }
            }
            .buttonStyle(SnapAIPrimaryButtonStyle(compact: true))
            .disabled(!canSubmit)
            .help(SnapAIL10n.string("Send Prompt (Return)"))
            .accessibilityLabel(model.didJustSend ? SnapAIL10n.string("Sent") : SnapAIL10n.string("Send Prompt (Return)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
            HStack(spacing: 5) {
                Image(systemName: currentAction?.icon.isEmpty == false ? currentAction!.icon : "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(currentAction?.name ?? "动作")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(SnapAIChipButtonStyle(active: true))
        .fixedSize()
        .disabled(settings.enabledActions.isEmpty)
        .help("切换提问动作")
        .accessibilityLabel("当前动作：\(currentAction?.name ?? "未选择")")
    }

    private var modelMenu: some View {
        let entries = settings.switchableEntries
        let title = settings.model.isEmpty ? "选择模型" : settings.model
        return Menu {
            if entries.isEmpty {
                Text("暂无可用模型（请先在设置中配置供应商）")
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, item in
                    Button {
                        settings.activate(providerID: item.provider.id,
                                          model: item.model,
                                          recordManualPreference: true)
                    } label: {
                        let isCurrent = item.provider.id == settings.activeProvider?.id && item.model == settings.model
                        if isCurrent {
                            Label("\(item.provider.name) · \(item.model)", systemImage: "checkmark")
                        } else {
                            Text("\(item.provider.name) · \(item.model)")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(SnapAIChipButtonStyle())
        .fixedSize()
        .help("快速切换当前 AI 模型")
        .accessibilityLabel("当前模型：\(title)")
    }

    private var screenshotMenu: some View {
        Menu {
            ForEach(ScreenCaptureMode.allCases) { mode in
                Button(mode.title) { onCapture(mode) }
            }
        } label: {
            Group {
                if model.isCapturing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "camera.viewfinder")
                }
            }
            .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.isCapturing)
        .help("截取选区、窗口或屏幕附加到提问")
        .accessibilityLabel("截图范围")
    }

    private var pasteImageButton: some View {
        Button(action: model.pasteImageFromClipboard) {
            Image(systemName: "photo.on.rectangle.angled")
        }
        .buttonStyle(SnapAIIconButtonStyle(size: 26, circular: false))
        .disabled(model.isCapturing)
        .help("粘贴剪贴板图片")
        .accessibilityLabel(SnapAIL10n.string("Paste Image"))
    }
}
