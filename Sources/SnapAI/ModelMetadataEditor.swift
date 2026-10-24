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
            return "上下文请输入 1–100,000,000 的整数 token 数。"
        }
        for price in [inputPrice, outputPrice] {
            let value = price.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && !(Double(value).map { $0.isFinite && (0...1_000_000).contains($0) } ?? false) {
                return "价格请输入 0–1,000,000 的数值，单位 USD / 百万 tokens。"
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模型能力与价格").font(.title2.bold())
            Text("\(provider.name) / \(entry.name)")
                .font(.callout).textSelection(.enabled)
            Form {
                Section("能力") {
                    Picker("视觉输入", selection: $metadata.supportsVision) {
                        Text("自动推断：\(inferred.supportsVision ? "支持" : "不支持")").tag(Bool?.none)
                        Text("支持（手工）").tag(Bool?.some(true))
                        Text("不支持（手工）").tag(Bool?.some(false))
                    }
                    Picker("推理", selection: $metadata.supportsReasoning) {
                        Text("自动推断：\(inferred.supportsReasoning ? "支持" : "不支持")").tag(Bool?.none)
                        Text("支持（手工）").tag(Bool?.some(true))
                        Text("不支持（手工）").tag(Bool?.some(false))
                    }
                    TextField("上下文 tokens", text: $contextTokens, prompt: Text("自动推断：\(inferred.contextTokens)"))
                    TextField("能力来源", text: $capabilitySource, prompt: Text("官方文档 URL 或说明"))
                    Text(provider.isAppleOnDevice
                         ? "来源：Apple 本机模型固定能力。"
                         : "未覆盖字段来自模型/供应商名称推断，未经服务商验证。手工覆盖立即用于路由和请求前检查；上下文留空恢复推断。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("价格 · USD / 百万 tokens") {
                    TextField("输入价格", text: $inputPrice, prompt: Text("未配置"))
                    TextField("输出价格", text: $outputPrice, prompt: Text("未配置"))
                    TextField("价格来源", text: $pricingSource, prompt: Text("报价页面 URL、日期或合同说明"))
                    Text(provider.isAppleOnDevice
                         ? "Apple 本机模型无 API 费用。"
                         : "两项价格均填写后才估算费用；未配置不代表免费。费用按此手工报价估算，不含缓存折扣、阶梯价或税费。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(provider.isAppleOnDevice)
            if let validationMessage {
                Text(validationMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("恢复自动推断并清除价格") {
                    metadata = ModelMetadataOverrides()
                    contextTokens = ""
                    inputPrice = ""
                    outputPrice = ""
                    capabilitySource = ""
                    pricingSource = ""
                }
                .disabled(provider.isAppleOnDevice)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    metadata.contextTokens = Int(contextTokens.trimmingCharacters(in: .whitespacesAndNewlines))
                    metadata.inputUSDPerMillionTokens = Double(inputPrice.trimmingCharacters(in: .whitespacesAndNewlines))
                    metadata.outputUSDPerMillionTokens = Double(outputPrice.trimmingCharacters(in: .whitespacesAndNewlines))
                    metadata.capabilitySource = capabilitySource
                    metadata.pricingSource = pricingSource
                    onSave(metadata.sanitized)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
        }
        .padding(20)
        .frame(width: 560, height: 650)
    }
}
