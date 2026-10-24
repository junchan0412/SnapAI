import AppKit
import SwiftUI
import SnapAILogic

struct QuickInputCropView: View {
    let image: NSImage
    let onCancel: () -> Void
    let onConfirm: (CGImage, CGRect, CGSize) -> Bool
    @State private var selection: CGRect = .zero
    @State private var failure: String?

    private var source: CGImage? { image.cgImage(forProposedRect: nil, context: nil, hints: nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("裁剪图片").font(.headline)
            Text("拖动图片或使用下方像素控件调整范围。确认后仅保留选区，已有 OCR 结果将失效。")
                .font(.callout).foregroundStyle(.secondary)
            if let source {
                let ratio = min(520 / CGFloat(source.width), 340 / CGFloat(source.height))
                let size = CGSize(width: CGFloat(source.width) * ratio, height: CGFloat(source.height) * ratio)
                ZStack {
                    Color.black.opacity(0.08)
                    canvas(source: source, size: size)
                }
                .frame(width: 520, height: 340)
                pixelControls(source: source, size: size)
                HStack {
                    if let rect = ImageCrop.pixelRect(selection: selection, displaySize: size,
                                                       pixelSize: CGSize(width: source.width, height: source.height)) {
                        Text("选区：\(Int(rect.width)) × \(Int(rect.height)) 像素")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("选择全图") { selection = CGRect(origin: .zero, size: size) }
                    Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                    Button("确认裁剪") {
                        if !onConfirm(source, selection, size) {
                            failure = "裁剪失败，原图已保留。请重新选择范围。"
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(ImageCrop.pixelRect(selection: selection, displaySize: size,
                                                   pixelSize: CGSize(width: source.width, height: source.height)) == nil)
                }
            } else {
                Text("无法读取图片，原图已保留。")
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder
    private func pixelControls(source: CGImage, size: CGSize) -> some View {
        let pixels = CGSize(width: source.width, height: source.height)
        if let rect = ImageCrop.pixelRect(selection: selection, displaySize: size, pixelSize: pixels) {
            HStack {
                pixelControl("左", value: Int(rect.minX), range: 0...(source.width - Int(rect.width)), size: size, pixels: pixels) {
                    var updated = rect
                    updated.origin.x = CGFloat($0)
                    return updated
                }
                pixelControl("上", value: Int(rect.minY), range: 0...(source.height - Int(rect.height)), size: size, pixels: pixels) {
                    var updated = rect
                    updated.origin.y = CGFloat($0)
                    return updated
                }
                pixelControl("宽", value: Int(rect.width), range: 1...(source.width - Int(rect.minX)), size: size, pixels: pixels) {
                    var updated = rect
                    updated.size.width = CGFloat($0)
                    return updated
                }
                pixelControl("高", value: Int(rect.height), range: 1...(source.height - Int(rect.minY)), size: size, pixels: pixels) {
                    var updated = rect
                    updated.size.height = CGFloat($0)
                    return updated
                }
            }
        }
    }

    private func pixelControl(_ title: String, value: Int, range: ClosedRange<Int>,
                              size: CGSize, pixels: CGSize,
                              updatedRect: @escaping (Int) -> CGRect) -> some View {
        Stepper(value: Binding(get: { value }, set: { next in
            if let updated = ImageCrop.displayRect(pixelRect: updatedRect(next),
                                                   displaySize: size, pixelSize: pixels) {
                selection = updated
            }
        }), in: range) {
            Text("\(title)：\(value)")
                .monospacedDigit()
        }
        .accessibilityLabel("裁剪\(title)，像素")
        .accessibilityValue("\(value)")
    }

    private func canvas(source: CGImage, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: source, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(selection)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Rectangle().stroke(.white, lineWidth: 1)
                .frame(width: selection.width, height: selection.height)
                .offset(x: selection.minX, y: selection.minY)
                .allowsHitTesting(false)
            ForEach(0..<4) { corner in
                handle(corner: corner, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .coordinateSpace(name: "cropCanvas")
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("cropCanvas"))
            .onChanged { value in
                selection = rectangle(from: value.startLocation, to: value.location, size: size)
            })
        .onAppear { selection = CGRect(origin: .zero, size: size) }
        .accessibilityLabel("图片裁剪选区，拖动重新选择或调整四角")
    }

    private func handle(corner: Int, size: CGSize) -> some View {
        let isRight = corner % 2 == 1
        let isBottom = corner >= 2
        let point = CGPoint(x: isRight ? selection.maxX : selection.minX,
                            y: isBottom ? selection.maxY : selection.minY)
        return Circle().fill(.white).shadow(radius: 1)
            .frame(width: 12, height: 12)
            .padding(5)
            .contentShape(Rectangle())
            .position(point)
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("cropCanvas"))
                .onChanged { value in
                    let anchor = CGPoint(x: isRight ? selection.minX : selection.maxX,
                                         y: isBottom ? selection.minY : selection.maxY)
                    let x = min(max(value.location.x, 0), size.width)
                    let y = min(max(value.location.y, 0), size.height)
                    let edge = CGPoint(x: isRight ? max(anchor.x + 1, x) : min(anchor.x - 1, x),
                                       y: isBottom ? max(anchor.y + 1, y) : min(anchor.y - 1, y))
                    selection = rectangle(from: anchor, to: edge, size: size)
                })
    }

    private func rectangle(from start: CGPoint, to end: CGPoint, size: CGSize) -> CGRect {
        let start = CGPoint(x: min(max(start.x, 0), size.width), y: min(max(start.y, 0), size.height))
        let end = CGPoint(x: min(max(end.x, 0), size.width), y: min(max(end.y, 0), size.height))
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}
