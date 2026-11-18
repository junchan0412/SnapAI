import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

struct IconPalette {
    let id: String
    // Outer squircle gradient (top -> bottom)
    let baseTop: UInt32
    let baseBottom: UInt32
    let baseRimAlpha: CGFloat
    // Tilted glass card tint
    let glassTint: UInt32
    let glassAlpha: CGFloat
    // Inner jewel gradient (top-left -> middle -> bottom-right)
    let jewelStart: UInt32
    let jewelMid: UInt32
    let jewelEnd: UInt32
    // Radial inner bloom
    let bloomColor: UInt32
    let bloomAlpha: CGFloat
    // Foreground emblem (star & brackets)
    let starTop: UInt32
    let starBottom: UInt32
    let bracketColor: UInt32
    let bracketAlpha: CGFloat
}

enum IconTheme: String, CaseIterable {
    case aurora
    case obsidian
    case emerald
    case sunset

    func palette(dark: Bool) -> IconPalette {
        switch (self, dark) {
        case (.aurora, false):
            return IconPalette(
                id: "aurora",
                baseTop: 0xFAFBFD, baseBottom: 0xE5ECF8, baseRimAlpha: 0.95,
                glassTint: 0x6366F1, glassAlpha: 0.16,
                jewelStart: 0x3B82F6, jewelMid: 0x4F46E5, jewelEnd: 0x7C3AED,
                bloomColor: 0x67E8F9, bloomAlpha: 0.36,
                starTop: 0xFFFFFF, starBottom: 0xE0E7FF,
                bracketColor: 0xFFFFFF, bracketAlpha: 0.88
            )
        case (.aurora, true):
            return IconPalette(
                id: "aurora",
                baseTop: 0x161D2F, baseBottom: 0x0B0F1A, baseRimAlpha: 0.18,
                glassTint: 0x818CF8, glassAlpha: 0.18,
                jewelStart: 0x2563EB, jewelMid: 0x4F46E5, jewelEnd: 0x9333EA,
                bloomColor: 0x38BDF8, bloomAlpha: 0.45,
                starTop: 0xFFFFFF, starBottom: 0xC7D2FE,
                bracketColor: 0xE0E7FF, bracketAlpha: 0.90
            )
        case (.obsidian, false):
            return IconPalette(
                id: "obsidian",
                baseTop: 0xF7F8FA, baseBottom: 0xDCE1EA, baseRimAlpha: 0.92,
                glassTint: 0x52525B, glassAlpha: 0.14,
                jewelStart: 0x27272A, jewelMid: 0x18181B, jewelEnd: 0x09090B,
                bloomColor: 0xF59E0B, bloomAlpha: 0.28,
                starTop: 0xFEF3C7, starBottom: 0xF59E0B,
                bracketColor: 0xF4F4F5, bracketAlpha: 0.82
            )
        case (.obsidian, true):
            return IconPalette(
                id: "obsidian",
                baseTop: 0x181920, baseBottom: 0x09090C, baseRimAlpha: 0.16,
                glassTint: 0xF59E0B, glassAlpha: 0.14,
                jewelStart: 0x2A2B33, jewelMid: 0x18191F, jewelEnd: 0x101014,
                bloomColor: 0xFBBF24, bloomAlpha: 0.34,
                starTop: 0xFEF9C3, starBottom: 0xF59E0B,
                bracketColor: 0xFDE68A, bracketAlpha: 0.84
            )
        case (.emerald, false):
            return IconPalette(
                id: "emerald",
                baseTop: 0xF5FCF9, baseBottom: 0xDCF2E8, baseRimAlpha: 0.94,
                glassTint: 0x10B981, glassAlpha: 0.16,
                jewelStart: 0x10B981, jewelMid: 0x059669, jewelEnd: 0x0F766E,
                bloomColor: 0x6EE7B7, bloomAlpha: 0.36,
                starTop: 0xFFFFFF, starBottom: 0xD1FAE5,
                bracketColor: 0xFFFFFF, bracketAlpha: 0.88
            )
        case (.emerald, true):
            return IconPalette(
                id: "emerald",
                baseTop: 0x132822, baseBottom: 0x091310, baseRimAlpha: 0.16,
                glassTint: 0x34D399, glassAlpha: 0.16,
                jewelStart: 0x10B981, jewelMid: 0x059669, jewelEnd: 0x065F46,
                bloomColor: 0x6EE7B7, bloomAlpha: 0.40,
                starTop: 0xFFFFFF, starBottom: 0xA7F3D0,
                bracketColor: 0xD1FAE5, bracketAlpha: 0.88
            )
        case (.sunset, false):
            return IconPalette(
                id: "sunset",
                baseTop: 0xFFF9F6, baseBottom: 0xFCE6DD, baseRimAlpha: 0.94,
                glassTint: 0xF43F5E, glassAlpha: 0.15,
                jewelStart: 0xFB923C, jewelMid: 0xF43F5E, jewelEnd: 0xBE185D,
                bloomColor: 0xFDE047, bloomAlpha: 0.30,
                starTop: 0xFFFFFF, starBottom: 0xFFE4E6,
                bracketColor: 0xFFFFFF, bracketAlpha: 0.88
            )
        case (.sunset, true):
            return IconPalette(
                id: "sunset",
                baseTop: 0x26141D, baseBottom: 0x12090E, baseRimAlpha: 0.16,
                glassTint: 0xFB7185, glassAlpha: 0.16,
                jewelStart: 0xF97316, jewelMid: 0xE11D48, jewelEnd: 0x9D174D,
                bloomColor: 0xFDBA74, bloomAlpha: 0.38,
                starTop: 0xFFFFFF, starBottom: 0xFECDD3,
                bracketColor: 0xFFE4E6, bracketAlpha: 0.88
            )
        }
    }
}

