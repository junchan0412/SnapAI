import SnapAILogic
import SwiftUI

struct ModelMetadataEditor: View {
    let provider: AIProvider
    let entry: AIModelEntry
    let onSave: (ModelMetadataOverrides) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var metadata: ModelMetadataOverrides
    @State private var contextTokens: String
    @State private var inputPrice: String
    @State private var outputPrice: String
    @State private var capabilitySource: String
    @State private var pricingSource: String

    init(provider: AIProvider, entry: AIModelEntry, onSave: @escaping (ModelMetadataOverrides) -> Void) {
        self.provider = provider
        self.entry = entry
        self.onSave = onSave
        _metadata = State(initialValue: entry.metadata)
        _contextTokens = State(initialValue: entry.metadata.contextTokens.map(String.init) ?? "")
        _inputPrice = State(initialValue: entry.metadata.inputUSDPerMillionTokens.map { String($0) } ?? "")
        _outputPrice = State(initialValue: entry.metadata.outputUSDPerMillionTokens.map { String($0) } ?? "")
        _capabilitySource = State(initialValue: entry.metadata.capabilitySource ?? "")
        _pricingSource = State(initialValue: entry.metadata.pricingSource ?? "")
    }

    private var inferred: ModelCapability {
        ModelCapabilityRegistry.capability(for: entry.name, providerName: provider.name)
    }

    private var validationMessage: String? {
        let context = contextTokens.trimmingCharacters(in: .whitespacesAndNewlines)
        if !context.isEmpty && !(Int(context).map { (1...100_000_000).contains($0) } ?? false) {
            return "上下文窗口请填写 1 – 100,000,000 之间的整数。"
        }
        for price in [inputPrice, outputPrice] {
            let value = price.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && !(Double(value).map { $0.isFinite && (0...1_000_000).contains($0) } ?? false) {
                return "单价请填写 0 – 1,000,000 之间的数字（USD / 百万 tokens）。"
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("模型能力与单价覆盖")
                        .font(SnapAIUI.Typography.windowTitle)
                    Text("\(provider.name) · \(entry.name)")
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            SnapAIFormDivider(inset: 0)

            Form {
                Section("能力属性（用于自动路由与识图检查）") {
                    Picker("视觉识图", selection: $metadata.supportsVision) {
                        Text("自动推断（\(inferred.supportsVision ? "支持" : "不支持")）").tag(Bool?.none)
                        Text("支持").tag(Bool?.some(true))
                        Text("不支持").tag(Bool?.some(false))
                    }
                    Picker("深度推理", selection: $metadata.supportsReasoning) {
                        Text("自动推断（\(inferred.supportsReasoning ? "支持" : "不支持")）").tag(Bool?.none)
                        Text("支持").tag(Bool?.some(true))
                        Text("不支持").tag(Bool?.some(false))
                    }
                    TextField("上下文窗口 (Tokens)", text: $contextTokens, prompt: Text("默认推断：\(inferred.contextTokens)"))
                    TextField("备注来源（可选）", text: $capabilitySource, prompt: Text("如官方文档链接"))
                }

                Section("单价（USD / 百万 Tokens，用于估算花费）") {
                    TextField("输入单价", text: $inputPrice, prompt: Text("未设置"))
                    TextField("输出单价", text: $outputPrice, prompt: Text("未设置"))
                    TextField("报价备注（可选）", text: $pricingSource, prompt: Text("如官网定价日期"))
                }
            }
            .formStyle(.grouped)
            .disabled(provider.isAppleOnDevice)

            if let validationMessage {
                Text(validationMessage)
                    .font(SnapAIUI.Typography.metaText)
                    .foregroundStyle(SnapAIUI.StatusColor.error)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            SnapAIFormDivider(inset: 0)

            HStack {
                Button("恢复默认推断") {
                    metadata = ModelMetadataOverrides()
                    contextTokens = ""
                    inputPrice = ""
                    outputPrice = ""
                    capabilitySource = ""
                    pricingSource = ""
                }
                .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                .disabled(provider.isAppleOnDevice)

                Spacer()

                Button("取消") { dismiss() }
                    .buttonStyle(SnapAISecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button("保存") {
                    metadata.contextTokens = Int(contextTokens.trimmingCharacters(in: .whitespacesAndNewlines))
                    metadata.inputUSDPerMillionTokens = Double(inputPrice.trimmingCharacters(in: .whitespacesAndNewlines))
                    metadata.outputUSDPerMillionTokens = Double(outputPrice.trimmingCharacters(in: .whitespacesAndNewlines))
                    metadata.capabilitySource = capabilitySource
                    metadata.pricingSource = pricingSource
                    onSave(metadata.sanitized)
                    dismiss()
                }
                .buttonStyle(SnapAIPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 540)
    }
}
