import AppKit
import CoreGraphics

// TokenUsage 应用图标生成器：CoreGraphics 矢量绘制，输出
//   1) macOS iconset（Configs/Resources/AppIcon.icns）
//   2) iOS 单尺寸 1024 AppIcon（Sources/TokenUsageiOS/Assets.xcassets）
// 运行：swift Scripts/make-icon.swift
// 设计：深色渐变底 + 60% 用量进度环（绿→琥珀，12 点起顺时针）+ 中央闪电（消耗隐喻）

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot = scriptDir.deletingLastPathComponent()

enum Variant { case mac, ios }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func render(variant: Variant, canvas: Int) -> CGImage? {
    let S = CGFloat(canvas)
    guard let ctx = CGContext(
        data: nil, width: canvas, height: canvas,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // 形状边界：mac = 居中 squircle（824/1024），ios = 全幅方图
    let margin: CGFloat = variant == .mac ? S * 0.0977 : 0
    let shape = S - margin * 2
    let shapeRect = CGRect(x: margin, y: margin, width: shape, height: shape)
    let corner = shape * 0.225
    let bgPath = CGPath(roundedRect: shapeRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // 背景：竖向渐变 + 顶部柔光
    ctx.saveGState()
    if variant == .mac {
        ctx.addPath(bgPath)
        ctx.clip()
    }
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x2A3441), color(0x10151D)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: S / 2, y: S * 0.96), startRadius: 0,
        endCenter: CGPoint(x: S / 2, y: S * 0.96), endRadius: shape * 0.8,
        options: []
    )
    ctx.restoreGState()

    // 边缘细描边（mac），深色桌面上更有轮廓
    if variant == .mac {
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.setStrokeColor(color(0xFFFFFF, 0.07))
        ctx.setLineWidth(S * 0.003)
        ctx.strokePath()
        ctx.restoreGState()
    }

    let cx = shapeRect.midX
    let cy = shapeRect.midY
    let ringR = shape * 0.29
    let lineWidth = shape * 0.08

    // 轨道环（带投影）
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -shape * 0.012),
        blur: shape * 0.04,
        color: CGColor(gray: 0, alpha: 0.45)
    )
    ctx.setStrokeColor(color(0xFFFFFF, 0.12))
    ctx.setLineWidth(lineWidth)
    ctx.strokeEllipse(in: CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2))
    ctx.restoreGState()

    // 60% 用量弧：12 点方向顺时针 216°，渐变描边（描边路径转区域后填渐变）
    ctx.saveGState()
    let arc = CGMutablePath()
    arc.addArc(
        center: CGPoint(x: cx, y: cy), radius: ringR,
        startAngle: .pi / 2, endAngle: .pi / 2 - 1.2 * .pi,
        clockwise: true, transform: .identity
    )
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.addPath(arc)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let arcGrad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x4ADE80), color(0xFBBF24)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        arcGrad,
        start: CGPoint(x: cx - ringR, y: cy + ringR),
        end: CGPoint(x: cx + ringR, y: cy - ringR),
        options: []
    )
    ctx.restoreGState()

    // 中央闪电：先实心带投影，再裁剪叠渐变
    let h = shape * 0.17
    let pts: [CGPoint] = [
        CGPoint(x: 0.30 * h, y: 1.00 * h),
        CGPoint(x: -0.50 * h, y: -0.06 * h),
        CGPoint(x: -0.09 * h, y: -0.06 * h),
        CGPoint(x: -0.30 * h, y: -1.00 * h),
        CGPoint(x: 0.50 * h, y: 0.10 * h),
        CGPoint(x: 0.09 * h, y: 0.10 * h),
    ]
    let bolt = CGMutablePath()
    bolt.move(to: CGPoint(x: cx + pts[0].x, y: cy + pts[0].y))
    for p in pts.dropFirst() {
        bolt.addLine(to: CGPoint(x: cx + p.x, y: cy + p.y))
    }
    bolt.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -shape * 0.008),
        blur: shape * 0.03,
        color: CGColor(gray: 0, alpha: 0.4)
    )
    ctx.addPath(bolt)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bolt)
    ctx.clip()
    let boltGrad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFFFFFF), color(0xD7E2EE)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(boltGrad, start: CGPoint(x: cx, y: cy + h), end: CGPoint(x: cx, y: cy - h), options: [])
    ctx.restoreGState()

    return ctx.makeImage()
}

func resized(_ image: CGImage, to px: Int) -> CGImage? {
    let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    ctx?.interpolationQuality = .high
    ctx?.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx?.makeImage()
}

func savePNG(_ image: CGImage, url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

let fm = FileManager.default
let buildDir = repoRoot.appendingPathComponent("build/icon")
try? fm.createDirectory(at: buildDir.appendingPathComponent("AppIcon.iconset"), withIntermediateDirectories: true)

let macMaster = render(variant: .mac, canvas: 1024)!
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in sizes {
    let image = px == 1024 ? macMaster : resized(macMaster, to: px)!
    savePNG(image, url: buildDir.appendingPathComponent("AppIcon.iconset/\(name)"))
}
savePNG(macMaster, url: buildDir.appendingPathComponent("preview-512.png"))

// iconset → icns
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    buildDir.appendingPathComponent("AppIcon.iconset").path,
    "-o", repoRoot.appendingPathComponent("Configs/Resources/AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil 失败")
}

// iOS 单尺寸 1024 AppIcon（系统自带圆角遮罩，无需预裁圆角）
let iosDir = repoRoot.appendingPathComponent("Sources/TokenUsageiOS/Assets.xcassets/AppIcon.appiconset")
try? fm.createDirectory(at: iosDir, withIntermediateDirectories: true)
let iosMaster = render(variant: .ios, canvas: 1024)!
savePNG(iosMaster, url: iosDir.appendingPathComponent("icon-1024.png"))
let contents = """
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try contents.write(to: iosDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("图标已生成：")
print("  \(repoRoot.path)/Configs/Resources/AppIcon.icns")
print("  \(iosDir.path)/icon-1024.png")
print("  预览：\(buildDir.appendingPathComponent("preview-512.png").path)")