func cgColor(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255,
            alpha: alpha)
}

/// 连续曲率圆角矩形路径（贴近 macOS 原生超椭圆图标曲线）
func squirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
    let bezier = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let path = CGMutablePath()
    var points = [NSPoint](repeating: .zero, count: 3)
    for i in 0..<bezier.elementCount {
        switch bezier.element(at: i, associatedPoints: &points) {
        case .moveTo:
            path.move(to: points[0])
        case .lineTo:
            path.addLine(to: points[0])
        case .curveTo, .cubicCurveTo:
            path.addCurve(to: points[2], control1: points[0], control2: points[1])
        case .quadraticCurveTo:
            path.addQuadCurve(to: points[1], control: points[0])
        case .closePath:
            path.closeSubpath()
        @unknown default:
            break
        }
    }
    return path
}

/// 四芒星路径（平滑内凹弧线）
func fourPointStarPath(center: CGPoint, outerRadius: CGFloat, waistRadius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let top = CGPoint(x: center.x, y: center.y + outerRadius)
    let right = CGPoint(x: center.x + outerRadius, y: center.y)
    let bottom = CGPoint(x: center.x, y: center.y - outerRadius)
    let left = CGPoint(x: center.x - outerRadius, y: center.y)

    let cTR = CGPoint(x: center.x + waistRadius, y: center.y + waistRadius)
    let cBR = CGPoint(x: center.x + waistRadius, y: center.y - waistRadius)
    let cBL = CGPoint(x: center.x - waistRadius, y: center.y - waistRadius)
    let cTL = CGPoint(x: center.x - waistRadius, y: center.y + waistRadius)

    path.move(to: top)
    path.addQuadCurve(to: right, control: cTR)
    path.addQuadCurve(to: bottom, control: cBR)
    path.addQuadCurve(to: left, control: cBL)
    path.addQuadCurve(to: top, control: cTL)
    path.closeSubpath()
    return path
}

func renderIcon(theme: IconTheme, dark: Bool, pixels: Int, destination: URL) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    guard let nsCtx = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Failed to create graphics context")
    }
    let ctx = nsCtx.cgContext
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let p = theme.palette(dark: dark)

    ctx.saveGState()
    let scale = CGFloat(pixels) / 1024.0
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high

    // 1. Apple 标准 macOS 图标外轮廓：1024 画布内居中 824×824 圆角矩形 + 柔和投影
    let outerRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let outerPath = squirclePath(in: outerRect, radius: 185.4)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12),
                  blur: 28,
                  color: cgColor(0x000000, alpha: dark ? 0.46 : 0.20))
    ctx.addPath(outerPath)
    ctx.setFillColor(cgColor(p.baseBottom))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. 外壳主渐变填充 + 环境内发光
    ctx.saveGState()
    ctx.addPath(outerPath)
    ctx.clip()

    let baseGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(p.baseTop), cgColor(p.baseBottom)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(baseGrad,
                           start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 100),
                           options: [])

    // 柔和环境光晕渗透到外壳背景
    let ambientGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(p.jewelMid, alpha: dark ? 0.24 : 0.10),
                 cgColor(p.jewelMid, alpha: 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(ambientGrad,
                           startCenter: CGPoint(x: 512, y: 490),
                           startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 490),
                           endRadius: 420,
                           options: [.drawsBeforeStartLocation])

    // 3. 背层微倾透景玻璃卡（营造空间纵深）
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: -0.15) // -8.6 deg
    let backCardRect = CGRect(x: -258, y: -258, width: 516, height: 516)
    let backCardPath = squirclePath(in: backCardRect, radius: 120)
    ctx.addPath(backCardPath)
    ctx.setFillColor(cgColor(p.glassTint, alpha: p.glassAlpha))
    ctx.fillPath()
    ctx.addPath(backCardPath)
    ctx.setStrokeColor(cgColor(dark ? 0xFFFFFF : p.jewelMid, alpha: dark ? 0.14 : 0.18))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // 4. 中心主宝石棱镜（520×520）+ 立体投影
    let jewelRect = CGRect(x: 252, y: 252, width: 520, height: 520)
    let jewelPath = squirclePath(in: jewelRect, radius: 124)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18),
                  blur: 36,
                  color: cgColor(dark ? 0x000000 : p.jewelEnd, alpha: dark ? 0.55 : 0.30))
    ctx.addPath(jewelPath)
    ctx.setFillColor(cgColor(p.jewelMid))
    ctx.fillPath()
    ctx.restoreGState()

    // 宝石内部对角渐变 + 极光高光 + 顶部玻璃反射弧
    ctx.saveGState()
    ctx.addPath(jewelPath)
    ctx.clip()

    let jewelGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(p.jewelStart), cgColor(p.jewelMid), cgColor(p.jewelEnd)] as CFArray,
        locations: [0.0, 0.52, 1.0]
    )!
    ctx.drawLinearGradient(jewelGrad,
                           start: CGPoint(x: 260, y: 764),
                           end: CGPoint(x: 764, y: 260),
                           options: [])

    let bloomGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(p.bloomColor, alpha: p.bloomAlpha),
                 cgColor(p.bloomColor, alpha: 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(bloomGrad,
                           startCenter: CGPoint(x: 390, y: 650),
                           startRadius: 0,
                           endCenter: CGPoint(x: 430, y: 610),
                           endRadius: 310,
                           options: [.drawsBeforeStartLocation])

    // 顶部微晶光泽层
    let glossPath = CGMutablePath()
    glossPath.move(to: CGPoint(x: 240, y: 780))
    glossPath.addLine(to: CGPoint(x: 784, y: 780))
    glossPath.addLine(to: CGPoint(x: 784, y: 545))
    glossPath.addQuadCurve(to: CGPoint(x: 240, y: 495), control: CGPoint(x: 512, y: 590))
    glossPath.closeSubpath()
    ctx.saveGState()
    ctx.addPath(glossPath)
    ctx.clip()
    let glossGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(0xFFFFFF, alpha: 0.22), cgColor(0xFFFFFF, alpha: 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(glossGrad,
                           start: CGPoint(x: 512, y: 772),
                           end: CGPoint(x: 512, y: 495),
                           options: [])
    ctx.restoreGState()

    // 5. 四角「Snap 取词/取景框」精工折角
    let bracketInset: CGFloat = 330
    let bracketMax: CGFloat = 694
    let arm: CGFloat = 66
    let cornerR: CGFloat = 24
    let strokeW: CGFloat = max(24, 1024 / CGFloat(max(pixels, 32)))

    ctx.saveGState()
    ctx.setStrokeColor(cgColor(p.bracketColor, alpha: p.bracketAlpha))
    ctx.setLineWidth(strokeW)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // 左上
    let tl = CGMutablePath()
    tl.move(to: CGPoint(x: bracketInset, y: bracketMax - arm))
    tl.addArc(tangent1End: CGPoint(x: bracketInset, y: bracketMax),
              tangent2End: CGPoint(x: bracketInset + arm, y: bracketMax),
              radius: cornerR)
    tl.addLine(to: CGPoint(x: bracketInset + arm, y: bracketMax))
    ctx.addPath(tl)
    ctx.strokePath()

    // 右上
    let tr = CGMutablePath()
    tr.move(to: CGPoint(x: bracketMax - arm, y: bracketMax))
    tr.addArc(tangent1End: CGPoint(x: bracketMax, y: bracketMax),
              tangent2End: CGPoint(x: bracketMax, y: bracketMax - arm),
              radius: cornerR)
    tr.addLine(to: CGPoint(x: bracketMax, y: bracketMax - arm))
    ctx.addPath(tr)
    ctx.strokePath()

    // 左下
    let bl = CGMutablePath()
    bl.move(to: CGPoint(x: bracketInset, y: bracketInset + arm))
    bl.addArc(tangent1End: CGPoint(x: bracketInset, y: bracketInset),
              tangent2End: CGPoint(x: bracketInset + arm, y: bracketInset),
              radius: cornerR)
    bl.addLine(to: CGPoint(x: bracketInset + arm, y: bracketInset))
    ctx.addPath(bl)
    ctx.strokePath()

    // 右下
    let br = CGMutablePath()
    br.move(to: CGPoint(x: bracketMax - arm, y: bracketInset))
    br.addArc(tangent1End: CGPoint(x: bracketMax, y: bracketInset),
              tangent2End: CGPoint(x: bracketMax, y: bracketInset + arm),
              radius: cornerR)
    br.addLine(to: CGPoint(x: bracketMax, y: bracketInset + arm))
    ctx.addPath(br)
    ctx.strokePath()
    ctx.restoreGState()

    // 6. 中心立体 AI 四芒星 + 右上伴星
    let mainStar = fourPointStarPath(center: CGPoint(x: 500, y: 500), outerRadius: 132, waistRadius: 30)
    let subStar = fourPointStarPath(center: CGPoint(x: 604, y: 606), outerRadius: 42, waistRadius: 10)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8),
                  blur: 20,
                  color: cgColor(0x000000, alpha: 0.25))
    ctx.addPath(mainStar)
    ctx.addPath(subStar)
    ctx.setFillColor(cgColor(p.starTop))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(mainStar)
    ctx.addPath(subStar)
    ctx.clip()
    let starGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [cgColor(p.starTop), cgColor(p.starBottom)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(starGrad,
                           start: CGPoint(x: 512, y: 650),
                           end: CGPoint(x: 512, y: 368),
                           options: [])
    ctx.restoreGState()

    // 宝石内高光描边
    let jewelBorder = squirclePath(in: jewelRect.insetBy(dx: 1.5, dy: 1.5), radius: 122.5)
    ctx.addPath(jewelBorder)
    ctx.setStrokeColor(cgColor(0xFFFFFF, alpha: 0.30))
    ctx.setLineWidth(3)
    ctx.strokePath()

    ctx.restoreGState() // end jewel clip

    // 外壳边缘高光描边
    let outerBorder = squirclePath(in: outerRect.insetBy(dx: 2, dy: 2), radius: 183.4)
    ctx.addPath(outerBorder)
    ctx.setStrokeColor(cgColor(0xFFFFFF, alpha: p.baseRimAlpha))
    ctx.setLineWidth(4)
    ctx.strokePath()

    ctx.restoreGState() // end outer clip
    ctx.restoreGState() // end scale

    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}

func buildIcns(theme: IconTheme, dark: Bool, icnsDestination: URL) throws {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }
    for size in [16, 32, 128, 256, 512] {
        try renderIcon(theme: theme, dark: dark, pixels: size,
                       destination: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
        try renderIcon(theme: theme, dark: dark, pixels: size * 2,
                       destination: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", icnsDestination.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
}

for theme in IconTheme.allCases {
    for dark in [false, true] {
        let suffix = dark ? "Dark" : "Light"
        let capitalized = theme.rawValue.prefix(1).uppercased() + theme.rawValue.dropFirst()
        let themedPNG = root.appendingPathComponent("AppIcon-\(capitalized)-\(suffix).png")
        try renderIcon(theme: theme, dark: dark, pixels: 1024, destination: themedPNG)

        // 默认主图标同步写入 AppIconLight / AppIconDark (.png + .icns)
        if theme == .aurora {
            let defaultName = "AppIcon\(suffix)"
            try renderIcon(theme: theme, dark: dark, pixels: 1024,
                           destination: root.appendingPathComponent("\(defaultName).png"))
            try buildIcns(theme: theme, dark: dark,
                          icnsDestination: root.appendingPathComponent("\(defaultName).icns"))
        }
    }
}
print("Generated 4 icon themes (Light + Dark PNGs & default ICNS) in \(root.path)")
